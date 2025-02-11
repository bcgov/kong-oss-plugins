import { test, expect, Cookie, Page } from "@playwright/test";
import { URL } from "url";
import runE2Etest, { checks } from "../../../helpers/e2e-test";
import prepare from "../../../helpers/prepare-client-and-service";
import { clientLogin } from "../../../helpers/keycloak";
import { callAPI, setHeaders } from "../../../helpers/api";
import logger from "../../../helpers/logger";

test.describe("jwt-keycloak plugin - happy paths", () => {
  test("using defaults", async ({ page, request }) => {
    // create keycloak client and service/route w/ jwt-keycloak plugin
    const { routePath, clientDetails } = await prepare(
      request,
      {
        standardFlowEnabled: false,
        directAccessGrantsEnabled: false,
      },
      "jwt-keycloak",
      {
        allowed_iss: ["http://keycloak.localtest.me:9081/auth/realms/e2e"],
      },
      ["admin", "viewer"]
    );

    logger.debug(clientDetails, "test client details");

    // login with client to get token
    const accessToken = await clientLogin(
      clientDetails.clientId,
      clientDetails.clientSecret
    );

    // call API with token
    setHeaders({
      Authorization: "Bearer " + accessToken,
    });

    const result = await callAPI(
      request,
      `http://kong.localtest.me:8000${routePath}/headers`,
      "GET"
    );
    expect(result.apiRes.status).toBe(200);

    const upstreamRequestHeaders = result.apiRes.body.headers;

    logger.debug(upstreamRequestHeaders, "test upstream request headers");
    expect(upstreamRequestHeaders).toHaveProperty("Authorization");
  });
});
