import { test, expect } from "@playwright/test";
import runE2Etest from "../../../helpers/e2e-test";
import { URL } from "url";

test.describe("oidc plugin - happy paths", () => {
  test("public client and use_nonce", async ({ page, request }) => {
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
        use_nonce: "yes",
        token_endpoint_auth_method: "none", // avoids client_secret being sent to TOKEN endpoint
      },
      {
        onLoginSuccess: async (response) => {
          const queryParams = new URL(response.request().url()).searchParams;
          console.log(queryParams);
          expect(queryParams.get("nonce")).not.toBeNull();
          expect(queryParams.get("code_challenge")).not.toBeNull();
          expect(queryParams.get("code_challenge_method")).toBe("S256");
        },
      }
    );
  });
});
