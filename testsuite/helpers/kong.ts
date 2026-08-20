import * as crypto from "crypto";
import * as dns from "dns";
import * as fs from "fs";
import * as https from "https";
import * as path from "path";
import {
  APIRequestContext,
  APIResponse,
  request as playwrightRequest,
} from "playwright";
import logger from "./logger";
import { upstreamServiceDefaults } from "./upstream";

/** Kong Admin API — override with KONG_ADMIN_URL (compose / .env.e2e). */
export const KONG_ADMIN_URL =
  process.env.KONG_ADMIN_URL ?? "http://kong.localtest.me:8001";

/** Kong proxy (nginx → DP replicas) — override with KONG_PROXY_URL. */
export const KONG_PROXY_URL =
  process.env.KONG_PROXY_URL ?? "http://kong.localtest.me:8000";

/**
 * Kong TLS/mTLS proxy entry point (nginx stream passthrough → DP :8443 ssl,
 * client certs verified against the fixture client CA) — override with
 * KONG_PROXY_TLS_URL. Use {@link mtlsProxyRequest}, not bare fetches.
 */
export const KONG_PROXY_TLS_URL =
  process.env.KONG_PROXY_TLS_URL ?? "https://kong.localtest.me:8443";

/** Per-file Kong entity prefix — entropy so parallel Playwright workers cannot collide. */
export function uniquePrefix(base: string): string {
  return `${base}-${Date.now()}-${crypto.randomBytes(4).toString("hex")}`;
}

const base_service = {
  id: "00000000-0000-0000-0000-00000000000",
  name: "NAME",
  ...upstreamServiceDefaults,
};

const base_route = {
  id: "00000000-0000-0000-0000-00000000000",
  name: "NAME",
  hosts: ["kong.localtest.me"],
  paths: ["/001"],
  strip_path: true,
  methods: ["GET","POST"],
  service: {
    id: "",
  },
};

type KongProvisionResponse = {
  status: number;
  body: any;
};

export async function provisionNewService(
  request: APIRequestContext,
  baseURL: string,
  id: number,
  plugin: { name: string; overrides: {} },
  clientDetails: { clientId: string; clientSecret: string }
): Promise<string> {
  const unqId = id.toString().padStart(8, "0");
  const newId = id.toString().padStart(8, "0");

  const service = {
    ...base_service,
    ...{
      id: `${unqId}-0000-0000-0000-0000${newId}`,
      name: `svc-${unqId}-${newId}`,
    },
  };
  const route = {
    ...base_route,
    ...{
      id: `${unqId}-0000-0000-0000-0000${newId}`,
      // Kong 3 -- paths: [`~/${newId}/.*`],
      paths: [`/${newId}`],
      name: `svc-${unqId}-${newId}-route`,
      service: { id: service.id },
    },
  };
  const pluginConfig = {
    ...{ name: plugin.name, config: plugin.overrides },
    ...{ route: { id: route.id } },
  };

  if (plugin.name == "oidc") {
    pluginConfig.config["client_id"] = clientDetails.clientId;
    if (clientDetails.clientSecret === null) {
      pluginConfig.config["client_secret"] = "XX"; // can not be null or empty
    } else {
      pluginConfig.config["client_secret"] = clientDetails.clientSecret;
    }
    pluginConfig.config["redirect_uri"] = `/${newId}/cb`;
    //pluginConfig.config["session_path"] = `/${newId}`;
  } else if (plugin.name == "jwt-keycloak") {
    // pluginConfig.config["allowed_aud"] = clientDetails.clientId;
  }

  await provisionKong(request, `${baseURL}/services`, service);
  await provisionKong(request, `${baseURL}/routes`, route);
  await provisionKong(request, `${baseURL}/plugins`, pluginConfig);

  return `/${newId}`;
}

export async function provisionKong(
  request: APIRequestContext,
  endpoint: string,
  payload: any
) {
  const options: any = {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Connection: "close",
    },
    data: JSON.stringify(payload),
  };

  const response = await request.fetch(endpoint, options);

  let responseBody: any;
  try {
    responseBody = await response.json();
  } catch (e) {
    logger.debug(e, "Error parsing json response");
    responseBody = null;
  }

  if (response.status() >= 300) {
    const errors = await response.text();
    logger.error(errors, "failed to provision kong");
    throw new Error("failed to provision kong");
  }

  return {
    status: response.status(),
    body: responseBody,
  } as KongProvisionResponse;
}

