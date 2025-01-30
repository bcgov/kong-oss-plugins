import { test, expect, Cookie, Page } from "@playwright/test";
import { URL } from "url";
import runE2Etest, { checks } from "../../../helpers/e2e-test";

test.describe("oidc plugin - happy paths", () => {
  test("using defaults", async ({ page, request }) => {
    await runE2Etest(page, request, {}, {});
  });
});
