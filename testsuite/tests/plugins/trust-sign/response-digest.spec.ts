import { test, expect } from "@playwright/test";
import { uniquePrefix, proxyGet } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  provisionSigningKeyset,
  trustSignConfig,
  cleanupByPrefix,
  cleanupStale,
  contentDigestOf,
  type SigningKeyset,
} from "../../../helpers/trust-sign";

const PREFIX = uniquePrefix("trust-sign");

let keyset: SigningKeyset;

test.describe("trust-sign — response digest generation", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupStale(request, "trust-sign-");
    keyset = await provisionSigningKeyset(request, { prefix: PREFIX });
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
      config: trustSignConfig(keyset.keysetName, { direction: "response" }),
    });

    const res = await proxyGet(request, routePath, { pathSuffix: "/anything" });
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
      config: trustSignConfig(keyset.keysetName, { direction: "response" }),
    });

    const res = await proxyGet(request, routePath, { pathSuffix: "/bytes/0" });
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
      config: trustSignConfig(keyset.keysetName, { direction: "response" }),
    });

    // deliberately not the digest of the actual response body
    const presetDigest = "sha-256=:cHJlc2V0LWRpZ2VzdA==:";
    const res = await proxyGet(request, routePath, {
      pathSuffix: `/response-headers?Content-Digest=${encodeURIComponent(
        presetDigest
      )}`,
    });
    expect(res.status()).toBe(200);

    expect(res.headers()["content-digest"]).toBe(presetDigest);
    // sanity: the preserved value differs from what recomputation would yield
    expect(presetDigest).not.toBe(contentDigestOf(await res.body()));
  });
});
