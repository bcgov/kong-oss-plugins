import { test, expect, Page } from "@playwright/test";
import runE2Etest, { checks } from "../../../helpers/e2e-test";
import { URL } from "url";

test.describe("oidc plugin - happy paths", () => {
  test("token headers - different name", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        disable_access_token_header: "no",
        disable_id_token_header: "no",
        disable_userinfo_header: "no",
        access_token_as_bearer: "no",
        access_token_header_name: "Y-Access-Token",
        id_token_header_name: "Y-ID-Token",
        userinfo_header_name: "Y-USERINFO",
      },
      [
        async (page: Page, jsonData: any) => {
          // Check for existence of upstream request headers
          expect(jsonData.headers["X-Credential-Identifier"]).toBe("local");
          expect(jsonData.headers["X-Forwarded-Host"]).toBe(
            "kong.localtest.me"
          );

          for (const propName of [
            "Y-Access-Token",
            "Y-Id-Token",
            "Y-Userinfo",
          ]) {
            expect(jsonData.headers).toHaveProperty(propName);
          }
        },
        ,
        checks.expected_cookies_exist,
        checks.expected_cookie_config,
      ]
    );
  });
  test("token headers - not sent", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        disable_access_token_header: "yes",
        disable_id_token_header: "yes",
        disable_userinfo_header: "yes",
      },
      [
        async (page: Page, jsonData: any) => {
          // Check for existence of upstream request headers
          expect(jsonData.headers["X-Credential-Identifier"]).toBe("local");
          expect(jsonData.headers["X-Forwarded-Host"]).toBe(
            "kong.localtest.me"
          );

          for (const propName of [
            "X-Access-Token",
            "X-Id-Token",
            "X-Userinfo",
          ]) {
            expect(jsonData.headers).not.toHaveProperty(propName);
          }
        },
        ,
        checks.expected_cookies_exist,
        checks.expected_cookie_config,
      ]
    );
  });
});
