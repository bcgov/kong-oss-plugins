import { test, expect } from "@playwright/test";

test.describe("keycloak ready", () => {
  test("login", async ({ browser, page, request }) => {
    await page.goto(
      "http:///keycloak.localtest.me:9081/auth/admin/master/console"
    );

    await expect(page).toHaveTitle(/Sign in/);

    await page.locator("input[name=username]").fill("local");
    await page.locator("input[name=password]").fill("local");
    await page.locator("[type=submit]").click();

    await expect(page).toHaveTitle(
      /[Keycloak Admin Console|Administration Console]/
    );

    //await expect(page.getByTestId("dashboard-tabs")).toBeAttached();

    await page.goto(
      "http:///keycloak.localtest.me:9081/auth/admin/master/console/#/master/clients"
    );

    await page.waitForLoadState("networkidle");
  });
});
