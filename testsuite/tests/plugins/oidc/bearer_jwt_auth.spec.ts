import { test, expect } from "@playwright/test";
import { URL } from "url";
import runE2Etest from "../../../helpers/e2e-test";

test.describe("oidc plugin - happy paths", () => {
  test("bearer_jwt_auth_allowed_auds", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        bearer_jwt_auth_allowed_auds: ["the-aud"],
      }
    );
  });
  test("bearer_jwt_auth_enable", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        bearer_jwt_auth_enable: "yes",
      }
    );
  });
});