/**
 * Poll until a newly provisioned route is live on all DP replicas.
 * GETs `${KONG_PROXY_URL}${routePath}/headers` every `intervalMs` until a
 * non-404, then requires `consecutive` further consecutive non-404s (a 404
 * resets the count). Optional `stableMs` keeps probing after that threshold
 * with zero 404s; default 0 (return as soon as the consecutive streak hits —
 * with consecutive≈9 @ 250ms the streak already spans ~2s of RR sampling).
 *
 * Each probe uses `perRequestTimeoutMs` so a hung DP/LB connection cannot
 * block the whole readiness loop until the Playwright test timeout.
 */
export async function waitForRouteReady(
  request: APIRequestContext,
  routePath: string,
  options?: {
    timeoutMs?: number;
    intervalMs?: number;
    consecutive?: number;
    stableMs?: number;
    perRequestTimeoutMs?: number;
  }
): Promise<void> {
  const timeoutMs = options?.timeoutMs ?? 10_000;
  const intervalMs = options?.intervalMs ?? 250;
  const consecutiveNeeded = options?.consecutive ?? 5;
  const stableMs = options?.stableMs ?? 0;
  const perRequestTimeoutMs = options?.perRequestTimeoutMs ?? 3_000;
  const url = `${KONG_PROXY_URL}${routePath}/headers`;
  const deadline = Date.now() + timeoutMs;
  let consecutive = 0;
  let stableSince: number | null = null;

  while (Date.now() < deadline) {
    try {
      const res = await request.get(url, { timeout: perRequestTimeoutMs });
      if (res.status() !== 404) {
        consecutive += 1;
        if (consecutive >= consecutiveNeeded) {
          if (stableSince === null) {
            stableSince = Date.now();
          }
          if (Date.now() - stableSince >= stableMs) {
            return;
          }
        }
      } else {
        consecutive = 0;
        stableSince = null;
      }
    } catch {
      // Timeout / connection error: treat as not ready and keep polling.
      consecutive = 0;
      stableSince = null;
    }
    await new Promise((r) => setTimeout(r, intervalMs));
  }

  throw new Error(
    `route not ready after ${timeoutMs}ms: ${url} (need ${consecutiveNeeded} consecutive non-404 + ${stableMs}ms stable)`
  );
}

export type ProxyRequestInit = {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE" | "HEAD";
  /** Appended to `routePath`; default `/headers`. */
  pathSuffix?: string;
  headers?: Record<string, string>;
  data?: string | Buffer | { [key: string]: any };
  attempts?: number;
  /**
   * Extra retry predicate beyond transient 404. Called only when status is
   * not 404. Return true to backoff and retry; false to return the response.
   */
  shouldRetry?: (res: APIResponse) => boolean | Promise<boolean>;
};

/**
 * Proxy request with retries for residual DP lag after {@link waitForRouteReady}.
 * On 404, re-runs readiness before the next attempt. Optional `shouldRetry`
 * covers plugin-specific flakes (e.g. JWKS fetch).
 */
export async function proxyRequest(
  request: APIRequestContext,
  routePath: string,
  init?: ProxyRequestInit
): Promise<APIResponse> {
  const method = init?.method ?? "GET";
  const pathSuffix = init?.pathSuffix ?? "/headers";
  const attempts = init?.attempts ?? 12;
  const url = `${KONG_PROXY_URL}${routePath}${pathSuffix}`;

  const fn = () =>
    request.fetch(url, {
      method,
      headers: init?.headers,
      data: init?.data,
    });

  let res = await fn();
  for (let i = 1; i < attempts; i++) {
    if (res.status() === 404) {
      try {
        await waitForRouteReady(request, routePath, {
          timeoutMs: 15_000,
          consecutive: 9,
        });
      } catch {
        // Fall through to retry; final attempt still returns 404.
      }
      res = await fn();
      continue;
    }
    if (init?.shouldRetry && (await init.shouldRetry(res))) {
      await new Promise((r) => setTimeout(r, Math.min(500, 100 * i)));
      res = await fn();
      continue;
    }
    return res;
  }
  return res;
}

/** GET via {@link proxyRequest} (default pathSuffix `/headers`). */
export async function proxyGet(
  request: APIRequestContext,
  routePath: string,
  init?: Omit<ProxyRequestInit, "method">
): Promise<APIResponse> {
  return proxyRequest(request, routePath, { ...init, method: "GET" });
}

// ---------------------------------------------------------------------------
// mTLS proxy entry point ({@link KONG_PROXY_TLS_URL})
// ---------------------------------------------------------------------------

