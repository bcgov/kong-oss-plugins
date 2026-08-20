import { test, expect } from "@playwright/test";
import { callAPI, setRequestBody } from "../helpers/api";
import { KONG_ADMIN_URL } from "../helpers/kong";

test.describe("kong ready", () => {
  test("admin api reachable", async ({ request }) => {
    const payload = {};
    setRequestBody(payload);
    const {
      apiRes: {
        status,
        body: { tagline },
      },
    } = await callAPI(request, KONG_ADMIN_URL, "GET");
    expect(status).toBe(200);
    expect(tagline).toBe("Welcome to kong");
  });
});
