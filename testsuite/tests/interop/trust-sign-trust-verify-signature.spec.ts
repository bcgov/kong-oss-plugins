import { test, expect, APIRequestContext } from "@playwright/test";
import {
  KONG_ADMIN_URL,
  provisionKong,
  waitForRouteReady,
  proxyRequest as kongProxyRequest,
} from "../../helpers/kong";
import { upstreamServiceDefaults } from "../../helpers/upstream";
import {
  decodeJwt,
  findHeader,
  contentDigestOf,
} from "../../helpers/trust-sign";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  uniquePrefix,
  fixtureKeysUrl,
  fixtureKeysContainerPath,
  proxyGet,
  proxyRequest,
} from "../../helpers/trust-verify-signature";

const PREFIX = uniquePrefix("trust-sign-trust-verify-signature-interop");
const RSA_JWKS_URL = fixtureKeysUrl("rsa-2048.jwks.json");

/**
 * Provisions a service + route with the real trust-sign plugin attached
 * (producer side of the interop contract), so this suite exercises an
 * actual signed manifest rather than a hand-built one.
 */
async function provisionTrustSignRoute(
  request: APIRequestContext,
  opts: { prefix: string; config: Record<string, unknown> }
): Promise<{ routePath: string }> {
  const serviceRes = await provisionKong(request, `${KONG_ADMIN_URL}/services`, {
    name: `${opts.prefix}-svc`,
    ...upstreamServiceDefaults,
  });
  const serviceId = serviceRes.body.id;

  const routePath = `/${opts.prefix}`;
  const routeRes = await provisionKong(request, `${KONG_ADMIN_URL}/routes`, {
    name: `${opts.prefix}-rt`,
    hosts: ["kong.localtest.me"],
    paths: [routePath],
    strip_path: true,
    service: { id: serviceId },
  });
  const routeId = routeRes.body.id;

  await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
    name: "trust-sign",
    route: { id: routeId },
    config: opts.config,
  });

  await waitForRouteReady(request, routePath, {
    timeoutMs: 30_000,
    consecutive: 9,
  });

  return { routePath };
}

test.describe("interop — trust-sign produces, trust-verify-signature consumes", () => {
  test.beforeAll(async ({ request }) => {
    // Only this file's prefix — a shared wipe races with parallel workers.
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // Signature / JWKS path: response-direction bare manifest (no digest claim).
  test("a manifest signed by trust-sign verifies against trust-verify-signature", async ({
    request,
  }) => {
    const signPrefix = `${PREFIX}-sign`;
    const { routePath: signRoutePath } = await provisionTrustSignRoute(
      request,
      {
        prefix: signPrefix,
        config: {
          keyid: "rsa-2048",
          private_key_location: fixtureKeysContainerPath("rsa-2048.pem"),
          signature_header_key: "X-Edge-Token",
          alg: "RS256",
          direction: "response",
          jwks_uri: RSA_JWKS_URL,
        },
      }
    );

    // Producer side: no inbound X-Edge-Token, so trust-sign emits a bare
    // manifest carrying only jwks_uri + the standard claims.
    // Retry 200s with no signature header — route can be ready while the
    // plugin is still missing on the replica that served the request.
    const signRes = await kongProxyRequest(request, signRoutePath, {
      pathSuffix: "/status/200",
      shouldRetry: async (res) =>
        res.status() === 200 && !res.headers()["x-edge-token"],
    });
    expect(signRes.status()).toBe(200);
    const token = signRes.headers()["x-edge-token"];
    expect(typeof token).toBe("string");
    expect(token.split(".")).toHaveLength(3);

    const verifyPrefix = `${PREFIX}-verify`;
    const { routePath: verifyRoutePath } = await provisionPluginRoute(
      request,
      {
        prefix: verifyPrefix,
        config: {
          signature_header_key: "X-Edge-Token",
          allowed_jwks_uri_prefix: [RSA_JWKS_URL],
          direction: "request",
        },
      }
    );

    // Consumer side: feed the real producer-signed manifest in as the
    // inbound request's signature header.
    const verifyRes = await proxyGet(request, verifyRoutePath, {
      headers: { "X-Edge-Token": token },
    });
    expect(verifyRes.status()).toBe(200);
    const echoedHeaders = (await verifyRes.json()).headers;
    expect(echoedHeaders["X-Trust-Verify-Signature-Req"]).toBe("OK");
    expect(echoedHeaders["X-Edge-Token"]).toBe(token);
  });

  // Content-digest path: request-direction producer binds body digest into
  // the manifest; consumer verifies claim vs Content-Digest (real plugins).
  test("a request digest signed by trust-sign verifies under content-digest mode", async ({
    request,
  }) => {
    const body = "interop trust-sign → trust-verify digest body";
    const expectedDigest = contentDigestOf(body);

    const { routePath: signRoutePath } = await provisionTrustSignRoute(
      request,
      {
        prefix: `${PREFIX}-digest-sign`,
        config: {
          keyid: "rsa-2048",
          private_key_location: fixtureKeysContainerPath("rsa-2048.pem"),
          signature_header_key: "X-Edge-Token",
          alg: "RS256",
          direction: "request",
          jwks_uri: RSA_JWKS_URL,
        },
      }
    );

    // Producer: retry 200s whose echoed headers lack X-Edge-Token — the
    // route can be ready while trust-sign is still missing on that replica.
    const signRes = await kongProxyRequest(request, signRoutePath, {
      method: "POST",
      pathSuffix: "/anything",
      data: body,
      headers: { "Content-Type": "text/plain" },
      shouldRetry: async (res) => {
        if (res.status() !== 200) return false;
        try {
          const headers = (await res.json()).headers ?? {};
          return !findHeader(headers, "X-Edge-Token");
        } catch {
          return false;
        }
      },
    });
    expect(signRes.status()).toBe(200);

    const signHeaders = (await signRes.json()).headers;
    const token = findHeader(signHeaders, "X-Edge-Token");
    const digestHeader = findHeader(signHeaders, "Content-Digest");
    expect(token).toBeTruthy();
    expect(digestHeader).toBe(expectedDigest);
    expect(decodeJwt(token!).payload.digest).toBe(expectedDigest);

    const { routePath: verifyRoutePath } = await provisionPluginRoute(
      request,
      {
        prefix: `${PREFIX}-digest-verify`,
        config: {
          signature_header_key: "X-Edge-Token",
          allowed_jwks_uri_prefix: [RSA_JWKS_URL],
          direction: "request",
          manifest_type: "content-digest",
        },
      }
    );

    const verifyRes = await proxyRequest(request, verifyRoutePath, {
      method: "POST",
      pathSuffix: "/anything",
      data: body,
      headers: {
        "Content-Type": "text/plain",
        "X-Edge-Token": token!,
        "Content-Digest": digestHeader!,
      },
    });
    expect(verifyRes.status()).toBe(200);
    const verifyHeaders = (await verifyRes.json()).headers;
    expect(verifyHeaders["X-Trust-Verify-Signature-Req"]).toBe("OK");

    // Same producer token must fail when Content-Digest does not match.
    const mismatchRes = await proxyRequest(request, verifyRoutePath, {
      method: "POST",
      pathSuffix: "/anything",
      data: body,
      headers: {
        "Content-Type": "text/plain",
        "X-Edge-Token": token!,
        "Content-Digest": contentDigestOf("a different body"),
      },
    });
    expect(mismatchRes.status()).toBe(400);
    const mismatchBody = await mismatchRes.json();
    expect(mismatchBody.message).toBe(
      "Content-Digest header does not match signature manifest"
    );
  });
});
