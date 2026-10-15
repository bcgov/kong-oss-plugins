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
let keysetSeq = 0;

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

export type SigningKeyInput = {
  kid: string;
  /** Filename under fixtures/keys. Defaults to rsa-2048.pub.pem when jwkFile is unset. */
  publicKeyFile?: string;
  /** Filename under fixtures/keys (uses keys[0]; kid is overwritten to match `kid`). */
  jwkFile?: string;
};

export type SigningKeyset = {
  keysetName: string;
  keysetId: string;
  keys: { id: string; kid: string }[];
  /** Kid of the key matching the rsa-2048 fixture when present, otherwise keys[0].kid. */
  expectedKid: string;
};

/** Canonical trust-sign config using a provisioned keyset and the rsa-2048 fixture. */
export function trustSignConfig(
  keysetName: string,
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    keyset_name: keysetName,
    private_key_location: `${CONTAINER_KEYS_DIR}/rsa-2048.pem`,
    alg: "RS256",
    ...overrides,
  };
}

async function postAdmin(
  request: APIRequestContext,
  path: string,
  payload: Record<string, unknown>
): Promise<Record<string, unknown>> {
  const res = await request.post(`${KONG_ADMIN_URL}${path}`, {
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    data: payload,
  });
  const body = await res.json().catch(() => null);
  if (res.status() >= 300) {
    throw new Error(
      `POST ${path} failed (${res.status()}): ${JSON.stringify(body ?? (await res.text()))}`
    );
  }
  return body as Record<string, unknown>;
}

function rsaExpectedKid(keys: SigningKeyInput[]): string {
  const rsa = keys.find(
    (k) =>
      k.jwkFile === "rsa-2048.jwks.json" ||
      (k.publicKeyFile ?? (k.jwkFile ? undefined : "rsa-2048.pub.pem")) ===
        "rsa-2048.pub.pem"
  );
  return (rsa ?? keys[0]).kid;
}

/**
 * Create a Kong key-set plus keys for trust-sign kid resolution.
 * Keys are inserted in array order. Cleans up with {@link cleanupByPrefix}
 * when key/key-set names start with `prefix`.
 */
export async function provisionSigningKeyset(
  request: APIRequestContext,
  options: {
    prefix: string;
    keys?: SigningKeyInput[];
  }
): Promise<SigningKeyset> {
  keysetSeq += 1;
  const keysetName = `${options.prefix}-ks-${keysetSeq}`;
  const keys = options.keys ?? [
    { kid: `${options.prefix}-kid`, publicKeyFile: "rsa-2048.pub.pem" },
  ];

  const keyset = await postAdmin(request, "/key-sets", {
    name: keysetName,
    tags: [options.prefix],
  });
  const keysetId = keyset.id as string;

  const created: { id: string; kid: string }[] = [];
  for (let i = 0; i < keys.length; i++) {
    const input = keys[i];
    const payload: Record<string, unknown> = {
      name: `${options.prefix}-key-${keysetSeq}-${i}`,
      kid: input.kid,
      set: { id: keysetId },
      tags: [options.prefix],
    };
    if (input.jwkFile) {
      const doc = JSON.parse(fixtureKeyPem(input.jwkFile)) as {
        keys: Array<Record<string, unknown>>;
      };
      const jwk = { ...doc.keys[0], kid: input.kid };
      payload.jwk = JSON.stringify(jwk);
    } else {
      payload.pem = {
        public_key: fixtureKeyPem(input.publicKeyFile ?? "rsa-2048.pub.pem"),
      };
    }
    const key = await postAdmin(request, "/keys", payload);
    created.push({ id: key.id as string, kid: input.kid });
  }

  return {
    keysetName,
    keysetId,
    keys: created,
    expectedKid: rsaExpectedKid(keys),
  };
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

type NamedCollection = "routes" | "services" | "keys" | "key-sets";

async function listAll(
  request: APIRequestContext,
  collection: NamedCollection
): Promise<{ id: string; name: string | null }[]> {
  const items: { id: string; name: string | null }[] = [];
  let url: string | null = `${KONG_ADMIN_URL}/${collection}?size=1000`;
  while (url) {
    const res = await request.get(url);
    const body = await res.json();
    items.push(...(body.data ?? []));
    url = body.next
      ? body.next.startsWith("http")
        ? body.next
        : `${KONG_ADMIN_URL}${body.next}`
      : null;
  }
  return items;
}

async function deleteNamed(
  request: APIRequestContext,
  collection: NamedCollection,
  predicate: (name: string | null) => boolean
): Promise<void> {
  for (const item of await listAll(request, collection)) {
    if (predicate(item.name)) {
      await request.delete(`${KONG_ADMIN_URL}/${collection}/${item.id}`);
    }
  }
}

export async function cleanupByPrefix(
  request: APIRequestContext,
  prefix: string
): Promise<void> {
  const matches = (name: string | null) => !!name && name.startsWith(prefix);
  // Keys before key-sets (membership); routes before services (plugins cascade).
  await deleteNamed(request, "keys", matches);
  await deleteNamed(request, "key-sets", matches);
  await deleteNamed(request, "routes", matches);
  await deleteNamed(request, "services", matches);
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
    // Require the uniquePrefix timestamp immediately after `base`. A longer
    // prefix that only shares the string (e.g. interop
    // `trust-sign-trust-verify-signature-interop-…`) must not be deleted.
    if (!match) return false;
    return Number(match[1]) < cutoff;
  };
  await deleteNamed(request, "keys", isStale);
  await deleteNamed(request, "key-sets", isStale);
  await deleteNamed(request, "routes", isStale);
  await deleteNamed(request, "services", isStale);
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
