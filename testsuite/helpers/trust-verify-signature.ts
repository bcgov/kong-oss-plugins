import * as crypto from "crypto";
import * as fs from "fs";
import * as path from "path";
import { APIRequestContext, APIResponse } from "playwright";
import {
  KONG_ADMIN_URL,
  KONG_PROXY_URL,
  provisionKong,
  waitForRouteReady,
  uniquePrefix,
  proxyRequest as kongProxyRequest,
  type ProxyRequestInit,
} from "./kong";
import { upstreamServiceDefaults } from "./upstream";

export { uniquePrefix };

const FIXTURES_KEYS_DIR = path.resolve(
  __dirname,
  "../local/kong/fixtures/keys"
);
/** In-container path the compose stack mounts the same directory at. */
const CONTAINER_KEYS_DIR = "/tmp/kong/fixtures/keys";

let routeCounter = 0;

export type ProvisionResult = {
  routePath: string;
  serviceId: string;
  routeId: string;
  pluginId: string;
};

/**
 * Provisions a service + route + trust-verify-signature plugin instance and
 * waits for it to be routable across all data-plane replicas.
 */
export async function provisionPluginRoute(
  request: APIRequestContext,
  opts: {
    prefix: string;
    config: Record<string, unknown>;
    serviceTags?: string[];
  }
): Promise<ProvisionResult> {
  const n = ++routeCounter;
  // Zero-pad so Kong's path-prefix match cannot treat /…-1 as a prefix of
  // /…-10 (waitForRouteReady would otherwise succeed against the wrong route).
  const seq = String(n).padStart(4, "0");

  const serviceBody: Record<string, unknown> = {
    name: `${opts.prefix}-svc-${seq}`,
    ...upstreamServiceDefaults,
  };
  if (opts.serviceTags) {
    serviceBody.tags = opts.serviceTags;
  }
  const serviceRes = await provisionKong(
    request,
    `${KONG_ADMIN_URL}/services`,
    serviceBody
  );
  const serviceId = serviceRes.body.id;

  const routePath = `/${opts.prefix}-${seq}`;
  const routeRes = await provisionKong(request, `${KONG_ADMIN_URL}/routes`, {
    name: `${opts.prefix}-rt-${seq}`,
    hosts: ["kong.localtest.me"],
    paths: [routePath],
    strip_path: true,
    service: { id: serviceId },
  });
  const routeId = routeRes.body.id;

  const pluginRes = await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
    name: "trust-verify-signature",
    route: { id: routeId },
    config: opts.config,
  });
  const pluginId = pluginRes.body.id;

  // 3 DPs sync independently; under parallel Admin load a short probe can
  // return while one replica still 404s. consecutive: 9 @ 250ms ≈ 2s of RR
  // sampling before we treat the route as ready.
  await waitForRouteReady(request, routePath, {
    timeoutMs: 30_000,
    consecutive: 9,
  });

  return { routePath, serviceId, routeId, pluginId };
}

/** Deletes routes (cascades their plugins) then services whose name starts with `prefix`. */
export async function cleanupByPrefix(
  request: APIRequestContext,
  prefix: string
): Promise<void> {
  await deleteEntitiesByPrefix(request, "routes", prefix);
  await deleteEntitiesByPrefix(request, "services", prefix);
}

async function deleteEntitiesByPrefix(
  request: APIRequestContext,
  collection: "routes" | "services",
  prefix: string
): Promise<void> {
  const ids: string[] = [];
  let url: string | null = `${KONG_ADMIN_URL}/${collection}?size=1000`;

  while (url) {
    const res = await request.get(url);
    const body = await res.json();
    for (const item of body.data ?? []) {
      if (typeof item.name === "string" && item.name.startsWith(prefix)) {
        ids.push(item.id);
      }
    }
    if (body.next) {
      url = body.next.startsWith("http")
        ? body.next
        : `${KONG_ADMIN_URL}${body.next}`;
    } else {
      url = null;
    }
  }

  for (const id of ids) {
    await request.delete(`${KONG_ADMIN_URL}/${collection}/${id}`);
  }
}

/** Host/Playwright URL for a file under the shared fixtures keys directory. */
export function fixtureKeysUrl(fileName: string): string {
  return `${KONG_PROXY_URL}/__fixtures__/keys/${fileName}`;
}

const CAPTURE_LOG = path.resolve(
  __dirname,
  "../local/kong/fixtures/capture/hits.log"
);

/**
 * Reachable JWKS URL under nginx `/__capture__/`. Each GET is appended
 * (unbuffered) to {@link CAPTURE_LOG}; the body is rsa-2048.jwks.json.
 * Use a unique suffix per test — workers share the log.
 */
export function captureJwksUrl(pathSuffix: string): string {
  return `${KONG_PROXY_URL}/__capture__/${pathSuffix}`;
}

