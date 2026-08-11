import * as crypto from "crypto";
import { APIRequestContext, APIResponse } from "playwright";
import logger from "./logger";
import { upstreamServiceDefaults } from "./upstream";

/** Kong Admin API — override with KONG_ADMIN_URL (compose / .env.e2e). */
export const KONG_ADMIN_URL =
  process.env.KONG_ADMIN_URL ?? "http://kong.localtest.me:8001";

/** Kong proxy (nginx → DP replicas) — override with KONG_PROXY_URL. */
export const KONG_PROXY_URL =
  process.env.KONG_PROXY_URL ?? "http://kong.localtest.me:8000";

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
