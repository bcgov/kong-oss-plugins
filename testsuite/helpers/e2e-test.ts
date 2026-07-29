import {
  expect,
  Cookie,
  Page,
  Response,
  APIRequestContext,
} from "@playwright/test";
import { provisionNewService } from "./kong";
import { createClient } from "./keycloak";
import prepare from "./prepare-client-and-service";
import logger from "./logger";

interface Hooks {
  onLoginError?: (response: Response) => Promise<void>;
  onLoginSuccess?: (response: Response) => Promise<void>;
}

const defaultHooks: Hooks = {
  onLoginError: async (response: Response) => {
    const queryParams = new URL(response.request().url()).searchParams;
    logger.debug(queryParams, "Login Error");

    expect(response.status(), "Login Error").toBeLessThan(300);
  },
  onLoginSuccess: async (response: Response) => {},
};

export default async function runE2Etest(
  page: Page,
  request: APIRequestContext,
  clientOverrides: any,
  pluginOverride: any,
  validators: Function[] = Object.values(checks),
  hooks: Hooks = defaultHooks
) {
  const { routePath } = await prepare(request, clientOverrides, "oidc", {
    ...{
      discovery:
        "http://keycloak.localtest.me:9081/auth/realms/e2e/.well-known/openid-configuration",
    },
    ...pluginOverride,
  });

  await page.context().clearCookies();

  // Use the new client setup to login
  async function do_page(retries: number = 0): Promise<null | Response> {
    const response = await page.goto(
      `http://kong.localtest.me:8000${routePath}/headers`
    );

    if (response.status() == 404 && retries < 20) {
      console.warn("Retry attempt", retries + 1);
      await page.waitForTimeout(500);
      return do_page(retries + 1);
    }

    // if we are waiting for kong to propagate the new service, we need to wait longer
    if (retries > 5) {
      await page.waitForTimeout(5000);
    }
    return response;
  }

  const response = await do_page();

  if (response.status() >= 300) {
    logger.debug(
      {
        status: response.status(),
        statusText: response.statusText(),
        url: response.request().url(),
      },
      "error status"
    );

    await (hooks.onLoginError ? hooks.onLoginError : defaultHooks.onLoginError)(
      response
    );
    return;
  }

  await (hooks.onLoginSuccess
    ? hooks.onLoginSuccess
    : defaultHooks.onLoginSuccess)(response);

  await expect(page).toHaveTitle(/Sign in/);

  await page.locator("input[name=username]").fill("local");
  await page.locator("input[name=password]").fill("local");
  await page.locator("[type=submit]").click();

  await expect(page.locator("pre")).toBeInViewport({ timeout: 20000 });

  const content = await page.locator("pre").evaluate((el) => el.textContent);
  logger.debug(content, "pre content from upstream");
  const jsonData = JSON.parse(content);

  for (const validator of validators) {
    await validator(pluginOverride, routePath, page, jsonData);
  }
}

export const checks: any = {
  expected_headers: async (pluginOverrides: any, routePath: string, page: Page, jsonData: any) => {
    // Check for existence of upstream request headers
    expect(jsonData.headers["X-Credential-Identifier"]).toBe("local");
    expect(jsonData.headers["X-Forwarded-Host"]).toBe("kong.localtest.me");

    for (const propName of ["X-Access-Token", "X-Id-Token", "X-Userinfo"]) {
      expect(jsonData.headers).toHaveProperty(propName);
    }
  },

  expected_cookies_exist: async (
    pluginOverrides: any,
    routePath: string,
    page: Page,
    jsonData: any
  ) => {
    const cookies = await page.context().cookies();
    logger.debug(cookies, "page cookies");

    const keycloakQuarkus =
      cookies.filter((c) => c.name == "AUTH_SESSION_ID").length == 1;

    if (keycloakQuarkus) {
      expect(cookies.filter((c) => c.name == "AUTH_SESSION_ID").length).toBe(1);
      expect(
        cookies.filter((c) => c.name == "KC_AUTH_SESSION_HASH").length
      ).toBe(1);
      expect(cookies.filter((c) => c.name == "KEYCLOAK_IDENTITY").length).toBe(
        1
      );
      expect(cookies.filter((c) => c.name == "KEYCLOAK_SESSION").length).toBe(
        1
      );
      expect(cookies.filter((c) => c.name == "session").length).toBe(1);
      expect(cookies.length).toBe(5);
    } else {
      expect(
        cookies.filter((c) => c.name == "AUTH_SESSION_ID_LEGACY").length
      ).toBe(1);
      expect(
        cookies.filter((c) => c.name == "KEYCLOAK_IDENTITY_LEGACY").length
      ).toBe(1);
      expect(
        cookies.filter((c) => c.name == "KEYCLOAK_SESSION_LEGACY").length
      ).toBe(1);
      expect(cookies.filter((c) => c.name == "session").length).toBe(1);

      expect(cookies.length).toBe(4);
    }

    // Using redis storage, so cookie size should be small
    expect(cookies.filter((c) => c.name == "session").length).toBeLessThan(80);
  },

  expected_cookie_config: async (
    pluginOverrides: any,
    routePath: string,
    page: Page,
    jsonData: any
  ) => {
    const cookies = await page.context().cookies();

    const keycloakQuarkus =
      cookies.filter((c) => c.name == "AUTH_SESSION_ID").length == 1;

    const sameSite = pluginOverrides.session_samesite || "Lax";

    const cookiePath = "/"; // could be routePath - see kong.ts
    const expectedCookieValues = keycloakQuarkus
      ? {
          AUTH_SESSION_ID:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
          KC_AUTH_SESSION_HASH:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":false,"secure":false,"sameSite":"Lax"}',
          KEYCLOAK_IDENTITY:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
          KEYCLOAK_SESSION:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":false,"secure":false,"sameSite":"Lax"}',
          // Redis-backed session: single "session" cookie; SameSite follows plugin config
          session:
            '{"domain":"kong.localtest.me","path":"' +
            cookiePath +
            '","httpOnly":true,"secure":false,"sameSite":"' +
            sameSite +
            '"}',
        }
      : {
          AUTH_SESSION_ID_LEGACY:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
          KEYCLOAK_IDENTITY_LEGACY:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
          KEYCLOAK_SESSION_LEGACY:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":false,"secure":false,"sameSite":"Lax"}',
          session:
            '{"domain":"kong.localtest.me","path":"' +
            cookiePath +
            '","httpOnly":true,"secure":false,"sameSite":"' +
            sameSite +
            '"}',
        };

    for (const cookie of cookies) {
      const expected = expectedCookieValues[cookie.name];
      const actual = JSON.stringify(
        (({ domain, path, httpOnly, secure, sameSite }) => ({
          domain,
          path,
          httpOnly,
          secure,
          sameSite,
        }))(cookie)
      );
      expect(actual).toBe(expected);
    }
  },
};
