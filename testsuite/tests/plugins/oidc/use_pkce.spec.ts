import { test, expect } from "@playwright/test";
import runE2Etest from "../../../helpers/e2e-test";
import { URL } from "url";

test.describe("oidc plugin - happy paths", () => {
  test("public client and use_pkce", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {
        clientAuthenticatorType: "public",
        publicClient: true,
        secret: null,
        attributes: {
          "pkce.code.challenge.method": "S256",
        },
      },
      {
        use_pkce: "yes",
        token_endpoint_auth_method: "none", // avoids client_secret being sent to TOKEN endpoint
      }
    );
  });
});

test.describe("oidc plugin - exception paths", () => {
  test("public client without use_pkce", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {
        clientAuthenticatorType: "public",
        publicClient: true,
        secret: null,
        attributes: {
          "pkce.code.challenge.method": "S256",
        },
      },
      {
        use_pkce: "false",
        token_endpoint_auth_method: "none", // avoids client_secret being sent to TOKEN endpoint
      },
      {
        onLoginError: async (response) => {
          console.log(response);
          const queryParams = new URL(response.request().url()).searchParams;
          console.log(queryParams);

          expect(queryParams.get("error_description")).toBe(
            "Missing parameter: code_challenge_method"
          );
        },
      }
    );
  });
});
