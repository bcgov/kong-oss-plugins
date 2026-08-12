import { test, expect } from "@playwright/test";
import { KONG_PROXY_URL } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  uniquePrefix,
  fixtureKeysUrl,
  readFixtureKeyFile,
  readFixtureJwksKeys,
  writeDynamicJwks,
  removeDynamicJwks,
  signManifestToken,
  primeAllReplicas,
  proxyGet,
  captureJwksUrl,
  countCaptureHits,
} from "../../../helpers/trust-verify-signature";

const PREFIX = uniquePrefix("trust-verify-signature");
const RSA_JWKS_URL = fixtureKeysUrl("rsa-2048.jwks.json");
const RSA_PRIVATE_KEY = readFixtureKeyFile("rsa-2048.pem");
const EC_JWKS_URL = fixtureKeysUrl("ec-p256.jwks.json");
const EC_PRIVATE_KEY = readFixtureKeyFile("ec-p256.pem");
const MALFORMED_JWKS_URL = fixtureKeysUrl("malformed.jwks.json");

async function verifyRoute(
  request: any,
  allowedJwksUriPrefix: string[],
  extraConfig: Record<string, unknown> = {}
) {
  return provisionPluginRoute(request, {
    prefix: PREFIX,
    config: {
      signature_header_key: "X-Edge-Token",
      allowed_jwks_uri_prefix: allowedJwksUriPrefix,
      direction: "request",
      ...extraConfig,
    },
  });
}

