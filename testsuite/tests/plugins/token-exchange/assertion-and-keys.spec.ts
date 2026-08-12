import { expect, test } from "@playwright/test";
import { proxyGet, uniquePrefix } from "../../../helpers/kong";
import {
  KEY_PATHS,
  PUBLIC_KEY_FILES,
  capturesForClient,
  cleanupByPrefix,
  decodeClientAssertion,
  provisionPluginRoute,
  proxyPluginGet,
  tokenEndpoint,
  verifyClientAssertion,
} from "../../../helpers/token-exchange";

const PREFIX = uniquePrefix("token-exchange-assertion");
let clientCounter = 0;

function clientId(label: string): string {
  clientCounter += 1;
  return `${PREFIX}-${label}-${clientCounter}`;
}

test.describe("token-exchange — client assertions and private keys", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: token-exchange.client-assertion-contents.default-metadata]
  test("emits fresh default RS256 assertion metadata", async ({ request }) => {
    const id = clientId("default-metadata");
    const endpoint = tokenEndpoint("success");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        private_key_location: KEY_PATHS.rsa2048,
        client_id: id,
        token_endpoint: endpoint,
      },
    });

    const before = Math.floor(Date.now() / 1000);
    const first = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound-one",
    });
    const second = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound-two",
    });
    const after = Math.floor(Date.now() / 1000);
    expect(first.status()).toBe(200);
    expect(second.status()).toBe(200);

    const captures = await capturesForClient(request, id);
    expect(captures).toHaveLength(2);
    const assertions = captures.map((capture) => capture.form.client_assertion);
    const decoded = assertions.map(decodeClientAssertion);

    for (const assertion of decoded) {
      expect(assertion.header.alg).toBe("RS256");
      expect(assertion.header).not.toHaveProperty("kid");
      expect(assertion.payload.iss).toBe(id);
      expect(assertion.payload.sub).toBe(id);
      expect(assertion.payload.aud).toBe(endpoint);
      expect(assertion.payload.jti).toMatch(/^[0-9a-f]{32}$/);
      expect(assertion.payload.iat).toEqual(expect.any(Number));
      expect(assertion.payload.iat).toBeGreaterThanOrEqual(before);
      expect(assertion.payload.iat).toBeLessThanOrEqual(after);
      expect(assertion.payload.exp).toBe((assertion.payload.iat as number) + 60);
    }
    expect(decoded[0].payload.jti).not.toBe(decoded[1].payload.jti);
  });

  // [Verifies: token-exchange.client-assertion-contents.configured-metadata]
  test("uses configured kid, algorithm, and expiration", async ({ request }) => {
    const id = clientId("configured-metadata");
    const endpoint = tokenEndpoint("success");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        private_key_location: KEY_PATHS.rsa2048,
        client_id: id,
        token_endpoint: endpoint,
        key_id: "configured-key-id",
        algorithm: "RS384",
        expiration: 137,
      },
    });

    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound",
    });
    expect(response.status()).toBe(200);

    const captures = await capturesForClient(request, id);
    expect(captures).toHaveLength(1);
    const assertion = decodeClientAssertion(captures[0].form.client_assertion);
    expect(assertion.header.alg).toBe("RS384");
    expect(assertion.header.kid).toBe("configured-key-id");
    expect(assertion.payload.exp).toBe((assertion.payload.iat as number) + 137);
  });

  // [Verifies: token-exchange.client-assertion-contents.non-sha256-label-uses-sha256]
  test("uses the digest and signature encoding named by every algorithm label", async ({
    request,
  }) => {
    test.setTimeout(90_000);
    const cases = [
      ["RS256", KEY_PATHS.rsa2048, PUBLIC_KEY_FILES.rsa2048, "sha256", false],
      ["RS384", KEY_PATHS.rsa2048, PUBLIC_KEY_FILES.rsa2048, "sha384", false],
      ["RS512", KEY_PATHS.rsa2048, PUBLIC_KEY_FILES.rsa2048, "sha512", false],
      ["ES256", KEY_PATHS.ecP256, PUBLIC_KEY_FILES.ecP256, "sha256", true],
      ["ES384", KEY_PATHS.ecP384, PUBLIC_KEY_FILES.ecP384, "sha384", true],
      ["ES512", KEY_PATHS.ecP521, PUBLIC_KEY_FILES.ecP521, "sha512", true],
    ] as const;

    for (const [algorithm, privateKey, publicKey, digest, ellipticCurve] of cases) {
      const id = clientId(algorithm.toLowerCase());
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: {
          private_key_location: privateKey,
          client_id: id,
          token_endpoint: tokenEndpoint("success"),
          algorithm,
        },
      });

      const response = await proxyGet(request, routePath, {
        headers: { Authorization: "Bearer inbound" },
      });
      expect(response.status()).toBe(200);
      const captures = await capturesForClient(request, id);
      expect(captures).toHaveLength(1);
      const assertion = captures[0].form.client_assertion;
      expect(decodeClientAssertion(assertion).header.alg).toBe(algorithm);
      expect(verifyClientAssertion(assertion, publicKey, digest, ellipticCurve)).toBe(true);
    }
  });

  // [Verifies: token-exchange.client-assertion-contents.algorithm-key-type-mismatch]
  test("rejects RSA/EC algorithm and private-key type mismatches before exchange", async ({
    request,
  }) => {
    const cases = [
      ["RS256", KEY_PATHS.ecP256],
      ["ES256", KEY_PATHS.rsa2048],
    ] as const;

    for (const [algorithm, privateKey] of cases) {
      const id = clientId(`mismatch-${algorithm.toLowerCase()}`);
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: {
          private_key_location: privateKey,
          client_id: id,
          token_endpoint: tokenEndpoint("success"),
          algorithm,
        },
      });

      const response = await proxyGet(request, routePath, {
        headers: { Authorization: "Bearer inbound" },
      });
      expect(response.status()).toBe(500);
      expect(await response.text()).toMatch(/private key|key type|signing algorithm/i);
      expect(await capturesForClient(request, id)).toEqual([]);
    }
  });

  // [Verifies: token-exchange.private-key-resolution.configured-key-signs-assertion]
  test("signs with the configured readable PEM key", async ({ request }) => {
    const id = clientId("configured-key");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        private_key_location: KEY_PATHS.rsa2048,
        client_id: id,
        token_endpoint: tokenEndpoint("success"),
      },
    });

    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound",
    });
    expect(response.status()).toBe(200);
    const captures = await capturesForClient(request, id);
    expect(captures).toHaveLength(1);
    expect(
      verifyClientAssertion(
        captures[0].form.client_assertion,
        PUBLIC_KEY_FILES.rsa2048,
        "sha256"
      )
    ).toBe(true);
  });

  // [Verifies: token-exchange.private-key-resolution.malformed-key-aborts-request]
  test("aborts every request when the readable key is malformed", async ({ request }) => {
    const id = clientId("malformed-key");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        private_key_location: KEY_PATHS.malformed,
        client_id: id,
        token_endpoint: tokenEndpoint("success"),
      },
    });

    for (const token of ["first", "second"]) {
      const response = await proxyPluginGet(request, proxyUrl, {
        Authorization: `Bearer ${token}`,
      });
      expect(response.status()).toBe(500);
      expect(await response.text()).toMatch(/private key.*(?:parse|invalid)|parse.*private key/i);
    }
    expect(await capturesForClient(request, id)).toEqual([]);
  });

  // [Verifies: token-exchange.private-key-resolution.unreadable-key-aborts-request]
  test("aborts every request when the key path cannot be read", async ({ request }) => {
    const id = clientId("unreadable-key");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        private_key_location: KEY_PATHS.unreadable,
        client_id: id,
        token_endpoint: tokenEndpoint("success"),
      },
    });

    for (const token of ["first", "second"]) {
      const response = await proxyPluginGet(request, proxyUrl, {
        Authorization: `Bearer ${token}`,
      });
      expect(response.status()).toBe(500);
      expect(await response.text()).toMatch(/private key.*(?:read|open)|(?:read|open).*private key/i);
    }
    expect(await capturesForClient(request, id)).toEqual([]);
  });
});
