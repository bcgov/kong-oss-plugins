import { test, expect } from "@playwright/test";
import { callAPI, setRequestBody, setHeaders } from "../helpers/api";
import { adminLogin } from "../helpers/keycloak";
import { readFileSync } from "fs";
import { v4 as uuidv4 } from "uuid";

test.describe("keycloak ready", () => {
  test("login", async ({ browser, page, request }) => {
    await page.goto("http:///keycloak.localtest.me:9081");

    await expect(page).toHaveTitle(/Sign in/);

    await page.locator("input[name=username]").fill("local");
    await page.locator("input[name=password]").fill("local");
    await page.locator("button[type=submit]").click();

    await expect(page).toHaveTitle(/Administration Console/);

    //await page.locator("[data-test-id=dashboard-tabs]");

    await page.goto("/auth/admin/master/console/#/master/clients");

    await page.waitForLoadState("networkidle");

    await page.screenshot({ path: "subscribe-demo.png" });

    await browser.close();
  });

  test("create client", async ({ page, request }) => {
    const bearerToken = await adminLogin();

    const payload = JSON.parse(
      readFileSync("./local/keycloak/client.json", "utf8")
    );

    const uid = uuidv4().replace(/-/g, "").toUpperCase().substring(0, 5);

    payload.clientId = "test-client-" + uid;

    setRequestBody(payload);
    setHeaders({
      Authorization: "Bearer " + bearerToken,
    });

    const {
      apiRes: { status, body, headers },
    } = await callAPI(
      request,
      `http:///keycloak.localtest.me:9081/auth/admin/realms/master/clients`,
      "POST"
    );
    expect(status).toBe(201);
    console.log(headers["location"]);

    // http://kong.localtest.me:5500/headers
  });
});