test.describe("trust-verify-signature — key discovery", () => {
  test.beforeAll(async ({ request }) => {
    // Only this file's prefix — a shared wipe races with parallel workers.
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-verify-signature.key-discovery.missing-jwks-uri-401]
  test("missing jwks_uri claim is rejected", async ({ request }) => {
    const { routePath } = await verifyRoute(request, [RSA_JWKS_URL]);

    const token = signManifestToken({
      alg: "RS256",
      kid: "rsa-2048",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: {}, // no jwks_uri claim
    });

    const res = await proxyGet(request, routePath, {
      headers: { "X-Edge-Token": token },
    });
    expect(res.status()).toBe(401);
    const body = await res.json();
    expect(body.message).toBe("Signature missing 'jwks_uri' claim");
  });

  test.describe("disallowed jwks_uri is rejected before fetch", () => {
    async function assertRejectedWithoutFetch(
      request: any,
      routePath: string,
      forbiddenUri: string,
      uriSubstring: string
    ) {
      // Prove the capture endpoint is reachable and that hits are logged;
      // otherwise a silent log-path failure would make "no fetch" a false pass.
      const probe = await request.get(forbiddenUri);
      expect(probe.ok()).toBeTruthy();
      const hitsAfterProbe = countCaptureHits(uriSubstring);
      expect(hitsAfterProbe).toBeGreaterThanOrEqual(1);

      const token = signManifestToken({
        alg: "RS256",
        kid: "rsa-2048",
        privateKeyPem: RSA_PRIVATE_KEY,
        payload: { jwks_uri: forbiddenUri },
      });

      const res = await proxyGet(request, routePath, {
        headers: { "X-Edge-Token": token },
      });
      expect(res.status()).toBe(401);
      const body = await res.json();
      expect(body.message).toBe("JWKS URI not allowed");
      expect(countCaptureHits(uriSubstring)).toBe(hitsAfterProbe);
    }

    // [Verifies: trust-verify-signature.key-discovery.jwks-uri-not-allowed-401]
    test("wholly unrelated URI", async ({ request }) => {
      const stem = `${PREFIX}-unrelated`;
      const forbiddenUri = captureJwksUrl(stem);
      const { routePath } = await verifyRoute(request, [RSA_JWKS_URL]);
      await assertRejectedWithoutFetch(request, routePath, forbiddenUri, stem);
    });

    // [Verifies: trust-verify-signature.key-discovery.jwks-uri-not-allowed-401]
    test("shared prefix without a / boundary", async ({ request }) => {
      // Naive string-prefix matching would accept this; the allow check must
      // require an exact match or a "/"-bounded continuation.
      const stem = `${PREFIX}-boundary`;
      const allowedPrefix = captureJwksUrl(stem);
      const forbiddenUri = `${allowedPrefix}.evil/keys.json`;
      const { routePath } = await verifyRoute(request, [allowedPrefix]);
      await assertRejectedWithoutFetch(
        request,
        routePath,
        forbiddenUri,
        `${stem}.evil`
      );
    });
  });

  test.describe("unusable JWKS endpoint is rejected", () => {
    // [Verifies: trust-verify-signature.key-discovery.jwks-fetch-failure-401]
    test("endpoint is unreachable", async ({ request }) => {
      const unreachable = "http://127.0.0.1:1/jwks.json";
      const { routePath } = await verifyRoute(request, [unreachable]);

      const token = signManifestToken({
        alg: "RS256",
        kid: "rsa-2048",
        privateKeyPem: RSA_PRIVATE_KEY,
        payload: { jwks_uri: unreachable },
      });

      // 404-only: expected message is itself the JWKS-flake string.
      const res = await proxyGet(request, routePath, {
        headers: { "X-Edge-Token": token },
        retryJwksFetchFlake: false,
      });
      expect(res.status()).toBe(401);
      const body = await res.json();
      expect(body.message).toBe("Unable to get public keys");
    });

    // [Verifies: trust-verify-signature.key-discovery.jwks-fetch-failure-401]
    test("endpoint responds with a non-200 status", async ({ request }) => {
      const notFound = fixtureKeysUrl("does-not-exist.jwks.json");
      const { routePath } = await verifyRoute(request, [notFound]);

      const token = signManifestToken({
        alg: "RS256",
        kid: "rsa-2048",
        privateKeyPem: RSA_PRIVATE_KEY,
        payload: { jwks_uri: notFound },
      });

      const res = await proxyGet(request, routePath, {
        headers: { "X-Edge-Token": token },
        retryJwksFetchFlake: false,
      });
      expect(res.status()).toBe(401);
      const body = await res.json();
      expect(body.message).toBe("Unable to get public keys");
    });

    // [Verifies: trust-verify-signature.key-discovery.jwks-fetch-failure-401]
    test("endpoint body is not JSON with a keys array", async ({
      request,
    }) => {
      const notJson = fixtureKeysUrl("rsa-2048.pem");
      const { routePath } = await verifyRoute(request, [notJson]);

      const token = signManifestToken({
        alg: "RS256",
        kid: "rsa-2048",
        privateKeyPem: RSA_PRIVATE_KEY,
        payload: { jwks_uri: notJson },
      });

      const res = await proxyGet(request, routePath, {
        headers: { "X-Edge-Token": token },
        retryJwksFetchFlake: false,
      });
      expect(res.status()).toBe(401);
      const body = await res.json();
      expect(body.message).toBe("Unable to get public keys");
    });
  });

  // [Verifies: trust-verify-signature.key-discovery.unknown-kid-401]
  test("unknown kid is rejected", async ({ request }) => {
    const { routePath } = await verifyRoute(request, [RSA_JWKS_URL]);

    const token = signManifestToken({
      alg: "RS256",
      kid: "no-such-kid",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: { jwks_uri: RSA_JWKS_URL },
    });

    const res = await proxyGet(request, routePath, {
      headers: { "X-Edge-Token": token },
    });
    expect(res.status()).toBe(401);
    const body = await res.json();
    expect(body.message).toBe("Signature public key not found");
  });

  // [Verifies: trust-verify-signature.key-discovery.missing-kid-refreshes-after-grace]
  test("missing kid refreshes keyset after grace period", async ({
    request,
  }) => {
    const stem = `grace-refresh-${PREFIX}`;
    const jwksUrl = fixtureKeysUrl(`${stem}.jwks.json`);
    writeDynamicJwks(stem, { keys: [] });

    try {
      const { routePath } = await verifyRoute(request, [jwksUrl], {
        iss_key_grace_period: 0,
      });

      const token = signManifestToken({
        alg: "RS256",
        kid: "rsa-2048",
        privateKeyPem: RSA_PRIVATE_KEY,
        payload: { jwks_uri: jwksUrl },
      });

      // Prime every DP replica's cache with the kid-less keyset.
      await primeAllReplicas(async () => {
        const primeRes = await proxyGet(request, routePath, {
          headers: { "X-Edge-Token": token },
        });
        expect(primeRes.status()).toBe(401);
      }, 15);

      // Publish the key; with a 0s grace period the next lookup must refetch.
      writeDynamicJwks(stem, {
        keys: readFixtureJwksKeys("rsa-2048.jwks.json"),
      });
      // Wait until the static fixture path serves the updated keyset (not a
      // fixed sleep — nginx may lag the host write briefly).
      await expect
        .poll(async () => {
          const jwksRes = await request.get(jwksUrl);
          if (!jwksRes.ok()) return false;
          const doc = await jwksRes.json();
          return (doc.keys ?? []).some((k: { kid?: string }) => k.kid === "rsa-2048");
        })
        .toBeTruthy();

      let res;
      await primeAllReplicas(async () => {
        res = await proxyGet(request, routePath, {
          headers: { "X-Edge-Token": token },
        });
        expect(res.status()).toBe(200);
      }, 15);
      const echoedHeaders = (await res!.json()).headers;
      expect(echoedHeaders["X-Trust-Verify-Signature-Req"]).toBe("OK");
    } finally {
      removeDynamicJwks(stem);
    }
  });

  // [Verifies: trust-verify-signature.key-discovery.missing-kid-no-refresh-within-grace]
  test("missing kid does not refresh within grace period", async ({
    request,
  }) => {
    const stem = `grace-norefresh-${PREFIX}`;
    const jwksUrl = fixtureKeysUrl(`${stem}.jwks.json`);
    writeDynamicJwks(stem, { keys: [] });

    try {
      const { routePath } = await verifyRoute(request, [jwksUrl], {
        iss_key_grace_period: 3600,
      });

      const token = signManifestToken({
        alg: "RS256",
        kid: "rsa-2048",
        privateKeyPem: RSA_PRIVATE_KEY,
        payload: { jwks_uri: jwksUrl },
      });

      await primeAllReplicas(async () => {
        const primeRes = await proxyGet(request, routePath, {
          headers: { "X-Edge-Token": token },
        });
        expect(primeRes.status()).toBe(401);
      }, 15);

      // The live endpoint now serves the key, but the cache is far younger
      // than the 1h grace period, so the plugin must not refetch, on any
      // replica.
      writeDynamicJwks(stem, {
        keys: readFixtureJwksKeys("rsa-2048.jwks.json"),
      });
      // Wait until the live endpoint serves the kid before asserting no-refresh;
      // otherwise a buggy refetch against a still-empty nginx body would also
      // return "Signature public key not found" and pass this test.
      await expect
        .poll(async () => {
          const jwksRes = await request.get(jwksUrl);
          if (!jwksRes.ok()) return false;
          const doc = await jwksRes.json();
          return (doc.keys ?? []).some((k: { kid?: string }) => k.kid === "rsa-2048");
        })
        .toBeTruthy();

      await primeAllReplicas(async () => {
        const res = await proxyGet(request, routePath, {
          headers: { "X-Edge-Token": token },
        });
        expect(res.status()).toBe(401);
        const body = await res.json();
        expect(body.message).toBe("Signature public key not found");
      }, 15);
    } finally {
      removeDynamicJwks(stem);
    }
  });

  // [Verifies: trust-verify-signature.key-discovery.malformed-jwk-401]
  test("malformed JWK is rejected", async ({ request }) => {
    const { routePath } = await verifyRoute(request, [MALFORMED_JWKS_URL]);

    const token = signManifestToken({
      alg: "RS256",
      kid: "malformed",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: { jwks_uri: MALFORMED_JWKS_URL },
    });

    const res = await proxyGet(request, routePath, {
      headers: { "X-Edge-Token": token },
    });
    expect(res.status()).toBe(401);
    const body = await res.json();
    expect(body.message).toBe("Public key format error");
  });

  // [Verifies: trust-verify-signature.key-discovery.signature-mismatch-401]
  test("signature mismatch is rejected", async ({ request }) => {
    const { routePath } = await verifyRoute(request, [RSA_JWKS_URL]);

    const token = signManifestToken({
      alg: "RS256",
      kid: "rsa-2048",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: { jwks_uri: RSA_JWKS_URL },
    });
    // Corrupt only the signature segment; header/payload (and thus kid/alg)
    // still name a well-formed key, but the bytes no longer verify.
    const [header, payload, signature] = token.split(".");
    const tamperedSignature = signature.split("").reverse().join("");
    const tamperedToken = `${header}.${payload}.${tamperedSignature}`;

    const res = await proxyGet(request, routePath, {
      headers: { "X-Edge-Token": tamperedToken },
    });
    expect(res.status()).toBe(401);
    const body = await res.json();
    expect(body.message).toBe("Signature public key mismatch");
  });

  // [Verifies: trust-verify-signature.key-discovery.allowed-jwks-uri-used]
  test("allowed jwks_uri is used for key discovery", async ({ request }) => {
    // Prefix is a directory boundary short of the full jwks_uri, exercising
    // the "/"-bounded-continuation form of the allow check.
    const prefix = `${KONG_PROXY_URL}/__fixtures__`;
    const { routePath } = await verifyRoute(request, [prefix]);

    const token = signManifestToken({
      alg: "RS256",
      kid: "rsa-2048",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: { jwks_uri: RSA_JWKS_URL },
    });

    const res = await proxyGet(request, routePath, {
      headers: { "X-Edge-Token": token },
    });
    expect(res.status()).toBe(200);
    const echoedHeaders = (await res.json()).headers;
    expect(echoedHeaders["X-Trust-Verify-Signature-Req"]).toBe("OK");
  });

  // [Verifies: trust-verify-signature.key-discovery.jwks-cache-keyed-by-uri]
  test("JWKS cache entries are keyed by jwks_uri", async ({ request }) => {
    const { routePath } = await verifyRoute(request, [
      RSA_JWKS_URL,
      EC_JWKS_URL,
    ]);

    const tokenA = signManifestToken({
      alg: "RS256",
      kid: "rsa-2048",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: { jwks_uri: RSA_JWKS_URL },
    });
    // Warm every DP replica with A's keyset so B cannot pass via a cold
    // per-DP cache that never saw A (which would hide shared-key bugs).
    await primeAllReplicas(async () => {
      const resA = await proxyGet(request, routePath, {
        headers: { "X-Edge-Token": tokenA },
      });
      expect(resA.status()).toBe(200);
    });

    // ec-p256's kid is absent from RSA_JWKS_URL's keyset; this must be
    // verified against EC_JWKS_URL's own cache entry, not A's.
    const tokenB = signManifestToken({
      alg: "ES256",
      kid: "ec-p256",
      privateKeyPem: EC_PRIVATE_KEY,
      payload: { jwks_uri: EC_JWKS_URL },
    });
    const resB = await proxyGet(request, routePath, {
      headers: { "X-Edge-Token": tokenB },
    });
    expect(resB.status()).toBe(200);
    const echoedHeaders = (await resB.json()).headers;
    expect(echoedHeaders["X-Trust-Verify-Signature-Req"]).toBe("OK");
  });
});
