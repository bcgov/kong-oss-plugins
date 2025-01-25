import { test, expect } from "@playwright/test";
import { URL } from "url";
import runE2Etest from "../../../helpers/e2e-test";
import { v4 as uuidv4 } from "uuid";

test.describe("oidc plugin - happy paths", () => {
  test("sessions", async ({ page, request }) => {
    const secret = uuidv4().replace(/-/g, "").toUpperCase().substring(0, 12);

    await runE2Etest(
      page,
      request,
      {},
      {
        session_check_addr: "yes",
        session_check_scheme: "yes",
        session_check_ssi: "yes",
        session_check_ua: "yes",
        //session_samesite: "Strict", // Lax, Strict, None
        //session_secret: btoa(secret),
        // oidc/session.lua:10: variable "session_secret" not found for writing;
        // maybe it is a built-in variable that is not changeable or you forgot
        // to use "set $session_secret ''

        //session_secure: "yes",
        // request to the redirect_uri path but there's no session state found
      }
    );
  });
});
