import { APIRequestContext } from "playwright";
import * as crypto from "crypto";
import * as fs from "fs";
import * as path from "path";
import {
  KONG_ADMIN_URL,
  provisionKong,
  waitForRouteReady,
} from "./kong";
import { upstreamServiceDefaults } from "./upstream";

/** Shared key fixtures: host path (for test-side crypto) … */
export const FIXTURE_KEYS_DIR = path.resolve(
  __dirname,
  "../local/kong/fixtures/keys"
);
/** … and the path the same directory is mounted at inside Kong containers. */
export const CONTAINER_KEYS_DIR = "/tmp/kong/fixtures/keys";

export function fixtureKeyPem(name: string): string {
  return fs.readFileSync(path.join(FIXTURE_KEYS_DIR, name), "utf8");
}

let entitySeq = 0;

export interface ProvisionOptions {
  prefix: string;
  config: Record<string, unknown>;
  serviceTags?: string[];
  /** Extra plugins to attach to the same route (e.g. request-termination). */
  extraPlugins?: { name: string; config: Record<string, unknown> }[];
}

export interface ProvisionResult {
  routePath: string;
  serviceId: string;
  routeId: string;
  pluginId: string;
}

export async function provisionPluginRoute(
  request: APIRequestContext,
  options: ProvisionOptions
): Promise<ProvisionResult> {
  entitySeq += 1;
  const n = entitySeq;
  const { prefix, config, serviceTags, extraPlugins } = options;

  const service: Record<string, unknown> = {
    name: `${prefix}-svc-${n}`,
    ...upstreamServiceDefaults,
  };
  if (serviceTags) {
    service.tags = serviceTags;
  }
  const svcRes = await provisionKong(
    request,
    `${KONG_ADMIN_URL}/services`,
    service
  );
  const serviceId = svcRes.body.id as string;

  const routePath = `/${prefix}-${n}`;
  const routeRes = await provisionKong(request, `${KONG_ADMIN_URL}/routes`, {
    name: `${prefix}-rt-${n}`,
    hosts: ["kong.localtest.me"],
    paths: [routePath],
    strip_path: true,
    service: { id: serviceId },
  });
  const routeId = routeRes.body.id as string;

  const pluginRes = await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
    name: "trust-sign",
    route: { id: routeId },
    config,
  });
  const pluginId = pluginRes.body.id as string;

  for (const extra of extraPlugins ?? []) {
    await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
      name: extra.name,
      route: { id: routeId },
      config: extra.config,
    });
  }

  // 3 DPs sync independently; under parallel Admin load a short probe can
  // return while one replica still 404s. consecutive: 9 @ 250ms ≈ 2s of RR
  // sampling before we treat the route as ready.
  await waitForRouteReady(request, routePath, {
    timeoutMs: 30_000,
    consecutive: 9,
  });

  return { routePath, serviceId, routeId, pluginId };
}

async function listAll(
  request: APIRequestContext,
  collection: "routes" | "services"
): Promise<{ id: string; name: string | null }[]> {
  const items: { id: string; name: string | null }[] = [];
  let url: string | null = `${KONG_ADMIN_URL}/${collection}?size=1000`;
  while (url) {
    const res = await request.get(url);
    const body = await res.json();
    items.push(...(body.data ?? []));
    url = body.next ? `${KONG_ADMIN_URL}${body.next}` : null;
  }
  return items;
}

export async function cleanupByPrefix(
  request: APIRequestContext,
  prefix: string
): Promise<void> {
  // Route-scoped plugins cascade with the route; delete routes first, then services.
  for (const route of await listAll(request, "routes")) {
    if (route.name && route.name.startsWith(prefix)) {
      await request.delete(`${KONG_ADMIN_URL}/routes/${route.id}`);
    }
  }
  for (const service of await listAll(request, "services")) {
    if (service.name && service.name.startsWith(prefix)) {
      await request.delete(`${KONG_ADMIN_URL}/services/${service.id}`);
    }
  }
}

/**
 * Stale-entity pre-cleanup for beforeAll hooks. Spec files run in parallel
 * workers, so deleting everything under "trust-sign-" would wipe entities a
 * sibling worker just provisioned. Names embed a uniquePrefix run ID
 * (`trust-sign-<ms>-…`), so only delete entities older than `olderThanMs`.
 */
