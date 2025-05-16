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
      }
    );
  });

  test("session secret", async ({ page, request }) => {
    const secret = uuidv4().replace(/-/g, "").toUpperCase().substring(0, 32);

    await runE2Etest(
      page,
      request,
      {},
      {
        session_check_addr: "yes",
        session_check_scheme: "yes",
        session_check_ssi: "yes",
        session_check_ua: "yes",
        session_secret: btoa(secret),
        session_samesite: "Strict", // Lax, Strict, None

        // secure=yes will fail in automated testing because we are not using https
        //session_secure: "yes",
      }
    );
  });

  test("samesite strict", async ({ page, request }) => {
    await runE2Etest(
      page,
      request,
      {},
      {
        session_samesite: "Strict",
      }
    );
  });
});
