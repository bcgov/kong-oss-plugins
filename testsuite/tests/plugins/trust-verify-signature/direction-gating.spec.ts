import { test, expect } from "@playwright/test";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  uniquePrefix,
  proxyGet,
} from "../../../helpers/trust-verify-signature";

const PREFIX = uniquePrefix("trust-verify-signature");

test.describe("trust-verify-signature — direction gating", () => {
  test.beforeAll(async ({ request }) => {
    // Only this file's prefix — a shared wipe races with parallel workers.
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-verify-signature.direction-gating.unset-noop]
  test("direction unset is a no-op", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        allowed_jwks_uri_prefix: ["https://jwks.example.com"],
        // direction deliberately unset
      },
    });

    const res = await proxyGet(request, routePath);
    expect(res.status()).toBe(200);
    const echoedHeaders = (await res.json()).headers;
    expect(echoedHeaders["X-Trust-Verify-Signature-Req"]).toBeUndefined();
    expect(res.headers()["x-trust-verify-signature-res"]).toBeUndefined();
    expect(res.headers()["x-edge-token"]).toBeUndefined();
  });
});
