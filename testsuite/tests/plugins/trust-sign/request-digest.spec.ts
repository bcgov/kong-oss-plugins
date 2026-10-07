import { test, expect } from "@playwright/test";
import { uniquePrefix, proxyRequest } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  provisionSigningKeyset,
  trustSignConfig,
  cleanupByPrefix,
  cleanupStale,
  decodeJwt,
  contentDigestOf,
  findHeader,
  type SigningKeyset,
} from "../../../helpers/trust-sign";

const PREFIX = uniquePrefix("trust-sign");

let keyset: SigningKeyset;

test.describe("trust-sign — request digest generation", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupStale(request, "trust-sign-");
    keyset = await provisionSigningKeyset(request, { prefix: PREFIX });
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-sign.request-digest-generation.missing-digest-nonempty-body]
  test("computes Content-Digest for a non-empty body and mirrors it in the manifest", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(keyset.keysetName, { direction: "request" }),
    });

    const body = "trust-sign digest body";
    const expectedDigest = contentDigestOf(body);
    const res = await proxyRequest(request, routePath, {
      method: "POST",
      pathSuffix: "/anything",
      data: body,
      headers: { "Content-Type": "text/plain" },
    });
    expect(res.status()).toBe(200);

    const echoedHeaders = (await res.json()).headers;
    expect(findHeader(echoedHeaders, "Content-Digest")).toBe(expectedDigest);

    const token = findHeader(echoedHeaders, "X-Edge-Token");
    expect(token).toBeTruthy();
    expect(decodeJwt(token!).payload.digest).toBe(expectedDigest);
  });

  // [Verifies: trust-sign.request-digest-generation.missing-digest-empty-string-body]
  test("computes the empty-string digest for an empty raw body", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(keyset.keysetName, { direction: "request" }),
    });

    const expectedDigest = contentDigestOf(""); // sha-256=:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=:
    const res = await proxyRequest(request, routePath, {
      method: "POST",
      pathSuffix: "/anything",
      data: "",
      headers: { "Content-Type": "text/plain" },
    });
    expect(res.status()).toBe(200);

    const echoedHeaders = (await res.json()).headers;
    expect(findHeader(echoedHeaders, "Content-Digest")).toBe(expectedDigest);

    const token = findHeader(echoedHeaders, "X-Edge-Token");
    expect(token).toBeTruthy();
    expect(decodeJwt(token!).payload.digest).toBe(expectedDigest);
  });

  // [Verifies: trust-sign.request-digest-generation.no-body-available]
  test("adds no Content-Digest when the raw body is unavailable", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(keyset.keysetName, { direction: "request" }),
    });

    // A body larger than nginx's in-memory client body buffer is spooled to
    // disk, making the raw body unavailable to the plugin (the scenario's
    // "no body at all (raw body unavailable)" condition).
    const largeBody = "x".repeat(1024 * 1024);
    const res = await proxyRequest(request, routePath, {
      method: "POST",
      pathSuffix: "/anything",
      data: largeBody,
      headers: { "Content-Type": "text/plain" },
    });
    expect(res.status()).toBe(200);

    const echoedHeaders = (await res.json()).headers;
    expect(findHeader(echoedHeaders, "Content-Digest")).toBeUndefined();

    const token = findHeader(echoedHeaders, "X-Edge-Token");
    expect(token).toBeTruthy();
    expect(decodeJwt(token!).payload).not.toHaveProperty("digest");
  });

  // [Verifies: trust-sign.request-digest-generation.client-supplied-digest-trusted]
  // quirk — the inbound digest is never validated against the actual body
  test("passes a client-supplied Content-Digest through unvalidated", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(keyset.keysetName, { direction: "request" }),
    });

    const body = "actual body";
    // deliberately the digest of a *different* body — must be trusted as-is
    const bogusDigest = contentDigestOf("a completely different body");
    expect(bogusDigest).not.toBe(contentDigestOf(body));

    const res = await proxyRequest(request, routePath, {
      method: "POST",
      pathSuffix: "/anything",
      data: body,
      headers: {
        "Content-Type": "text/plain",
        "Content-Digest": bogusDigest,
      },
    });
    expect(res.status()).toBe(200);

    const echoedHeaders = (await res.json()).headers;
    expect(findHeader(echoedHeaders, "Content-Digest")).toBe(bogusDigest);

    const token = findHeader(echoedHeaders, "X-Edge-Token");
    expect(token).toBeTruthy();
    expect(decodeJwt(token!).payload.digest).toBe(bogusDigest);
  });
});