const MTLS_FIXTURES_DIR = path.resolve(
  __dirname,
  "..",
  "local",
  "kong",
  "fixtures",
  "keys",
  "mtls"
);

export type MtlsClientCert = {
  name: string;
  certPath: string;
  keyPath: string;
  pem: string;
  /** Parsed certificate — fingerprints, serial number, subject/issuer, etc. */
  x509: crypto.X509Certificate;
};

/**
 * Resolve a client-certificate fixture by name (file stem under
 * `local/kong/fixtures/keys/mtls/` — see the README there for the inventory
 * and each cert's subject DN). Tests derive expected values (fingerprint,
 * serial, PEM) from `x509`/`pem` instead of hardcoding them.
 */
export function mtlsClientCert(name: string): MtlsClientCert {
  const certPath = path.join(MTLS_FIXTURES_DIR, `${name}.crt`);
  const keyPath = path.join(MTLS_FIXTURES_DIR, `${name}.key`);
  const pem = fs.readFileSync(certPath, "utf8");
  return { name, certPath, keyPath, pem, x509: new crypto.X509Certificate(pem) };
}

/**
 * Response shape shared by both mTLS transports. Playwright's `APIResponse`
 * satisfies it structurally; the no-SNI path (raw Node TLS) returns a small
 * adapter with the same methods.
 */
export type MtlsProxyResponse = {
  status(): number;
  statusText(): string;
  ok(): boolean;
  url(): string;
  /** Lowercased header names, like APIResponse.headers(). */
  headers(): { [key: string]: string };
  text(): Promise<string>;
  json(): Promise<any>;
  body(): Promise<Buffer>;
};

export type MtlsProxyRequestInit = Omit<ProxyRequestInit, "shouldRetry"> & {
  /**
   * Client-cert fixture name (e.g. `"alice"`) to present in the TLS
   * handshake; omit to connect without a client certificate.
   */
  clientCert?: string;
  /**
   * `false` → connect via raw Node TLS to the resolved IP literal so the
   * handshake carries no SNI (Playwright cannot do this: it reuses the Host
   * header as servername); an explicit Host header keeps Kong route matching
   * working. Default `true`.
   */
  sni?: boolean;
  shouldRetry?: (res: MtlsProxyResponse) => boolean | Promise<boolean>;
};

const mtlsContexts = new Map<string, APIRequestContext>();

async function mtlsContext(
  origin: string,
  clientCert?: string
): Promise<APIRequestContext> {
  const key = `${origin}|${clientCert ?? ""}`;
  const existing = mtlsContexts.get(key);
  if (existing) {
    return existing;
  }
  const cert = clientCert ? mtlsClientCert(clientCert) : undefined;
  const ctx = await playwrightRequest.newContext({
    // Kong serves its default self-signed server cert on :8443.
    ignoreHTTPSErrors: true,
    ...(cert
      ? {
          clientCertificates: [
            { origin, certPath: cert.certPath, keyPath: cert.keyPath },
          ],
        }
      : {}),
  });
  mtlsContexts.set(key, ctx);
  return ctx;
}

/** Dispose all cached mTLS request contexts — call from `afterAll`. */
export async function disposeMtlsContexts(): Promise<void> {
  const contexts = Array.from(mtlsContexts.values());
  mtlsContexts.clear();
  await Promise.all(contexts.map((ctx) => ctx.dispose()));
}

/**
 * One request over raw Node TLS with SNI omitted: Node only sends SNI when
 * the connection host is a DNS name, so connecting to the resolved IP
 * literal (with an explicit Host header for Kong route matching) produces a
 * handshake with no server_name extension.
 */
