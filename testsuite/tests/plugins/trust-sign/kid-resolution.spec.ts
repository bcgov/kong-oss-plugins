import { test, expect, APIRequestContext } from "@playwright/test";
import { uniquePrefix, proxyGet } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  provisionSigningKeyset,
  trustSignConfig,
  cleanupByPrefix,
  cleanupStale,
  decodeJwt,
  findHeader,
} from "../../../helpers/trust-sign";

const PREFIX = uniquePrefix("trust-sign");

async function fetchSignedJwt(
  request: APIRequestContext,
  routePath: string
): Promise<string> {
  const res = await proxyGet(request, routePath, {
    shouldRetry: async (r) => {
      if (r.status() !== 200) return false;
      try {
        const headers = (await r.json()).headers ?? {};
        return !findHeader(headers, "X-Edge-Token");
      } catch {
        return false;
      }
    },
  });
  expect(res.status()).toBe(200);
  const token = findHeader((await res.json()).headers, "X-Edge-Token");
  expect(token).toBeTruthy();
  return token!;
}

async function fetchFailClosed(
  request: APIRequestContext,
  routePath: string
): Promise<void> {
  const res = await proxyGet(request, routePath, {
    // 200 with no token means the plugin has not yet applied on that replica.
    shouldRetry: async (r) => r.status() === 200,
  });
  expect(res.status()).toBeGreaterThanOrEqual(500);
  expect(res.status()).toBeLessThan(600);
  expect(res.headers()["x-edge-token"]).toBeUndefined();
  try {
    const body = await res.json();
    expect(findHeader(body.headers ?? {}, "X-Edge-Token")).toBeUndefined();
  } catch {
    // 5xx body may not be the upstream echo; absence of the response header
    // is the contract.
  }
}

test.describe("trust-sign — JWT kid resolution", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupStale(request, "trust-sign-");
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-sign.jwt-kid-resolution.unique-keyset-match-supplies-kid]
  // [Verifies: trust-sign.jwt-kid-resolution.pem-public-key-material-matched]
  test("a unique PEM keyset match supplies the JWT kid", async ({
    request,
  }) => {
    const keyset = await provisionSigningKeyset(request, { prefix: PREFIX });
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(keyset.keysetName, { direction: "request" }),
    });

    const jwt = decodeJwt(await fetchSignedJwt(request, routePath));
    expect(jwt.header.kid).toBe(keyset.expectedKid);
  });

  // [Verifies: trust-sign.jwt-kid-resolution.jwk-key-material-matched]
  test("a unique JWK keyset match supplies the JWT kid", async ({
    request,
  }) => {
    const jwkKid = `${PREFIX}-jwk`;
    const keyset = await provisionSigningKeyset(request, {
      prefix: PREFIX,
      keys: [{ kid: jwkKid, jwkFile: "rsa-2048.jwks.json" }],
    });
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(keyset.keysetName, { direction: "request" }),
    });

    const jwt = decodeJwt(await fetchSignedJwt(request, routePath));
    expect(jwt.header.kid).toBe(jwkKid);
  });

  // [Verifies: trust-sign.jwt-kid-resolution.independent-of-keyset-ordering]
  test("selects the matching kid regardless of keyset order", async ({
    request,
  }) => {
    const matchKid = `${PREFIX}-match`;
    const otherKid = `${PREFIX}-other`;

    const matchLast = await provisionSigningKeyset(request, {
      prefix: PREFIX,
      keys: [
        { kid: otherKid, publicKeyFile: "ec-p256.pub.pem" },
        { kid: matchKid, publicKeyFile: "rsa-2048.pub.pem" },
      ],
    });
    const matchFirst = await provisionSigningKeyset(request, {
      prefix: PREFIX,
      keys: [
        { kid: `${matchKid}-first`, publicKeyFile: "rsa-2048.pub.pem" },
        { kid: `${otherKid}-first`, publicKeyFile: "ec-p256.pub.pem" },
      ],
    });

    const lastRoute = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(matchLast.keysetName, { direction: "request" }),
    });
    const firstRoute = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(matchFirst.keysetName, { direction: "request" }),
    });

    expect(
      decodeJwt(await fetchSignedJwt(request, lastRoute.routePath)).header.kid
    ).toBe(matchKid);
    expect(
      decodeJwt(await fetchSignedJwt(request, firstRoute.routePath)).header.kid
    ).toBe(`${matchKid}-first`);
  });

  // [Verifies: trust-sign.jwt-kid-resolution.overlap-rotation-selects-matching-kid]
  test("overlap rotation selects the kid matching the mounted private key", async ({
    request,
  }) => {
    const oldKid = `${PREFIX}-old`;
    const newKid = `${PREFIX}-new`;
    const keyset = await provisionSigningKeyset(request, {
      prefix: PREFIX,
      keys: [
        { kid: oldKid, publicKeyFile: "ec-p256.pub.pem" },
        { kid: newKid, publicKeyFile: "rsa-2048.pub.pem" },
      ],
    });
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(keyset.keysetName, { direction: "request" }),
    });

    const jwt = decodeJwt(await fetchSignedJwt(request, routePath));
    expect(jwt.header.kid).toBe(newKid);
    expect(jwt.header.kid).not.toBe(oldKid);
  });

  // [Verifies: trust-sign.jwt-kid-resolution.missing-keyset-fails-closed]
  test("a missing keyset fails closed without emitting a token", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(`${PREFIX}-does-not-exist`, {
        direction: "request",
      }),
    });
    await fetchFailClosed(request, routePath);
  });

  // [Verifies: trust-sign.jwt-kid-resolution.no-matching-key-fails-closed]
  test("no matching key fails closed without emitting a token", async ({
    request,
  }) => {
    const keyset = await provisionSigningKeyset(request, {
      prefix: PREFIX,
      keys: [{ kid: `${PREFIX}-other`, publicKeyFile: "ec-p256.pub.pem" }],
    });
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(keyset.keysetName, { direction: "request" }),
    });
    await fetchFailClosed(request, routePath);
  });

  // [Verifies: trust-sign.jwt-kid-resolution.multiple-matching-keys-fail-closed]
  test("multiple matching keys fail closed without emitting a token", async ({
    request,
  }) => {
    const keyset = await provisionSigningKeyset(request, {
      prefix: PREFIX,
      keys: [
        { kid: `${PREFIX}-a`, publicKeyFile: "rsa-2048.pub.pem" },
        { kid: `${PREFIX}-b`, publicKeyFile: "rsa-2048.pub.pem" },
      ],
    });
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: trustSignConfig(keyset.keysetName, { direction: "request" }),
    });
    await fetchFailClosed(request, routePath);
  });
});
