import { test, expect } from "@playwright/test";
import { KONG_PROXY_URL } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  cleanupStale,
  contentDigestOf,
  CONTAINER_KEYS_DIR,
} from "../../../helpers/trust-sign";

const PREFIX = `trust-sign-${Date.now()}-${process.pid}`;

const responseConfig = {
  keyid: "rsa-2048",
  private_key_location: `${CONTAINER_KEYS_DIR}/rsa-2048.pem`,
  alg: "RS256",
  direction: "response",
};

test.describe("trust-sign — response digest generation", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupStale(request, "trust-sign-");
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-sign.response-digest-generation.missing-digest-nonempty-upstream-body]
  test("sets Content-Digest to the SHA-256 of a non-empty upstream body", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { ...responseConfig },
    });

    const res = await request.get(`${KONG_PROXY_URL}${routePath}/anything`);
    expect(res.status()).toBe(200);

    const body = await res.body();
    expect(body.length).toBeGreaterThan(0);
    expect(res.headers()["content-digest"]).toBe(contentDigestOf(body));
  });

  // [Verifies: trust-sign.response-digest-generation.missing-digest-empty-string-body]
  test("sets the empty-string digest for an empty upstream body", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { ...responseConfig },
    });

    const res = await request.get(`${KONG_PROXY_URL}${routePath}/bytes/0`);
    expect(res.status()).toBe(200);

    const body = await res.body();
    expect(body.length).toBe(0);
    expect(res.headers()["content-digest"]).toBe(
      "sha-256=:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=:"
    );
  });

  // [Verifies: trust-sign.response-digest-generation.upstream-supplied-digest-preserved]
  test("preserves an upstream-supplied Content-Digest unchanged", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { ...responseConfig },
    });

    // deliberately not the digest of the actual response body
    const presetDigest = "sha-256=:cHJlc2V0LWRpZ2VzdA==:";
    const res = await request.get(
      `${KONG_PROXY_URL}${routePath}/response-headers?Content-Digest=${encodeURIComponent(
        presetDigest
      )}`
    );
    expect(res.status()).toBe(200);

    expect(res.headers()["content-digest"]).toBe(presetDigest);
    // sanity: the preserved value differs from what recomputation would yield
    expect(presetDigest).not.toBe(contentDigestOf(await res.body()));
  });
});
