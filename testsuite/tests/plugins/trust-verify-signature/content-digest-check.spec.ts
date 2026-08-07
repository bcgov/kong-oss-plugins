import { test, expect } from "@playwright/test";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  uniquePrefix,
  fixtureKeysUrl,
  readFixtureKeyFile,
  signManifestToken,
  proxyGet,
} from "../../../helpers/trust-verify-signature";

const PREFIX = uniquePrefix("trust-verify-signature");
const RSA_JWKS_URL = fixtureKeysUrl("rsa-2048.jwks.json");
const RSA_PRIVATE_KEY = readFixtureKeyFile("rsa-2048.pem");

test.describe("trust-verify-signature — content-digest manifest check", () => {
  test.beforeAll(async ({ request }) => {
    // Only this file's prefix — a shared wipe races with parallel workers.
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  test.describe("signature-only and unset add no manifest checks", () => {
    // [Verifies: trust-verify-signature.content-digest-check.signature-only-or-unset-no-checks]
    test("manifest_type signature-only", async ({ request }) => {
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: {
          signature_header_key: "X-Edge-Token",
          allowed_jwks_uri_prefix: [RSA_JWKS_URL],
          direction: "request",
          manifest_type: "signature-only",
        },
      });

      const token = signManifestToken({
        alg: "RS256",
        kid: "rsa-2048",
        privateKeyPem: RSA_PRIVATE_KEY,
        payload: { jwks_uri: RSA_JWKS_URL }, // no digest claim
      });

      const res = await proxyGet(request, routePath, {
   headers: { "X-Edge-Token": token },
 });
      expect(res.status()).toBe(200);
      const echoedHeaders = (await res.json()).headers;
      expect(echoedHeaders["X-Trust-Verify-Signature-Req"]).toBe("OK");
    });

    // [Verifies: trust-verify-signature.content-digest-check.signature-only-or-unset-no-checks]
    test("manifest_type unset", async ({ request }) => {
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: {
          signature_header_key: "X-Edge-Token",
          allowed_jwks_uri_prefix: [RSA_JWKS_URL],
          direction: "request",
          // manifest_type deliberately unset
        },
      });

      const token = signManifestToken({
        alg: "RS256",
        kid: "rsa-2048",
        privateKeyPem: RSA_PRIVATE_KEY,
        payload: { jwks_uri: RSA_JWKS_URL }, // no digest claim
      });

      const res = await proxyGet(request, routePath, {
   headers: { "X-Edge-Token": token },
 });
      expect(res.status()).toBe(200);
      const echoedHeaders = (await res.json()).headers;
      expect(echoedHeaders["X-Trust-Verify-Signature-Req"]).toBe("OK");
    });
  });

  // [Verifies: trust-verify-signature.content-digest-check.response-direction-skips-checks]
  test("response direction skips content-digest checks", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        signature_header_key: "X-Edge-Token",
        allowed_jwks_uri_prefix: [RSA_JWKS_URL],
        direction: "response",
        manifest_type: "content-digest",
      },
    });

    const token = signManifestToken({
      alg: "RS256",
      kid: "rsa-2048",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: { jwks_uri: RSA_JWKS_URL }, // no digest claim
    });

    const res = await proxyGet(request, routePath, {
      pathSuffix: `/response-headers?X-Edge-Token=${encodeURIComponent(token)}`,
    });
    expect(res.status()).toBe(200);
    expect(res.headers()["x-trust-verify-signature-res"]).toBe("OK");
  });

  // [Verifies: trust-verify-signature.content-digest-check.missing-digest-claim-401]
  test("missing digest claim is rejected in content-digest mode", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        signature_header_key: "X-Edge-Token",
        allowed_jwks_uri_prefix: [RSA_JWKS_URL],
        direction: "request",
        manifest_type: "content-digest",
      },
    });

    // No jwks_uri either: if the digest-claim check truly runs before key
    // discovery, this must still surface the digest-specific message.
    const token = signManifestToken({
      alg: "RS256",
      kid: "rsa-2048",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: {},
    });

    const res = await proxyGet(request, routePath, {
   headers: { "X-Edge-Token": token },
 });
    expect(res.status()).toBe(401);
    const body = await res.json();
    expect(body.message).toBe(
      "Signature missing content digest manifest (digest)"
    );
  });

  // [Verifies: trust-verify-signature.content-digest-check.matching-content-digest-accepted]
  test("matching Content-Digest is accepted", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        signature_header_key: "X-Edge-Token",
        allowed_jwks_uri_prefix: [RSA_JWKS_URL],
        direction: "request",
        manifest_type: "content-digest",
      },
    });

    const digest = "sha-256=:dGVzdC1kaWdlc3Q=:";
    const token = signManifestToken({
      alg: "RS256",
      kid: "rsa-2048",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: { jwks_uri: RSA_JWKS_URL, digest },
    });

    const res = await proxyGet(request, routePath, {
   headers: { "X-Edge-Token": token, "Content-Digest": digest },
 });
    expect(res.status()).toBe(200);
    const echoedHeaders = (await res.json()).headers;
    expect(echoedHeaders["X-Trust-Verify-Signature-Req"]).toBe("OK");
  });

  test.describe("mismatched or missing Content-Digest is rejected", () => {
    // [Verifies: trust-verify-signature.content-digest-check.mismatched-content-digest-400]
    test("differing Content-Digest header", async ({ request }) => {
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: {
          signature_header_key: "X-Edge-Token",
          allowed_jwks_uri_prefix: [RSA_JWKS_URL],
          direction: "request",
          manifest_type: "content-digest",
        },
      });

      const token = signManifestToken({
        alg: "RS256",
        kid: "rsa-2048",
        privateKeyPem: RSA_PRIVATE_KEY,
        payload: {
          jwks_uri: RSA_JWKS_URL,
          digest: "sha-256=:dGVzdC1kaWdlc3Q=:",
        },
      });

      const res = await proxyGet(request, routePath, {
   headers: {
            "X-Edge-Token": token,
            "Content-Digest": "sha-256=:ZGlmZmVyZW50Cg==:",
          },
 });
      expect(res.status()).toBe(400);
      const body = await res.json();
      expect(body.message).toBe(
        "Content-Digest header does not match signature manifest"
      );
    });

    // [Verifies: trust-verify-signature.content-digest-check.mismatched-content-digest-400]
    test("absent Content-Digest header", async ({ request }) => {
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: {
          signature_header_key: "X-Edge-Token",
          allowed_jwks_uri_prefix: [RSA_JWKS_URL],
          direction: "request",
          manifest_type: "content-digest",
        },
      });

      const token = signManifestToken({
        alg: "RS256",
        kid: "rsa-2048",
        privateKeyPem: RSA_PRIVATE_KEY,
        payload: {
          jwks_uri: RSA_JWKS_URL,
          digest: "sha-256=:dGVzdC1kaWdlc3Q=:",
        },
      });

      const res = await proxyGet(request, routePath, {
   headers: { "X-Edge-Token": token },
 });
      expect(res.status()).toBe(400);
      const body = await res.json();
      expect(body.message).toBe(
        "Content-Digest header does not match signature manifest"
      );
    });
  });
});
