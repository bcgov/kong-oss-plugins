import { test, expect } from "@playwright/test";

test.describe("oidc plugin", () => {
  test("login", async ({ page }) => {
    await page.goto("http:///kong.localtest.me:5500/headers");

    await expect(page).toHaveTitle(/Sign in/);

    await page.locator("input[name=username]").fill("local");
    await page.locator("input[name=password]").fill("local");
    await page.locator("button[type=submit]").click();

    await expect(page.locator("pre")).toBeInViewport();
  });
});
