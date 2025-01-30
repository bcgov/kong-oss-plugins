import { test, expect, Cookie, Page } from "@playwright/test";
import { URL } from "url";
import runE2Etest, { checks } from "../../../helpers/e2e-test";

test.describe("oidc plugin - happy paths", () => {
  test("use_jwks", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        use_jwks: "yes",
      }
    );
  });

  test("ssl_verify", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        ssl_verify: "yes",
      }
    );
  });

  test("validate_scope", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        scope: "openid phone",
        validate_scope: "yes",
      }
    );
  });

  test("ignore_auth_filters[no]", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        ignore_auth_filters: "no",
      }
    );
  });

  test("ignore_auth_filters[yes]", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        ignore_auth_filters: "yes",
      }
    );
  });

  test("header_claims", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        header_claims: ["sub"],
        header_names: ["X-SUB"],
      },
      [
        checks.expected_headers,
        checks.expected_cookies_exist,
        checks.expected_cookie_config,
        async (page: Page, jsonData: any) => {
          expect(jsonData.headers).toHaveProperty("X-Sub");
        },
      ]
    );
  });
});
