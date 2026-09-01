import { test, expect } from "@playwright/test";
import { uniquePrefix, proxyGet, proxyRequest } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  cleanupStale,
  decodeJwt,
  contentDigestOf,
  findHeader,
  CONTAINER_KEYS_DIR,
} from "../../../helpers/trust-sign";

const PREFIX = uniquePrefix("trust-sign");

const baseConfig = {
  keyid: "rsa-2048",
  private_key_location: `${CONTAINER_KEYS_DIR}/rsa-2048.pem`,
  alg: "RS256",
};

test.describe("trust-sign — direction gating", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupStale(request, "trust-sign-"); // stale entities from prior runs
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-sign.direction-gating.unset-noop]
  test("direction unset is a no-op", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { ...baseConfig }, // direction deliberately unset
    });

    const res = await proxyGet(request, routePath);
    expect(res.status()).toBe(200);
    const echoedHeaders = (await res.json()).headers;
    expect(findHeader(echoedHeaders, "X-Edge-Token")).toBeUndefined();
    expect(findHeader(echoedHeaders, "Content-Digest")).toBeUndefined();
    expect(res.headers()["x-edge-token"]).toBeUndefined();
    expect(res.headers()["content-digest"]).toBeUndefined();
  });

  // [Verifies: trust-sign.direction-gating.request-leaves-response-untouched]
  test("request direction signs the upstream request only", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { ...baseConfig, direction: "request" },
    });

    const body = "direction-gating request body";
    const res = await proxyRequest(request, routePath, {
      method: "POST",
      pathSuffix: "/anything",
      data: body,
      headers: { "Content-Type": "text/plain" },
    });
    expect(res.status()).toBe(200);

    // upstream request carries the signature and digest headers
    const echoedHeaders = (await res.json()).headers;
    const token = findHeader(echoedHeaders, "X-Edge-Token");
    expect(token).toBeTruthy();
    expect(decodeJwt(token!).payload).toBeTruthy();
    expect(findHeader(echoedHeaders, "Content-Digest")).toBe(
      contentDigestOf(body)
    );

    // the client response is not modified by the plugin
    expect(res.headers()["x-edge-token"]).toBeUndefined();
    expect(res.headers()["content-digest"]).toBeUndefined();
  });

  // [Verifies: trust-sign.direction-gating.response-leaves-request-untouched]
  test("response direction signs the client response only", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { ...baseConfig, direction: "response" },
    });

    const res = await proxyGet(request, routePath);
    expect(res.status()).toBe(200);

    // the upstream request is not modified by the plugin
    const echoedHeaders = (await res.json()).headers;
    expect(findHeader(echoedHeaders, "X-Edge-Token")).toBeUndefined();
    expect(findHeader(echoedHeaders, "Content-Digest")).toBeUndefined();

    // signature and digest headers are added to the client response
    const responseToken = res.headers()["x-edge-token"];
    expect(responseToken).toBeTruthy();
    expect(decodeJwt(responseToken).payload).toBeTruthy();
    expect(res.headers()["content-digest"]).toBeTruthy();
  });
});
