import { test, expect } from "@playwright/test";
import { callAPI, setRequestBody } from "../../../helpers/api";
import logger from "../../../helpers/logger";
import { provisionNewService } from "../../../helpers/kong";

test.describe("response-signer plugin - happy paths", () => {
  test("using defaults", async ({ page, request }) => {
    const iteration = Math.round(Math.random() * 100000000);
    const routePath = await provisionNewService(
      request,
      "http://kong.localtest.me:8001",
      iteration,
      {
        name: "response-signer",
        overrides: {
          private_key_location: "/tmp/kong/cluster.key",
          public_key_location: "/tmp/kong/cluster.crt",
        },
      },
      { clientId: null, clientSecret: null }
    );

    logger.debug(
      { url: `http://kong.localtest.me:8000${routePath}/headers` },
      "new service url"
    );

    setRequestBody({
      vehicle: "V5AR4T",
      info: { year: "2021", make: "Toyota" },
    });

    const result = await callAPI(
      request,
      `http://kong.localtest.me:8000${routePath}/anything`,
      "POST"
    );
    expect(result.apiRes.status).toBe(200);
  });
});
