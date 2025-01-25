import { test, expect } from "@playwright/test";

test.describe("keycloak ready", () => {
  test("login", async ({ browser, page, request }) => {
    await page.goto("http:///keycloak.localtest.me:9081");

    await expect(page).toHaveTitle(/Sign in/);

    await page.locator("input[name=username]").fill("local");
    await page.locator("input[name=password]").fill("local");
    await page.locator("button[type=submit]").click();

    await expect(page).toHaveTitle(/Administration Console/);

    await page.locator("[data-test-id=dashboard-tabs]");

    await page.goto(
      "http:///keycloak.localtest.me:9081/auth/admin/master/console/#/master/clients"
    );

    await page.waitForLoadState("networkidle");

    await page.screenshot({ path: "subscribe-demo.png" });
  });
});
