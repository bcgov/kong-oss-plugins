import { test, expect } from "@playwright/test";
import runE2Etest, { checks } from "../../../helpers/e2e-test";
import { URL } from "url";
import logger from "../../../helpers/logger";

test.describe("oidc plugin - happy paths", () => {
  test("public client and use_nonce", async ({ page, request }) => {
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
        use_nonce: "yes",
        token_endpoint_auth_method: "none", // avoids client_secret being sent to TOKEN endpoint
      },
      [
        checks.expected_headers,
        checks.expected_cookies_exist,
        checks.expected_cookie_config,
      ],
      {
        onLoginSuccess: async (response) => {
          const queryParams = new URL(response.request().url()).searchParams;
          logger.debug(queryParams, "test login success query params");
          expect(queryParams.get("nonce")).not.toBeNull();
          expect(queryParams.get("code_challenge")).not.toBeNull();
          expect(queryParams.get("code_challenge_method")).toBe("S256");
        },
      }
    );
  });
});
