import { APIRequestContext, expect, test } from "@playwright/test";
import prepare from "../../../helpers/prepare-client-and-service";
import { clientLogin } from "../../../helpers/keycloak";
import {
  KONG_ADMIN_URL,
  provisionKong,
  proxyGet,
  waitForRouteReady,
} from "../../../helpers/kong";

const issuer = "http://keycloak.localtest.me:9081/auth/realms/e2e";
const unmatchedConsumerMessage = "Unable to match token to a Kong consumer";
const stableProbeCount = 9;

function responseHeaders(body: { headers: Record<string, unknown> }) {
  return Object.fromEntries(
    Object.entries(body.headers).map(([name, value]) => [
      name.toLowerCase(),
      value,
    ])
  );
}

async function prepareConsumerMatch(
  request: APIRequestContext,
  overrides: Record<string, unknown> = {}
) {
  const prepared = await prepare(
    request,
    {
      standardFlowEnabled: false,
      directAccessGrantsEnabled: false,
    },
    "jwt-keycloak",
    {
      allowed_iss: [issuer],
      consumer_match: true,
      consumer_match_claim: "azp",
      consumer_match_claim_custom_id: true,
      consumer_match_ignore_not_found: false,
      ...overrides,
    }
  );

  await waitForRouteReady(request, prepared.routePath, {
    timeoutMs: 15_000,
    consecutive: 9,
  });

  const accessToken = await clientLogin(
    prepared.clientDetails.clientId,
    prepared.clientDetails.clientSecret
  );

  return { ...prepared, accessToken };
}

async function authenticatedGet(
  request: APIRequestContext,
  routePath: string,
  accessToken: string,
  expectedStatus: number
) {
  return proxyGet(request, routePath, {
    headers: { Authorization: `Bearer ${accessToken}` },
    shouldRetry: (response) => response.status() !== expectedStatus,
  });
}

test.describe("jwt-keycloak consumer matching", () => {
  // [Verifies: APS-4990 custom_id matching]
  test("authenticates the consumer whose custom_id matches azp", async ({
    request,
  }) => {
    const { routePath, clientDetails, accessToken } =
      await prepareConsumerMatch(request);

    await provisionKong(request, `${KONG_ADMIN_URL}/consumers`, {
      username: `consumer-${clientDetails.clientId}`,
      custom_id: clientDetails.clientId,
    });

    const response = await authenticatedGet(
      request,
      routePath,
      accessToken,
      200
    );

    expect(response.status()).toBe(200);
    const body = await response.json();
    const headers = responseHeaders(body);
    expect(headers["x-consumer-custom-id"]).toBe(clientDetails.clientId);
  });

  // [Verifies: APS-4990 username compatibility]
  test("preserves username matching when custom_id matching is disabled", async ({
    request,
  }) => {
    const { routePath, clientDetails, accessToken } =
      await prepareConsumerMatch(request, {
        consumer_match_claim_custom_id: false,
      });

    await provisionKong(request, `${KONG_ADMIN_URL}/consumers`, {
      username: clientDetails.clientId,
    });

    const response = await authenticatedGet(
      request,
      routePath,
      accessToken,
      200
    );

    expect(response.status()).toBe(200);
    const body = await response.json();
    const headers = responseHeaders(body);
    expect(headers["x-consumer-username"]).toBe(clientDetails.clientId);
  });

  // [Verifies: APS-4990 invalid match claims]
  test("returns a stable 401 when the configured match claim is missing", async ({
    request,
  }) => {
    const { routePath, clientDetails, accessToken } =
      await prepareConsumerMatch(request, {
        consumer_match_claim: "claim-that-is-not-present",
      });

    const response = await authenticatedGet(
      request,
      routePath,
      accessToken,
      401
    );

    expect(response.status()).toBe(401);
    const body = await response.json();
    expect(body).toEqual({ message: unmatchedConsumerMessage });
    expect(JSON.stringify(body)).not.toContain(clientDetails.clientId);
  });

  // [Verifies: APS-4990 unknown consumer response]
  test("returns a stable 401 without exposing an unknown custom_id", async ({
    request,
  }) => {
    const { routePath, clientDetails, accessToken } =
      await prepareConsumerMatch(request);

    const response = await authenticatedGet(
      request,
      routePath,
      accessToken,
      401
    );

    expect(response.status()).toBe(401);
    const body = await response.json();
    expect(body).toEqual({ message: unmatchedConsumerMessage });
    expect(JSON.stringify(body)).not.toContain(clientDetails.clientId);
  });

  // [Verifies: APS-4990 ignore-not-found compatibility]
  test("allows an unknown custom_id when ignore-not-found is enabled", async ({
    request,
  }) => {
    const { routePath, accessToken } = await prepareConsumerMatch(request, {
      consumer_match_ignore_not_found: true,
    });

    const deadline = Date.now() + 15_000;
    let consecutiveDenials = 0;
    while (Date.now() < deadline && consecutiveDenials < stableProbeCount) {
      const probe = await proxyGet(request, routePath, {
        attempts: 1,
        headers: { Connection: "close" },
      });
      consecutiveDenials =
        probe.status() === 401 ? consecutiveDenials + 1 : 0;
      if (consecutiveDenials < stableProbeCount) {
        await new Promise((resolve) => setTimeout(resolve, 250));
      }
    }
    expect(consecutiveDenials).toBe(stableProbeCount);

    const response = await authenticatedGet(
      request,
      routePath,
      accessToken,
      200
    );

    expect(response.status()).toBe(200);
    const body = await response.json();
    const headers = responseHeaders(body);
    expect(headers["x-consumer-custom-id"]).toBeUndefined();
    expect(headers["x-consumer-username"]).toBeUndefined();
  });
});
