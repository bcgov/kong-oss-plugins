import { test, expect } from "@playwright/test";
import { callAPI, setRequestBody, setHeaders } from "../helpers/api";
import { provisionKong } from "../helpers/kong";
import { readFileSync } from "fs";
import { parse, stringify } from "yaml";
import { v4 as uuidv4 } from "uuid";

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

  test("simple service", async ({ page, request }) => {
    const uid = uuidv4().replace(/-/g, "").toUpperCase().substring(0, 5);

    // parse yaml
    const path = require("path");
    //const data = require(path.resolve(__dirname, "../local/data/kong.yaml"));
    const data = readFileSync("./local/data/kong.yaml", "utf8");

    const kongdata = parse(data);

    kongdata.services[0].name = `service-${uid}`;

    const res = await provisionKong(
      request,
      "http:///kong.localtest.me:5501/services",
      kongdata.services[0]
    );
    console.log(`The page title is: ${JSON.stringify(res.body)}`);

    expect(res.status).toBe(201);
  });

  test("admin api in browser", async ({ page, request }) => {
    await page.goto("http:///kong.localtest.me:8001");

    // Expect a title "to contain" a substring.
    //await expect(page).toHaveTitle(/Playwright/);
  });
});
