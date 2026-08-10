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

test.describe("trust-verify-signature — response verification", () => {
  test.beforeAll(async ({ request }) => {
    // Only this file's prefix — a shared wipe races with parallel workers.
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-verify-signature.response-verification.valid-token-verified]
  test("valid response token is verified and marked", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        signature_header_key: "X-Edge-Token",
        allowed_jwks_uri_prefix: [RSA_JWKS_URL],
        direction: "response",
      },
    });

    const token = signManifestToken({
      alg: "RS256",
      kid: "rsa-2048",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: { jwks_uri: RSA_JWKS_URL },
    });

    const res = await proxyGet(request, routePath, {
      pathSuffix: `/response-headers?X-Edge-Token=${encodeURIComponent(token)}`,
    });
    expect(res.status()).toBe(200);
    expect(res.headers()["x-trust-verify-signature-res"]).toBe("OK");
    expect(res.headers()["x-edge-token"]).toBe(token);
  });

  // [Verifies: trust-verify-signature.response-verification.valid-token-verified]
  // Requirement also says verification runs regardless of upstream status;
  // /response-headers is always 200, so cover a non-2xx via httpbun /mix.
  // Use 500 (not 404): proxyGet treats 404 as residual DP lag and retries.
  test("valid response token is verified on a non-2xx upstream", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        signature_header_key: "X-Edge-Token",
        allowed_jwks_uri_prefix: [RSA_JWKS_URL],
        direction: "response",
      },
    });

    const token = signManifestToken({
      alg: "RS256",
      kid: "rsa-2048",
      privateKeyPem: RSA_PRIVATE_KEY,
      payload: { jwks_uri: RSA_JWKS_URL },
    });

    const res = await proxyGet(request, routePath, {
      pathSuffix: `/mix/s=500/h=X-Edge-Token:${encodeURIComponent(token)}`,
    });
    expect(res.status()).toBe(500);
    expect(res.headers()["x-trust-verify-signature-res"]).toBe("OK");
    expect(res.headers()["x-edge-token"]).toBe(token);
  });

  // [Verifies: trust-verify-signature.response-verification.missing-header-401]
  test("missing response signature header replaces the response", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        signature_header_key: "X-Edge-Token",
        allowed_jwks_uri_prefix: [RSA_JWKS_URL],
        direction: "response",
      },
    });

    const res = await proxyGet(request, routePath, {
      pathSuffix: "/response-headers",
    });
    expect(res.status()).toBe(401);
    const body = await res.json();
    expect(body.message).toBe("Missing Signature in X-Edge-Token");
  });
});
