import { test, expect } from "@playwright/test";
import { KONG_PROXY_URL } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  cleanupStale,
  decodeJwt,
  findHeader,
  CONTAINER_KEYS_DIR,
} from "../../../helpers/trust-sign";

const PREFIX = `trust-sign-${Date.now()}-${process.pid}`;

const requestConfig = {
  keyid: "rsa-2048",
  private_key_location: `${CONTAINER_KEYS_DIR}/rsa-2048.pem`,
  alg: "RS256",
  direction: "request",
};

const JWKS_URI = "https://jwks.example.test/keys.json";

test.describe("trust-sign — request manifest signing", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupStale(request, "trust-sign-");
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-sign.request-manifest-signing.standard-request-signing]
  test("signs the configured header with identity, digest and jwks_uri claims", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      serviceTags: ["client:c1", "service:s1"],
      config: {
        ...requestConfig,
        signature_header_key: "X-Trust-Manifest",
        jwks_uri: JWKS_URI,
      },
    });

    const body = "standard signing body";
    const res = await request.post(`${KONG_PROXY_URL}${routePath}/anything`, {
      data: body,
      headers: { "Content-Type": "text/plain" },
    });
    expect(res.status()).toBe(200);

    const echoedHeaders = (await res.json()).headers;
    const token = findHeader(echoedHeaders, "X-Trust-Manifest");
    expect(token).toBeTruthy();

    const { payload } = decodeJwt(token!);
    expect(payload.client_id).toBe("c1");
    expect(payload.service_id).toBe("s1");
    expect(payload.digest).toBe(findHeader(echoedHeaders, "Content-Digest"));
    expect(payload.jwks_uri).toBe(JWKS_URI);

    // request_id is the Kong request ID for this exchange
    const kongRequestId = res.headers()["x-kong-request-id"];
    expect(kongRequestId).toBeTruthy();
    expect(payload.request_id).toBe(kongRequestId);
  });

  // [Verifies: trust-sign.request-manifest-signing.missing-service-tags-empty-identity]
  test("yields empty identity claims when the service has no tags", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      // no serviceTags
      config: { ...requestConfig, jwks_uri: JWKS_URI },
    });

    const res = await request.get(`${KONG_PROXY_URL}${routePath}/headers`);
    expect(res.status()).toBe(200);

    const echoedHeaders = (await res.json()).headers;
    const token = findHeader(echoedHeaders, "X-Edge-Token");
    expect(token).toBeTruthy();

    const { payload } = decodeJwt(token!);
    expect(payload.client_id).toBe("");
    expect(payload.service_id).toBe("");
  });

  // [Verifies: trust-sign.request-manifest-signing.jwks-uri-unset-omits-claim]
  test("omits the jwks_uri claim when config.jwks_uri is unset", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { ...requestConfig }, // jwks_uri deliberately unset
    });

    const res = await request.get(`${KONG_PROXY_URL}${routePath}/headers`);
    expect(res.status()).toBe(200);

    const echoedHeaders = (await res.json()).headers;
    const token = findHeader(echoedHeaders, "X-Edge-Token");
    expect(token).toBeTruthy();
    expect(decodeJwt(token!).payload).not.toHaveProperty("jwks_uri");
  });

  // [Verifies: trust-sign.request-manifest-signing.signature-header-key-defaults-to-x-edge-token]
  test("writes the manifest to X-Edge-Token when signature_header_key is omitted", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { ...requestConfig }, // signature_header_key deliberately omitted
    });

    const res = await request.get(`${KONG_PROXY_URL}${routePath}/headers`);
    expect(res.status()).toBe(200);

    const echoedHeaders = (await res.json()).headers;
    const token = findHeader(echoedHeaders, "X-Edge-Token");
    expect(token).toBeTruthy();
    const { header } = decodeJwt(token!);
    expect(header.kid).toBe("rsa-2048");
  });
});