export async function cleanupStale(
  request: APIRequestContext,
  base: string,
  olderThanMs = 10 * 60 * 1000
): Promise<void> {
  const cutoff = Date.now() - olderThanMs;
  const isStale = (name: string | null): boolean => {
    if (!name || !name.startsWith(base)) return false;
    const match = name.slice(base.length).match(/^(\d+)/);
    if (!match) return true; // prefixed but no run timestamp: treat as stale
    return Number(match[1]) < cutoff;
  };
  for (const route of await listAll(request, "routes")) {
    if (isStale(route.name)) {
      await request.delete(`${KONG_ADMIN_URL}/routes/${route.id}`);
    }
  }
  for (const service of await listAll(request, "services")) {
    if (isStale(service.name)) {
      await request.delete(`${KONG_ADMIN_URL}/services/${service.id}`);
    }
  }
}

// ---------------------------------------------------------------------------
// JWT / digest utilities (wire-format helpers derived from the spec's
// "JWT token format" requirement and shared contract section).
// ---------------------------------------------------------------------------

export interface DecodedJwt {
  header: Record<string, any>;
  payload: Record<string, any>;
  signature: Buffer;
  signingInput: string;
  raw: string;
}

function b64urlDecode(segment: string): Buffer {
  return Buffer.from(segment.replace(/-/g, "+").replace(/_/g, "/"), "base64");
}

function b64urlEncode(data: Buffer | string): string {
  return Buffer.from(data)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/** Decode a JWS compact serialization without verifying it. */
export function decodeJwt(token: string): DecodedJwt {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new Error(
      `expected JWS compact serialization with 3 segments, got ${parts.length}: ${token}`
    );
  }
  return {
    header: JSON.parse(b64urlDecode(parts[0]).toString("utf8")),
    payload: JSON.parse(b64urlDecode(parts[1]).toString("utf8")),
    signature: b64urlDecode(parts[2]),
    signingInput: `${parts[0]}.${parts[1]}`,
    raw: token,
  };
}

/** sha256 or sha512 as derived from a JWS alg per the spec. */
export function digestForAlg(alg: string): "sha256" | "sha512" {
  if (alg === "RS256" || alg === "ES256") return "sha256";
  if (alg === "RS512" || alg === "ES512") return "sha512";
  throw new Error(`unsupported alg: ${alg}`);
}

/**
 * Verify a decoded token's signature over `<header>.<payload>` with the given
 * public key PEM and digest. ECDSA signatures are raw r||s per the spec.
 */
export function verifyJws(
  jwt: DecodedJwt,
  publicKeyPem: string,
  digest: "sha256" | "sha512"
): boolean {
  const key = crypto.createPublicKey(publicKeyPem);
  const verifyKey: crypto.VerifyKeyObjectInput =
    key.asymmetricKeyType === "ec"
      ? { key, dsaEncoding: "ieee-p1363" }
      : { key };
  return crypto.verify(
    digest,
    Buffer.from(jwt.signingInput, "utf8"),
    verifyKey,
    jwt.signature
  );
}

/** Sign a JWS compact JWT with a fixture private key (for inbound-token tests). */
export function signJwt(
  payload: Record<string, unknown>,
  options: { alg: "RS256" | "RS512" | "ES256" | "ES512"; kid: string; keyFile: string }
): string {
  const header = { alg: options.alg, kid: options.kid, typ: "JWT" };
  const signingInput = `${b64urlEncode(JSON.stringify(header))}.${b64urlEncode(
    JSON.stringify(payload)
  )}`;
  const key = crypto.createPrivateKey(fixtureKeyPem(options.keyFile));
  const signKey: crypto.SignKeyObjectInput =
    key.asymmetricKeyType === "ec"
      ? { key, dsaEncoding: "ieee-p1363" }
      : { key };
  const signature = crypto.sign(
    digestForAlg(options.alg),
    Buffer.from(signingInput, "utf8"),
    signKey
  );
  return `${signingInput}.${b64urlEncode(signature)}`;
}

/** Case-insensitive lookup in an echoed-headers object from httpbun. */
export function findHeader(
  headers: Record<string, string>,
  name: string
): string | undefined {
  const lower = name.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === lower) {
      return value;
    }
  }
  return undefined;
}

/** `sha-256=:<standard base64 of SHA-256(body)>:` per the shared contract. */
export function contentDigestOf(body: string | Buffer): string {
  const digest = crypto.createHash("sha256").update(body).digest("base64");
  return `sha-256=:${digest}:`;
}