/** Count `/__capture__/` access-log lines containing `uriSubstring`. */
export function countCaptureHits(uriSubstring: string): number {
  if (!fs.existsSync(CAPTURE_LOG)) {
    return 0;
  }
  return fs
    .readFileSync(CAPTURE_LOG, "utf8")
    .split(/\r?\n/)
    .filter((line) => line.includes(uriSubstring)).length;
}

/** In-container path (for plugin config values) for a file under the shared fixtures keys directory. */
export function fixtureKeysContainerPath(fileName: string): string {
  return `${CONTAINER_KEYS_DIR}/${fileName}`;
}

export function readFixtureKeyFile(fileName: string): string {
  return fs.readFileSync(path.join(FIXTURES_KEYS_DIR, fileName), "utf8");
}

/** Reads a fixture `<name>.jwks.json`'s `keys` array, for splicing into dynamic JWKS docs. */
export function readFixtureJwksKeys(fileName: string): unknown[] {
  const doc = JSON.parse(readFixtureKeyFile(fileName));
  return doc.keys;
}

/** Writes/overwrites a JWKS document fixture, e.g. for grace-period cache tests. */
export function writeDynamicJwks(
  fileStem: string,
  doc: { keys: unknown[] }
): void {
  fs.writeFileSync(
    path.join(FIXTURES_KEYS_DIR, `${fileStem}.jwks.json`),
    JSON.stringify(doc, null, 2)
  );
}

export function removeDynamicJwks(fileStem: string): void {
  const filePath = path.join(FIXTURES_KEYS_DIR, `${fileStem}.jwks.json`);
  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
  }
}

type SigningAlg = "RS256" | "RS512" | "ES256" | "ES512";

const NODE_DIGEST_BY_ALG: Record<SigningAlg, string> = {
  RS256: "sha256",
  RS512: "sha512",
  ES256: "sha256",
  ES512: "sha512",
};

function base64url(input: Buffer): string {
  return input
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/** Builds a signed JWS-compact manifest token for use as test input to the verifier. */
export function signManifestToken(opts: {
  alg: SigningAlg;
  kid: string;
  privateKeyPem: string;
  payload: Record<string, unknown>;
  headerOverrides?: Record<string, unknown>;
}): string {
  const header = { alg: opts.alg, kid: opts.kid, ...opts.headerOverrides };
  const encodedHeader = base64url(Buffer.from(JSON.stringify(header)));
  const encodedPayload = base64url(Buffer.from(JSON.stringify(opts.payload)));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const signer = crypto.createSign(NODE_DIGEST_BY_ALG[opts.alg]);
  signer.update(signingInput);
  signer.end();

  const isEcdsa = opts.alg.startsWith("ES");
  const signature = signer.sign({
    key: opts.privateKeyPem,
    ...(isEcdsa ? { dsaEncoding: "ieee-p1363" as const } : {}),
  });

  return `${signingInput}.${base64url(signature)}`;
}

/**
 * Fires the same request repeatedly so the nginx LB's round-robin across the
 * 3 DP replicas × 2 workers each has a high chance of having observed it
 * (used to prime per-worker JWKS cache state before a follow-up that depends
 * on that state, regardless of which replica/worker serves it).
 *
 * Default 36 ≈ 6 cache silos × 6; (5/6)^36 miss-one-worker ≈ 0.15%.
 */
export async function primeAllReplicas(
  fn: () => Promise<void>,
  times = 36
): Promise<void> {
  for (let i = 0; i < times; i++) {
    await fn();
  }
}

async function isJwksFetchFlake(res: APIResponse): Promise<boolean> {
  if (res.status() !== 401) {
    return false;
  }
  // Observed ~1 in 10 against a known-good fixture JWKS URL. Do NOT enable
  // when the scenario's expected message is exactly this string.
  try {
    const body = await res.json();
    return body?.message === "Unable to get public keys";
  } catch {
    return false;
  }
}

/**
 * Proxy request with shared 404/re-ready retries, plus optional JWKS-fetch flake
 * retry (401 Unable to get public keys). Set `retryJwksFetchFlake: false`
 * when that message is the expected failure.
 */
export async function proxyRequest(
  request: APIRequestContext,
  routePath: string,
  init?: Omit<ProxyRequestInit, "shouldRetry"> & {
    retryJwksFetchFlake?: boolean;
  }
): Promise<APIResponse> {
  const { retryJwksFetchFlake = true, ...rest } = init ?? {};
  return kongProxyRequest(request, routePath, {
    ...rest,
    shouldRetry: retryJwksFetchFlake ? isJwksFetchFlake : undefined,
  });
}

/** GET via {@link proxyRequest} (default pathSuffix `/headers`). */
export async function proxyGet(
  request: APIRequestContext,
  routePath: string,
  init?: Omit<ProxyRequestInit, "method" | "shouldRetry"> & {
    retryJwksFetchFlake?: boolean;
  }
): Promise<APIResponse> {
  return proxyRequest(request, routePath, { ...init, method: "GET" });
}
