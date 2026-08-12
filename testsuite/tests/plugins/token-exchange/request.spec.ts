import { expect, test } from "@playwright/test";
import { proxyGet, uniquePrefix } from "../../../helpers/kong";
import {
  KEY_PATHS,
  capturesForClient,
  cleanupByPrefix,
  provisionPluginRoute,
  proxyPluginGet,
  selfSignedTokenEndpoint,
  tokenEndpoint,
} from "../../../helpers/token-exchange";

const STALE_PREFIX = "token-exchange-request-";
const PREFIX = uniquePrefix("token-exchange-request");
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

test.describe("token-exchange — subject extraction and endpoint request", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, STALE_PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: token-exchange.subject-token-extraction.bearer-token-extracted]
  test("extracts a bearer token after one or more whitespace characters", async ({
    request,
  }) => {
    const cases = [
      ["Bearer one-space", "one-space"],
      ["Bearer\tseveral-spaces", "several-spaces"],
    ];

    for (const [authorization, expectedSubject] of cases) {
      const id = clientId("bearer");
      const { proxyUrl } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: config(id, tokenEndpoint("success")),
      });
      const response = await proxyPluginGet(request, proxyUrl, {
        Authorization: authorization,
      });
      expect(response.status()).toBe(200);
      const captures = await capturesForClient(request, id);
      expect(captures).toHaveLength(1);
      expect(captures[0].form.subject_token).toBe(expectedSubject);
    }
  });

  // [Verifies: token-exchange.subject-token-extraction.missing-header-unhandled-failure]
  test("returns a Kong-generated 5xx when Authorization is missing", async ({ request }) => {
    const id = clientId("missing-authorization");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(id, tokenEndpoint("success")),
    });

    const response = await proxyPluginGet(request, proxyUrl);
    expect(response.status()).toBeGreaterThanOrEqual(500);
    expect(response.status()).toBeLessThan(600);
    expect(await response.text()).not.toContain("Token exchange failed");
    expect(await capturesForClient(request, id)).toEqual([]);
  });

  // [Verifies: token-exchange.subject-token-extraction.nonmatching-header-omits-subject-token]
  test("still exchanges while omitting a nonmatching subject token", async ({ request }) => {
    for (const authorization of ["bearer lowercase", "Basic credentials"]) {
      const id = clientId("nonmatching");
      const { proxyUrl } = await provisionPluginRoute(request, {
        prefix: PREFIX,
        config: config(id, tokenEndpoint("success")),
      });
      const response = await proxyPluginGet(request, proxyUrl, {
        Authorization: authorization,
      });
      expect(response.status()).toBe(200);
      const captures = await capturesForClient(request, id);
      expect(captures).toHaveLength(1);
      expect(captures[0].form).not.toHaveProperty("subject_token");
    }
  });

  // [Verifies: token-exchange.subject-token-extraction.embedded-bearer-substring-accepted]
  test("accepts an embedded Bearer substring", async ({ request }) => {
    const id = clientId("embedded-bearer");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(id, tokenEndpoint("success")),
    });
    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "arbitrary prefix Bearer embedded-token",
    });
    expect(response.status()).toBe(200);
    const captures = await capturesForClient(request, id);
    expect(captures).toHaveLength(1);
    expect(captures[0].form.subject_token).toBe("embedded-token");
  });

  // [Verifies: token-exchange.token-endpoint-request.standard-request]
  test("sends one canonical form-encoded exchange request", async ({ request }) => {
    const id = clientId("standard-request");
    const endpoint = tokenEndpoint("success");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(id, endpoint),
    });
    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound-subject",
    });
    expect(response.status()).toBe(200);

    const captures = await capturesForClient(request, id);
    expect(captures).toHaveLength(1);
    const capture = captures[0];
    expect(capture.method).toBe("POST");
    expect(capture.headers["content-type"]).toContain("application/x-www-form-urlencoded");
    expect(capture.headers.accept).toBe("application/json");
    expect(capture.form.client_id).toBe(id);
    expect(capture.form.client_assertion.split(".")).toHaveLength(3);
    expect(capture.form.client_assertion_type).toBe(
      "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    );
    expect(capture.form.grant_type).toBe(
      "urn:ietf:params:oauth:grant-type:token-exchange"
    );
    expect(capture.form.subject_token_type).toBe(
      "urn:ietf:params:oauth:token-type:access_token"
    );
    expect(capture.form.requested_token_type).toBe(
      "urn:ietf:params:oauth:token-type:access_token"
    );
    expect(capture.form.subject_token).toBe("inbound-subject");
  });

  // [Verifies: token-exchange.token-endpoint-request.standard-request]
  test("verifies the token endpoint TLS certificate", async ({ request }) => {
    const id = clientId("tls-verification");
    const { proxyUrl } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(id, selfSignedTokenEndpoint()),
    });
    const response = await proxyPluginGet(request, proxyUrl, {
      Authorization: "Bearer inbound",
    });
    expect(response.status()).toBe(400);
    const body = await response.json();
    expect(body.message).toBe("Token exchange failed");
    expect(body.error).toMatchObject({ code: "E1" });
    expect(await capturesForClient(request, id)).toEqual([]);
  });

  // [Verifies: token-exchange.token-endpoint-request.audience-conditional]
  test("includes audience only when configured", async ({ request }) => {
    const configuredId = clientId("audience-set");
    const configured = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        ...config(configuredId, tokenEndpoint("success")),
        audience: "payments-api",
      },
    });
    expect(
      (
        await proxyGet(request, configured.routePath, {
          headers: { Authorization: "Bearer inbound" },
        })
      ).status()
    ).toBe(200);
    const configuredCaptures = await capturesForClient(request, configuredId);
    expect(configuredCaptures).toHaveLength(1);
    expect(configuredCaptures[0].form.audience).toBe("payments-api");

    const omittedId = clientId("audience-unset");
    const omitted = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(omittedId, tokenEndpoint("success")),
    });
    expect(
      (
        await proxyGet(request, omitted.routePath, {
          headers: { Authorization: "Bearer inbound" },
        })
      ).status()
    ).toBe(200);
    const omittedCaptures = await capturesForClient(request, omittedId);
    expect(omittedCaptures).toHaveLength(1);
    expect(omittedCaptures[0].form).not.toHaveProperty("audience");
  });

  // [Verifies: token-exchange.token-endpoint-request.scopes-joined-in-order]
  test("joins scopes in configured order and omits an empty scope", async ({ request }) => {
    const configuredId = clientId("scopes-set");
    const configured = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        ...config(configuredId, tokenEndpoint("success")),
        scopes: ["read:first", "write:second", "admin:third"],
      },
    });
    expect(
      (
        await proxyGet(request, configured.routePath, {
          headers: { Authorization: "Bearer inbound" },
        })
      ).status()
    ).toBe(200);
    const configuredCaptures = await capturesForClient(request, configuredId);
    expect(configuredCaptures).toHaveLength(1);
    expect(configuredCaptures[0].form.scope).toBe(
      "read:first write:second admin:third"
    );

    const emptyId = clientId("scopes-empty");
    const empty = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        ...config(emptyId, tokenEndpoint("success")),
        scopes: [],
      },
    });
    expect(
      (
        await proxyGet(request, empty.routePath, {
          headers: { Authorization: "Bearer inbound" },
        })
      ).status()
    ).toBe(200);
    const emptyCaptures = await capturesForClient(request, emptyId);
    expect(emptyCaptures).toHaveLength(1);
    expect(emptyCaptures[0].form).not.toHaveProperty("scope");
  });

  // [Verifies: token-exchange.token-endpoint-request.timeout-field-unavailable]
  test("uses a configured timeout and the 10-second default", async ({ request }) => {
    const configuredId = clientId("timeout-configured");
    const configured = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        ...config(configuredId, tokenEndpoint("success", { delay_ms: 1000 })),
        timeout: 150,
      },
    });
    const configuredResponse = await proxyPluginGet(request, configured.proxyUrl, {
      Authorization: "Bearer inbound",
    });
    expect(configuredResponse.status()).toBe(400);
    expect((await configuredResponse.json()).error).toMatchObject({ code: "E1" });
    const configuredCaptures = await capturesForClient(request, configuredId);
    expect(configuredCaptures).toHaveLength(1);
    expect(Date.now() - configuredCaptures[0].receivedAt).toBeLessThan(900);

    const defaultId = clientId("timeout-default");
    const omitted = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: config(defaultId, tokenEndpoint("success", { delay_ms: 11_000 })),
    });
    const defaultResponse = await proxyPluginGet(request, omitted.proxyUrl, {
      Authorization: "Bearer inbound",
    });
    expect(defaultResponse.status()).toBe(400);
    expect((await defaultResponse.json()).error).toMatchObject({ code: "E1" });
    const defaultCaptures = await capturesForClient(request, defaultId);
    expect(defaultCaptures).toHaveLength(1);
    const elapsedFromEndpointRequest = Date.now() - defaultCaptures[0].receivedAt;
    expect(elapsedFromEndpointRequest).toBeGreaterThanOrEqual(9_000);
    expect(elapsedFromEndpointRequest).toBeLessThan(13_000);
  });
});