async function noSniRequest(opts: {
  url: string;
  hostHeader: string;
  method: string;
  headers?: Record<string, string>;
  data?: string | Buffer | { [key: string]: any };
  clientCert?: string;
}): Promise<MtlsProxyResponse> {
  const target = new URL(opts.url);
  const cert = opts.clientCert ? mtlsClientCert(opts.clientCert) : undefined;

  let payload: string | Buffer | undefined;
  const headers: Record<string, string> = {
    Host: opts.hostHeader,
    ...(opts.headers ?? {}),
  };
  if (opts.data !== undefined) {
    if (typeof opts.data === "string" || Buffer.isBuffer(opts.data)) {
      payload = opts.data;
    } else {
      payload = JSON.stringify(opts.data);
      headers["Content-Type"] = headers["Content-Type"] ?? "application/json";
    }
  }

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        host: target.hostname,
        port: Number(target.port || "443"),
        path: `${target.pathname}${target.search}`,
        method: opts.method,
        headers,
        // Explicitly disable SNI: without this Node's https agent derives
        // servername from the Host header (as Playwright also does).
        servername: "",
        rejectUnauthorized: false, // Kong's default self-signed server cert
        ...(cert
          ? {
              cert: fs.readFileSync(cert.certPath),
              key: fs.readFileSync(cert.keyPath),
            }
          : {}),
      },
      (res) => {
        const chunks: Buffer[] = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const body = Buffer.concat(chunks);
          const responseHeaders: { [key: string]: string } = {};
          for (const [name, value] of Object.entries(res.headers)) {
            responseHeaders[name] = Array.isArray(value)
              ? value.join(", ")
              : value ?? "";
          }
          const status = res.statusCode ?? 0;
          resolve({
            status: () => status,
            statusText: () => res.statusMessage ?? "",
            ok: () => status >= 200 && status < 300,
            url: () => opts.url,
            headers: () => responseHeaders,
            text: async () => body.toString("utf8"),
            json: async () => JSON.parse(body.toString("utf8")),
            body: async () => body,
          });
        });
      }
    );
    req.on("error", reject);
    if (payload !== undefined) {
      req.write(payload);
    }
    req.end();
  });
}

/**
 * Proxy request over the TLS entry point ({@link KONG_PROXY_TLS_URL}),
 * optionally presenting a fixture client certificate, with the same
 * residual-404 retry semantics as {@link proxyRequest}. The `request`
 * argument is only used for the http readiness re-probe after a 404 —
 * route sync is protocol-independent.
 */
export async function mtlsProxyRequest(
  request: APIRequestContext,
  routePath: string,
  init?: MtlsProxyRequestInit
): Promise<MtlsProxyResponse> {
  const method = init?.method ?? "GET";
  const pathSuffix = init?.pathSuffix ?? "/headers";
  const attempts = init?.attempts ?? 12;
  const sni = init?.sni ?? true;

  const tls = new URL(KONG_PROXY_TLS_URL);

  let fn: () => Promise<MtlsProxyResponse>;
  if (sni) {
    const ctx = await mtlsContext(tls.origin, init?.clientCert);
    const url = `${tls.origin}${routePath}${pathSuffix}`;
    fn = () =>
      ctx.fetch(url, { method, headers: init?.headers, data: init?.data });
  } else {
    // Resolve every A record and try each: a hostname with multiple docker
    // aliases (historically kong-cp AND the nginx LB) can yield an IP that
    // refuses :8443. Prefer KONG_PROXY_TLS_CONNECT_HOST (compose sets `kong`,
    // the LB service name). lookup() (not resolve4) honours /etc/hosts so
    // host runs of kong.localtest.me → 127.0.0.1 still work.
    const connectHost =
      process.env.KONG_PROXY_TLS_CONNECT_HOST ?? tls.hostname;
    const lookedUp = await dns.promises.lookup(connectHost, {
      family: 4,
      all: true,
    });
    const addresses = [...new Set(lookedUp.map((r) => r.address))];
    if (addresses.length === 0) {
      throw new Error(`no IPv4 addresses for ${connectHost}`);
    }
    const port = tls.port || "443";
    fn = async () => {
      let lastErr: unknown;
      for (const address of addresses) {
        try {
          return await noSniRequest({
            url: `https://${address}:${port}${routePath}${pathSuffix}`,
            hostHeader: tls.host,
            method,
            headers: init?.headers,
            data: init?.data,
            clientCert: init?.clientCert,
          });
        } catch (err) {
          lastErr = err;
        }
      }
      throw lastErr;
    };
  }

  let res = await fn();
  for (let i = 1; i < attempts; i++) {
    if (res.status() === 404) {
      try {
        await waitForRouteReady(request, routePath, {
          timeoutMs: 15_000,
          consecutive: 9,
        });
      } catch {
        // Fall through to retry; final attempt still returns 404.
      }
      res = await fn();
      continue;
    }
    if (init?.shouldRetry && (await init.shouldRetry(res))) {
      await new Promise((r) => setTimeout(r, Math.min(500, 100 * i)));
      res = await fn();
      continue;
    }
    return res;
  }
  return res;
}

/** GET via {@link mtlsProxyRequest} (default pathSuffix `/headers`). */
export async function mtlsProxyGet(
  request: APIRequestContext,
  routePath: string,
  init?: Omit<MtlsProxyRequestInit, "method">
): Promise<MtlsProxyResponse> {
  return mtlsProxyRequest(request, routePath, { ...init, method: "GET" });
}
