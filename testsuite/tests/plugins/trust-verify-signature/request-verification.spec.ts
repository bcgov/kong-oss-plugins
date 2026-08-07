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

test.describe("trust-verify-signature — request verification", () => {
  test.beforeAll(async ({ request }) => {
    // Only this file's prefix — a shared wipe races with parallel workers.
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-verify-signature.request-verification.valid-token-verified]
  test("valid token is verified and marked", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        signature_header_key: "X-Edge-Token",
        allowed_jwks_uri_prefix: [RSA_JWKS_URL],
        direction: "request",
      },
    });

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
    expect(echoedHeaders["X-Edge-Token"]).toBe(token);
  });

  // [Verifies: trust-verify-signature.request-verification.missing-header-401]
  test("missing signature header is rejected", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        signature_header_key: "X-Edge-Token",
        allowed_jwks_uri_prefix: [RSA_JWKS_URL],
        direction: "request",
      },
    });

    const res = await proxyGet(request, routePath);
    expect(res.status()).toBe(401);
    const body = await res.json();
    expect(body.message).toBe("Missing Signature in X-Edge-Token");
  });

  // [Verifies: trust-verify-signature.request-verification.unparseable-token-401]
  test("unparseable token is rejected", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        signature_header_key: "X-Edge-Token",
        allowed_jwks_uri_prefix: [RSA_JWKS_URL],
        direction: "request",
      },
    });

    const res = await proxyGet(request, routePath, {
      headers: { "X-Edge-Token": "not-a-jwt-at-all" },
    });
    expect(res.status()).toBe(401);
    const body = await res.json();
    expect(body.message).toMatch(/^Bad token/);
  });
});
