import { test, expect } from "@playwright/test";
import { callAPI, setRequestBody } from "../helpers/api";

test.describe("kong ready", () => {
  test("admin api reachable", async ({ request }) => {
    const payload = {};
    setRequestBody(payload);
    const {
      apiRes: {
        status,
        body: { tagline },
      },
    } = await callAPI(request, `http:///kong.localtest.me:8001`, "GET");
    expect(status).toBe(200);
    expect(tagline).toBe("Welcome to kong");
  });
});
