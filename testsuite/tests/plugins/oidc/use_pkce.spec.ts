import { test, expect } from "@playwright/test";
import runE2Etest, { checks } from "../../../helpers/e2e-test";
import { URL } from "url";
import logger from "../../../helpers/logger";

test.describe("oidc plugin - happy paths", () => {
  test("public client and use_pkce", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {
        clientAuthenticatorType: "public",
        publicClient: true,
        secret: null,
        attributes: {
          "pkce.code.challenge.method": "S256",
        },
      },
      {
        use_pkce: "yes",
        token_endpoint_auth_method: "none", // avoids client_secret being sent to TOKEN endpoint
      },
      [
        checks.expected_headers,
        checks.expected_cookies_exist,
        checks.expected_cookie_config,
      ]
    );
  });
});

test.describe("oidc plugin - exception paths", () => {
  test("public client without use_pkce", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {
        clientAuthenticatorType: "public",
        publicClient: true,
        secret: null,
        attributes: {
          "pkce.code.challenge.method": "S256",
        },
      },
      {
        use_pkce: "false",
        token_endpoint_auth_method: "none", // avoids client_secret being sent to TOKEN endpoint
      },
      [
        checks.expected_headers,
        checks.expected_cookies_exist,
        checks.expected_cookie_config,
      ],
      {
        onLoginError: async (response) => {
          logger.debug(response, "test login error response");
          const queryParams = new URL(response.request().url()).searchParams;
          logger.debug(queryParams, "test login error query params");

          expect(queryParams.get("error_description")).toBe(
            "Missing parameter: code_challenge_method"
          );
        },
      }
    );
  });
});
