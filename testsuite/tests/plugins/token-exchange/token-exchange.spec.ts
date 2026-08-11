import { expect, test, APIResponse } from "@playwright/test";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import {
  CapturedExchange,
  KONG_PROXY_URL,
  TokenExchangeConfig,
  cleanupByPrefix,
  clearMockCaptures,
  getMockCapture,
  mockTokenEndpoint,
  provisionPluginRoute,
} from "../../../helpers/token-exchange";

const PREFIX = `token-exchange-${Date.now()}`;
const KEY_ROOT = "/tmp/kong/fixtures/keys";
const LOCAL_KEY_ROOT = path.resolve(__dirname, "../../../local/kong/fixtures/keys");
let captureCounter = 0;

function captureId(label: string) {
  captureCounter += 1;
  return `${PREFIX}-${label}-${captureCounter}`;
}

function config(
  tokenEndpoint: string,
  overrides: Partial<TokenExchangeConfig> = {}
): TokenExchangeConfig {
  return {
    private_key_location: `${KEY_ROOT}/rsa-2048.pem`,
    client_id: "spec-client",
    token_endpoint: tokenEndpoint,
    ...overrides,
  };
}

async function exchange(
  request: Parameters<typeof provisionPluginRoute>[0],
  routePath: string,
  authorization = "Bearer inbound-token"
) {
  return request.get(`${KONG_PROXY_URL}${routePath}/headers`, {
    headers: { Authorization: authorization },
  });
}

async function requiredCapture(
  request: Parameters<typeof getMockCapture>[0],
  id: string
): Promise<CapturedExchange> {
  const captured = await getMockCapture(request, id);
  expect(captured).toBeDefined();
  return captured!;
}

function decodeJwt(jwt: string) {
  const segments = jwt.split(".");
  expect(segments).toHaveLength(3);
  return {
    segments,
    header: JSON.parse(Buffer.from(segments[0], "base64url").toString("utf8")),
    payload: JSON.parse(Buffer.from(segments[1], "base64url").toString("utf8")),
  };
}

function verifyJwt(
  jwt: string,
  publicKeyFile: string,
  digest: "sha256" | "sha384" | "sha512",
  ec = false
) {
  const [header, payload, signature] = jwt.split(".");
  return crypto.verify(
    digest,
    Buffer.from(`${header}.${payload}`),
    {
      key: fs.readFileSync(path.join(LOCAL_KEY_ROOT, publicKeyFile), "utf8"),
      ...(ec ? { dsaEncoding: "ieee-p1363" as const } : {}),
    },
    Buffer.from(signature, "base64url")
  );
}

function headerValue(headers: Record<string, unknown>, name: string) {
  const entry = Object.entries(headers).find(
    ([candidate]) => candidate.toLowerCase() === name.toLowerCase()
  );
  return entry?.[1];
}

async function jsonBody(response: APIResponse) {
  const text = await response.text();
  return { text, body: JSON.parse(text) };
}

async function expectHandledError(response: APIResponse, code: string) {
  expect(response.status()).toBe(400);
  const { body } = await jsonBody(response);
  expect(body.message).toBe("Token exchange failed");
  expect(body.error).toEqual(expect.objectContaining({ code }));
  expect(body).not.toHaveProperty("headers");
  return body;
}

