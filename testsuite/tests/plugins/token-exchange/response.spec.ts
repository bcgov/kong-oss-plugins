import { expect, test } from "@playwright/test";
import {
  KONG_ADMIN_URL,
  provisionKong,
  proxyRequest,
  uniquePrefix,
} from "../../../helpers/kong";
import {
  audienceMapper,
  clientLogin,
  createClient,
} from "../../../helpers/keycloak";
import {
  KEY_PATHS,
  capturesForClient,
  cleanupByPrefix,
  provisionPluginRoute,
  proxyPluginGet,
  tokenEndpoint,
  waitForJwtVerification,
} from "../../../helpers/token-exchange";

const PREFIX = uniquePrefix("token-exchange-response");
let clientCounter = 0;

function clientId(label: string): string {
  clientCounter += 1;
  return `${PREFIX}-${label}-${clientCounter}`;
}

function config(id: string, endpoint: string) {
  return {
    private_key_location: KEY_PATHS.rsa2048,
    client_id: id,
    token_endpoint: endpoint,
  };
}

function tokenScopes(token: string): string[] {
  const payload = JSON.parse(
    Buffer.from(token.split(".")[1], "base64url").toString("utf8")
  );
  return Array.from(new Set(String(payload.scope).split(/\s+/).filter(Boolean)));
}

async function expectHandledError(response: import("@playwright/test").APIResponse, code: string) {
  expect(response.status()).toBe(400);
  const body = await response.json();
  expect(body.message).toBe("Token exchange failed");
  expect(body.error).toMatchObject({ code });
  return body;
}

test.describe("token-exchange — successful and failed exchanges", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: token-exchange.successful-exchange.access-token-replaces-authorization]
  test("replaces inbound credentials with the exchanged access token", async ({ request }) => {
    const id = clientId("replace-authorization");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(id, tokenEndpoint("success", { access_token: "new-access-token" })),
    });
    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound-credential",
    });
    expect(response.status()).toBe(200);
    const upstream = await response.json();
    expect(upstream.headers.Authorization ?? upstream.headers.authorization).toBe(
      "Bearer new-access-token"
    );
    expect(JSON.stringify(upstream.headers)).not.toContain("inbound-credential");
  });

  // [Verifies: token-exchange.successful-exchange.additional-members-ignored]
  test("ignores additional members in a successful token response", async ({ request }) => {
    const id = clientId("additional-members");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(
        id,
        tokenEndpoint("success", {
          access_token: "only-this-token",
          additional: "true",
        })
      ),
    });
    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound",
    });
    expect(response.status()).toBe(200);
    const upstream = await response.json();
    expect(upstream.headers.Authorization ?? upstream.headers.authorization).toBe(
      "Bearer only-this-token"
    );
    expect(upstream.headers).not.toHaveProperty("token_type");
    expect(upstream.headers).not.toHaveProperty("expires_in");
    expect(upstream.headers).not.toHaveProperty("scope");
  });

  // [Verifies: token-exchange.successful-exchange.missing-access-token-unhandled-failure]
  test("rejects missing, non-string, and empty access tokens with E3", async ({ request }) => {
    for (const mode of ["missing", "nonstring", "empty"]) {
      const id = clientId(`bad-access-token-${mode}`);
      const { proxyUrl } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: config(id, tokenEndpoint(mode)),
      });
      const response = await proxyPluginGet(request, proxyUrl, {
        Authorization: "Bearer inbound",
      });
      await expectHandledError(response, "E3");
    }
  });

  // [Verifies: token-exchange.token-endpoint-failure-mapping.transport-failure-e1]
  test("maps token-endpoint transport failure to E1", async ({ request }) => {
    const id = clientId("transport-failure");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(id, "http://token-exchange-mock:9/token/success"),
    });
    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound",
    });
    await expectHandledError(response, "E1");
  });

  // [Verifies: token-exchange.token-endpoint-failure-mapping.non-200-json-e2]
  test("maps a non-200 JSON response to E2 without detail", async ({ request }) => {
    const id = clientId("json-e2");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(id, tokenEndpoint("error-json", { status: 401 })),
    });
    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound",
    });
    const body = await expectHandledError(response, "E2");
    expect(body.error).not.toHaveProperty("detail");
  });

  // [Verifies: token-exchange.token-endpoint-failure-mapping.non-200-non-json-e2]
  test("maps a non-200 non-JSON response to E2 without detail", async ({ request }) => {
    const id = clientId("text-e2");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(id, tokenEndpoint("error-text", { status: 503 })),
    });
    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound",
    });
    const body = await expectHandledError(response, "E2");
    expect(body.error).not.toHaveProperty("detail");
  });

  // [Verifies: token-exchange.configuration-error.invalid-scope]
  test("returns a correlated, redacted configuration error for invalid_scope", async ({
    request,
  }) => {
    const id = clientId("invalid-scope");
    const subjectClient = await createClient(request, {
      standardFlowEnabled: false,
      directAccessGrantsEnabled: false,
      protocolMappers: [audienceMapper("sdx exchange audience", id)],
    });
    const subjectToken = await clientLogin(
      subjectClient.clientId,
      subjectClient.clientSecret
    );
    const expectedScope = tokenScopes(subjectToken).join(" ");
    const { routePath, routeId } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        ...config(
          id,
          tokenEndpoint("error-json", {
            status: 400,
            error: "invalid_scope",
            error_description: "the SDX client is missing a secret scope",
          })
        ),
        audience: "provider-api-secret",
        scopes: ["configured.scope.must.not.be.used"],
      },
    });
    await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
      name: "jwt-keycloak",
      route: { id: routeId },
      config: {
        allowed_iss: ["http://keycloak.localtest.me:9081/auth/realms/e2e"],
      },
    });
    await waitForJwtVerification(request, routePath, id);

    const response = await proxyRequest(request, routePath, {
      headers: { Authorization: `Bearer ${subjectToken}` },
      shouldRetry: async (candidate) => {
        if (candidate.status() !== 500) {
          return true;
        }
        const captures = await capturesForClient(request, id);
        return captures.at(-1)?.form.scope !== expectedScope;
      },
    });

    expect(response.status()).toBe(500);
    const requestId = response.headers()["x-kong-request-id"];
    expect(requestId).toBeTruthy();
    const body = await response.json();
    expect(body.error).toEqual({ code: "SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR" });
    expect(body.message).toBe(
      "The SDX token-exchange client is not configured to complete this request. " +
        `Refer to the SDX Kong token-exchange plugin logs using request ID ${requestId} for details.`
    );

    const publicResponse = JSON.stringify(body);
    expect(publicResponse).not.toContain("invalid_scope");
    expect(publicResponse).not.toContain("secret scope");
    expect(publicResponse).not.toContain("provider-api-secret");
    for (const scope of tokenScopes(subjectToken)) {
      expect(publicResponse).not.toContain(scope);
    }

    const captures = await capturesForClient(request, id);
    expect(captures.at(-1)?.form.scope).toBe(expectedScope);
    expect(captures.at(-1)?.form.audience).toBe("provider-api-secret");
  });

  // [Verifies: token-exchange.token-endpoint-failure-mapping.invalid-200-json-e3]
  test("maps invalid JSON in a 200 response to E3", async ({ request }) => {
    const id = clientId("invalid-json-e3");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(id, tokenEndpoint("invalid-json")),
    });
    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound",
    });
    await expectHandledError(response, "E3");
  });
});
