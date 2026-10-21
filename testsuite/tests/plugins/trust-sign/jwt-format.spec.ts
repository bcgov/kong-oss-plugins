import { test, expect } from "@playwright/test";
import { uniquePrefix, proxyGet } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  provisionSigningKeyset,
  trustSignConfig,
  cleanupByPrefix,
  cleanupStale,
  decodeJwt,
  verifyJws,
  digestForAlg,
  fixtureKeyPem,
  findHeader,
  CONTAINER_KEYS_DIR,
  type SigningKeyset,
} from "../../../helpers/trust-sign";

const PREFIX = uniquePrefix("trust-sign");

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

let keyset: SigningKeyset;

function baseConfig(alg: string) {
  return trustSignConfig(keyset.keysetName, { alg, direction: "request" });
}

async function fetchEmittedToken(
  request: any,
  routePath: string
): Promise<string> {
  const res = await proxyGet(request, routePath);
  expect(res.status()).toBe(200);
  const echoedHeaders = (await res.json()).headers;
  const token = findHeader(echoedHeaders, "X-Edge-Token");
  expect(token).toBeTruthy();
  return token!;
}

test.describe("trust-sign — JWT token format and key resolution", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupStale(request, "trust-sign-");
    keyset = await provisionSigningKeyset(request, { prefix: PREFIX });
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-sign.jwt-token-format.token-structure]
  // [Verifies: trust-sign.jwt-token-format.header-alg-single-source-of-truth.rs256]
  test("emits a verifiable JWS with alg/kid header and jti/iat claims", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: baseConfig("RS256"),
    });

    const token = await fetchEmittedToken(request, routePath);
    expect(token.split(".")).toHaveLength(3);

    const jwt = decodeJwt(token);
    expect(jwt.header.alg).toBe("RS256");
    expect(jwt.header.kid).toBe(keyset.expectedKid);
    expect(jwt.payload.jti).toMatch(UUID_RE);
    expect(typeof jwt.payload.iat).toBe("number");

    // signature over <header>.<payload> with the digest derived from config.alg
    expect(
      verifyJws(jwt, fixtureKeyPem("rsa-2048.pub.pem"), digestForAlg("RS256"))
    ).toBe(true);
  });

  // [Verifies: trust-sign.jwt-token-format.header-alg-single-source-of-truth.rs512]
  // pending — APS-4798
  test("RS512 signatures verify with sha512", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: baseConfig("RS512"),
    });

    test.fail(true, "pending — APS-4798");

    const token = await fetchEmittedToken(request, routePath);
    const jwt = decodeJwt(token);
    expect(jwt.header.alg).toBe("RS512");

    // a verifier that trusts header.alg must succeed
    expect(
      verifyJws(jwt, fixtureKeyPem("rsa-2048.pub.pem"), digestForAlg("RS512"))
    ).toBe(true);
  });

  // [Verifies: trust-sign.private-key-resolution.key-from-configuration]
  test("tokens verify against the public key of config.private_key_location", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: baseConfig("RS256"),
    });

    const token = await fetchEmittedToken(request, routePath);
    const jwt = decodeJwt(token);

    // This scenario pins *which key* signed the token (KONG_SIGNING_CERT_KEY
    // is unset in the shared stack). Digest choice for RS256 is covered by
    // header-alg-single-source-of-truth.rs256; accept either digest here as
    // long as the configured key verifies.
    const publicKey = fixtureKeyPem("rsa-2048.pub.pem");
    const verifies =
      verifyJws(jwt, publicKey, "sha256") || verifyJws(jwt, publicKey, "sha512");
    expect(verifies).toBe(true);
  });

  // [Verifies: trust-sign.configuration-schema.alg-must-match-key-type]
  // pending — APS-4798
  test("ECDSA alg with an RSA key fails the exchange with a 5xx", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: baseConfig("ES256"), // RSA key file + ECDSA alg
    });

    test.fail(true, "pending — APS-4798");

    const res = await proxyGet(request, routePath);
    expect(res.status()).toBeGreaterThanOrEqual(500);
    expect(res.status()).toBeLessThan(600);
    // no signed manifest is emitted anywhere
    expect(res.headers()["x-edge-token"]).toBeUndefined();
  });

  // [Verifies: trust-sign.configuration-schema.alg-must-match-key-type]
  // pending — APS-4798
  test("RSA alg with an ECDSA key fails the exchange with a 5xx", async ({
    request,
  }) => {
    const ecKeyset = await provisionSigningKeyset(request, {
      prefix: PREFIX,
      keys: [{ kid: `${PREFIX}-ec`, publicKeyFile: "ec-p256.pub.pem" }],
    });
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        keyset_name: ecKeyset.keysetName,
        private_key_location: `${CONTAINER_KEYS_DIR}/ec-p256.pem`,
        alg: "RS256", // ECDSA key file + RSA alg
        direction: "request",
      },
    });

    test.fail(true, "pending — APS-4798");

    const res = await proxyGet(request, routePath);
    expect(res.status()).toBeGreaterThanOrEqual(500);
    expect(res.status()).toBeLessThan(600);
    expect(res.headers()["x-edge-token"]).toBeUndefined();
  });
});