test.describe("token-exchange — spec behavior", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, "token-exchange-");
    await clearMockCaptures(request);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: token-exchange.client-assertion-contents.default-metadata]
  test("emits fresh default RS256 assertion metadata", async ({ request }) => {
    const firstId = captureId("default-assertion-a");
    const firstEndpoint = mockTokenEndpoint(firstId);
    const firstRoute = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(firstEndpoint),
    });
    expect((await exchange(request, firstRoute.routePath)).status()).toBe(200);
    const firstJwt = (await requiredCapture(request, firstId)).form.client_assertion;
    const first = decodeJwt(firstJwt);

    expect(first.header.alg).toBe("RS256");
    expect(first.header).not.toHaveProperty("kid");
    expect(first.payload.iss).toBe("spec-client");
    expect(first.payload.sub).toBe("spec-client");
    expect(first.payload.aud).toBe(firstEndpoint);
    expect(first.payload.jti).toMatch(/^[0-9a-f]{32}$/);
    expect(first.payload.exp - first.payload.iat).toBe(60);
    expect(Math.abs(first.payload.iat - Math.floor(Date.now() / 1000))).toBeLessThanOrEqual(10);

    const secondId = captureId("default-assertion-b");
    const secondEndpoint = mockTokenEndpoint(secondId);
    const secondRoute = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(secondEndpoint),
    });
    expect((await exchange(request, secondRoute.routePath)).status()).toBe(200);
    const secondJwt = (await requiredCapture(request, secondId)).form.client_assertion;
    const second = decodeJwt(secondJwt);
    expect(second.payload.jti).toMatch(/^[0-9a-f]{32}$/);
    expect(second.payload.jti).not.toBe(first.payload.jti);
  });

  // [Verifies: token-exchange.client-assertion-contents.configured-metadata]
  test("emits configured assertion metadata", async ({ request }) => {
    const id = captureId("configured-assertion");
    const endpoint = mockTokenEndpoint(id);
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(endpoint, {
        algorithm: "RS384",
        expiration: 137,
        key_id: "configured-key-id",
      }),
    });

    expect((await exchange(request, routePath)).status()).toBe(200);
    const jwt = (await requiredCapture(request, id)).form.client_assertion;
    const decoded = decodeJwt(jwt);
    expect(decoded.header.alg).toBe("RS384");
    expect(decoded.header.kid).toBe("configured-key-id");
    expect(decoded.payload.exp - decoded.payload.iat).toBe(137);
  });

  // [Verifies: token-exchange.client-assertion-contents.non-sha256-label-uses-sha256]
  test("signs each algorithm label with its matching digest", async ({ request }) => {
    test.setTimeout(120_000);
    const cases = [
      ["RS256", "rsa-2048.pem", "rsa-2048.pub.pem", "sha256", false],
      ["RS384", "rsa-2048.pem", "rsa-2048.pub.pem", "sha384", false],
      ["RS512", "rsa-2048.pem", "rsa-2048.pub.pem", "sha512", false],
      ["ES256", "ec-p256.pem", "ec-p256.pub.pem", "sha256", true],
      ["ES384", "ec-p384.pem", "ec-p384.pub.pem", "sha384", true],
      ["ES512", "ec-p521.pem", "ec-p521.pub.pem", "sha512", true],
    ] as const;

    for (const [algorithm, privateKey, publicKey, digest, ec] of cases) {
      const id = captureId(`digest-${algorithm}`);
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: config(mockTokenEndpoint(id), {
          algorithm,
          private_key_location: `${KEY_ROOT}/${privateKey}`,
        }),
      });
      const response = await exchange(request, routePath);
      expect(response.status(), `${algorithm}: ${await response.text()}`).toBe(200);
      const jwt = (await requiredCapture(request, id)).form.client_assertion;
      expect(decodeJwt(jwt).header.alg).toBe(algorithm);
      expect(verifyJwt(jwt, publicKey, digest, ec)).toBe(true);
    }
  });

  // [Verifies: token-exchange.client-assertion-contents.algorithm-key-type-mismatch]
  test("rejects RSA/EC algorithm and private-key type mismatches", async ({ request }) => {
    const cases = [
      ["RS256", `${KEY_ROOT}/ec-p256.pem`],
      ["ES256", `${KEY_ROOT}/rsa-2048.pem`],
    ] as const;

    for (const [algorithm, privateKey] of cases) {
      const id = captureId(`key-mismatch-${algorithm}`);
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: config(mockTokenEndpoint(id), {
          algorithm,
          private_key_location: privateKey,
        }),
      });
      const response = await exchange(request, routePath);
      expect(response.status()).toBe(500);
      expect(await response.text()).toMatch(/private key.*(?:type|algorithm)|algorithm.*private key/i);
      expect(await getMockCapture(request, id)).toBeUndefined();
    }
  });

  // [Verifies: token-exchange.private-key-resolution.configured-key-signs-assertion]
  test("signs with the configured readable PEM key", async ({ request }) => {
    const id = captureId("configured-key");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id), {
        private_key_location: `${KEY_ROOT}/rsa-3072.pem`,
      }),
    });
    const response = await exchange(request, routePath);
    expect(response.status(), `rsa-3072: ${await response.text()}`).toBe(200);
    const jwt = (await requiredCapture(request, id)).form.client_assertion;
    expect(verifyJwt(jwt, "rsa-3072.pub.pem", "sha256")).toBe(true);
    expect(verifyJwt(jwt, "rsa-2048.pub.pem", "sha256")).toBe(false);
  });

  // [Verifies: token-exchange.private-key-resolution.malformed-key-aborts-request]
  test("aborts before exchange when a readable key is malformed", async ({ request }) => {
    const id = captureId("malformed-key");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id), {
        private_key_location: "/tmp/kong/fixtures/token-exchange-malformed-key.pem",
      }),
    });
    const response = await exchange(request, routePath);
    expect(response.status()).toBe(500);
    const body = await response.text();
    expect(body).toMatch(/private key.*(?:parse|invalid)|(?:parse|invalid).*private key/i);
    expect(body).not.toContain('"headers"');
    expect(await getMockCapture(request, id)).toBeUndefined();
  });

  // [Verifies: token-exchange.private-key-resolution.unreadable-key-generates-ephemeral-key]
  test("aborts before exchange when the key file is unreadable", async ({ request }) => {
    const id = captureId("unreadable-key");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id), {
        private_key_location: `${KEY_ROOT}/missing-${Date.now()}.pem`,
      }),
    });
    const response = await exchange(request, routePath);
    expect(response.status()).toBe(500);
    const body = await response.text();
    expect(body).toMatch(/private key.*(?:read|open|file)|(?:read|open).*private key/i);
    expect(body).not.toContain('"headers"');
    expect(await getMockCapture(request, id)).toBeUndefined();
  });

  // [Verifies: token-exchange.subject-token-extraction.bearer-token-extracted]
  test("extracts a bearer token after one or more whitespace characters", async ({ request }) => {
    const id = captureId("bearer-extracted");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id)),
    });
    expect((await exchange(request, routePath, "Bearer \t subject-token-123")).status()).toBe(200);
    expect((await requiredCapture(request, id)).form.subject_token).toBe("subject-token-123");
  });

  // [Verifies: token-exchange.subject-token-extraction.missing-header-unhandled-failure]
  test("returns a Kong-generated 5xx for a missing Authorization header", async ({ request }) => {
    const id = captureId("missing-authorization");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id)),
    });
    const response = await request.get(`${KONG_PROXY_URL}${routePath}/headers`);
    expect(response.status()).toBeGreaterThanOrEqual(500);
    expect(response.status()).toBeLessThan(600);
    expect(await response.text()).not.toContain("Token exchange failed");
    expect(await getMockCapture(request, id)).toBeUndefined();
  });

  // [Verifies: token-exchange.subject-token-extraction.nonmatching-header-omits-subject-token]
  test("calls the endpoint without subject_token for nonmatching authorization", async ({ request }) => {
    const id = captureId("nonmatching-authorization");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id)),
    });
    expect((await exchange(request, routePath, "bearer lowercase-token")).status()).toBe(200);
    expect((await requiredCapture(request, id)).form).not.toHaveProperty("subject_token");
  });

  // [Verifies: token-exchange.subject-token-extraction.embedded-bearer-substring-accepted]
  test("accepts an embedded Bearer substring", async ({ request }) => {
    const id = captureId("embedded-bearer");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id)),
    });
    expect((await exchange(request, routePath, "prefix text Bearer embedded-token")).status()).toBe(200);
    expect((await requiredCapture(request, id)).form.subject_token).toBe("embedded-token");
  });

  // [Verifies: token-exchange.token-endpoint-request.audience-conditional]
  test("includes audience only when configured", async ({ request }) => {
    for (const audience of ["api://payments", undefined]) {
      const id = captureId(audience ? "audience-set" : "audience-unset");
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: config(mockTokenEndpoint(id), { audience }),
      });
      const response = await exchange(request, routePath);
      expect(
        response.status(),
        `audience=${String(audience)}: ${await response.text()}`
      ).toBe(200);
      const form = (await requiredCapture(request, id)).form;
      if (audience) expect(form.audience).toBe(audience);
      else expect(form).not.toHaveProperty("audience");
    }
  });

  // [Verifies: token-exchange.token-endpoint-request.scopes-joined-in-order]
  test("joins scopes in order and omits an empty scope list", async ({ request }) => {
    for (const scopes of [["read", "write", "admin"], []]) {
      const id = captureId(scopes.length ? "scopes-set" : "scopes-empty");
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: config(mockTokenEndpoint(id), { scopes }),
      });
      const response = await exchange(request, routePath);
      expect(
        response.status(),
        `scopes=${JSON.stringify(scopes)}: ${await response.text()}`
      ).toBe(200);
      const form = (await requiredCapture(request, id)).form;
      if (scopes.length) expect(form.scope).toBe("read write admin");
      else expect(form).not.toHaveProperty("scope");
    }
  });

  // [Verifies: token-exchange.successful-exchange.access-token-replaces-authorization]
  test("replaces inbound credentials with the exchanged access token", async ({ request }) => {
    const id = captureId("replace-authorization");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id, { accessToken: "new-access-token" })),
    });
    const response = await exchange(request, routePath, "Bearer old-access-token");
    expect(response.status()).toBe(200);
    const upstream = await response.json();
    expect(headerValue(upstream.headers, "authorization")).toBe("Bearer new-access-token");
  });

  // [Verifies: token-exchange.successful-exchange.additional-members-ignored]
  test("ignores additional successful token-response members", async ({ request }) => {
    const id = captureId("additional-members");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(
        mockTokenEndpoint(id, { mode: "success-extra", accessToken: "only-this-token" })
      ),
    });
    const response = await exchange(request, routePath);
    expect(response.status()).toBe(200);
    const upstream = await response.json();
    expect(headerValue(upstream.headers, "authorization")).toBe("Bearer only-this-token");
    expect(headerValue(upstream.headers, "token_type")).toBeUndefined();
    expect(headerValue(upstream.headers, "expires_in")).toBeUndefined();
    expect(headerValue(upstream.headers, "scope")).toBeUndefined();
  });

  // [Verifies: token-exchange.successful-exchange.missing-access-token-unhandled-failure]
  test("rejects missing, non-string, and empty access tokens with E3", async ({ request }) => {
    for (const mode of ["missing", "non-string", "empty"]) {
      const id = captureId(`bad-access-token-${mode}`);
      const { routePath } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: config(mockTokenEndpoint(id, { mode })),
      });
      await expectHandledError(await exchange(request, routePath), "E3");
      expect(await getMockCapture(request, id)).toBeDefined();
    }
  });

  // [Verifies: token-exchange.token-endpoint-failure-mapping.transport-failure-e1]
  test("maps token-endpoint transport failure to E1", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config("http://127.0.0.1:1/token", { timeout: 250 }),
    });
    await expectHandledError(await exchange(request, routePath), "E1");
  });

  // [Verifies: token-exchange.token-endpoint-failure-mapping.non-200-json-e2]
  test("maps a non-200 JSON token response to E2 without detail", async ({ request }) => {
    const id = captureId("non-200-json");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id, { mode: "non-200-json" })),
    });
    const body = await expectHandledError(await exchange(request, routePath), "E2");
    expect(body.error).not.toHaveProperty("detail");
  });

  // [Verifies: token-exchange.token-endpoint-failure-mapping.non-200-non-json-e2]
  test("maps a non-200 non-JSON token response to E2 without detail", async ({ request }) => {
    const id = captureId("non-200-text");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id, { mode: "non-200-text" })),
    });
    const body = await expectHandledError(await exchange(request, routePath), "E2");
    expect(body.error).not.toHaveProperty("detail");
  });

  // [Verifies: token-exchange.token-endpoint-failure-mapping.invalid-200-json-e3]
  test("maps invalid JSON in a 200 token response to E3", async ({ request }) => {
    const id = captureId("invalid-200-json");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(mockTokenEndpoint(id, { mode: "invalid-json" })),
    });
    await expectHandledError(await exchange(request, routePath), "E3");
  });
});
