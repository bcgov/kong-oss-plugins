import { test, expect } from "@playwright/test";
import runE2Etest, { checks } from "../../../helpers/e2e-test";
import { URL } from "url";

test.describe("oidc plugin - happy paths", () => {
  test("unauth_action - deny", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        unauth_action: "deny",
      },
      [
        checks.expected_headers,
        checks.expected_cookies_exist,
        checks.expected_cookie_config,
      ],
      {
        onLoginError: async (response) => {
          const queryParams = new URL(response.request().url()).searchParams;
          console.log(queryParams);

          expect(response.status()).toBe(401);
        },
      }
    );
  });
});
