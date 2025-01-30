import { test, expect } from "@playwright/test";
import { URL } from "url";
import runE2Etest, { checks } from "../../../helpers/e2e-test";

test.describe("oidc plugin - happy paths", () => {
  test("bearer_jwt_auth_allowed_auds", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        bearer_jwt_auth_allowed_auds: ["the-aud"],
      },
      [
        checks.expected_headers,
        checks.expected_cookies_exist,
        checks.expected_cookie_config,
      ]
    );
  });
  test("bearer_jwt_auth_enable", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        bearer_jwt_auth_enable: "yes",
      },
      [
        checks.expected_headers,
        checks.expected_cookies_exist,
        checks.expected_cookie_config,
      ]
    );
  });
});
