import { test, expect } from "@playwright/test";
import {
  uniquePrefix,
  mtlsProxyGet,
  disposeMtlsContexts,
  provisionPluginRoute,
  cleanupByPrefix,
  sharedContextObserver,
} from "../../../helpers/mtls-auth";

const PREFIX = uniquePrefix("mtls-auth");

const ERROR_BODY = {
  error: "invalid_request",
  error_description: "mTLS client not provided or invalid",
};

test.describe("mtls-auth — client certificate verification gate", () => {
  test.beforeAll(async ({ request }) => {
    // Only this file's PREFIX — wiping "mtls-auth-" races with parallel workers.
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
    await disposeMtlsContexts();
  });

  // [Verifies: mtls-auth.certificate-verification-gate.missing-certificate]
  test("no client certificate is rejected with 401 and the JSON error body", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {},
    });

    const res = await mtlsProxyGet(request, routePath); // no clientCert
    expect(res.status()).toBe(401);
    expect(res.headers()["content-type"]).toContain("application/json");
    const body = await res.json();
    expect(body.error).toBe(ERROR_BODY.error);
    expect(body.error_description).toBe(ERROR_BODY.error_description);
    // The body is the plugin's error, not the upstream echo — nothing was proxied.
    expect(body.headers).toBeUndefined();
  });

  // [Verifies: mtls-auth.certificate-verification-gate.failed-verification]
  test("failed certificate verification is rejected with 401 and the JSON error body", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {},
      extraPlugins: [sharedContextObserver()],
    });

    // untrusted is signed by a CA the DPs do not trust -> $ssl_client_verify FAILED:…
    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "untrusted",
    });
    expect(res.status()).toBe(401);
    expect(res.headers()["content-type"]).toContain("application/json");
    const body = await res.json();
    expect(body.error).toBe(ERROR_BODY.error);
    expect(body.error_description).toBe(ERROR_BODY.error_description);
    expect(body.headers).toBeUndefined();
    // The spec's "shared context SHALL NOT be populated" clause, observed via
    // the header_filter observer (a rejected request never reaches later
    // access-phase plugins). This is the one reject path where a certificate
    // actually exists on the connection and could leak into the context.
    expect(res.headers()["x-shared-keys"]).toBe("__absent__");
  });

  // [Verifies: mtls-auth.certificate-verification-gate.custom-status]
  test("error_response_code overrides the rejection status", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { error_response_code: 495 },
    });

    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "untrusted",
    });
    expect(res.status()).toBe(495);
    expect(res.headers()["content-type"]).toContain("application/json");
    const body = await res.json();
    expect(body.error).toBe(ERROR_BODY.error);
    expect(body.error_description).toBe(ERROR_BODY.error_description);
    expect(body.headers).toBeUndefined();
  });

  // [Verifies: mtls-auth.certificate-verification-gate.success-passthrough]
  test("verified client certificate is proxied upstream untouched", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {},
    });

    const res = await mtlsProxyGet(request, routePath, { clientCert: "alice" });
    expect(res.status()).toBe(200);
    // The upstream echo answered: the request was proxied, not terminated.
    const body = await res.json();
    expect(body.headers).toBeDefined();
    expect(body.error).toBeUndefined();
  });
});
