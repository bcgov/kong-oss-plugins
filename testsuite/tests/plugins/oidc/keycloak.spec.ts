import { test, expect } from "@playwright/test";
import { callAPI, setRequestBody, setHeaders } from "../../../helpers/api";
import { adminLogin } from "../../../helpers/keycloak";
import { readFileSync } from "fs";
import { v4 as uuidv4 } from "uuid";

test.describe("keycloak ready", () => {
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
