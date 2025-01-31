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

interface Hooks {
  onLoginError?: (response: Response) => Promise<void>;
  onLoginSuccess?: (response: Response) => Promise<void>;
}

const defaultHooks: Hooks = {
  onLoginError: async (response: Response) => {
    const queryParams = new URL(response.request().url()).searchParams;
    console.log(queryParams);

    expect(response.status()).toBeLessThan(300);
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

  // Use the new client setup to login
  const response = await page.goto(
    `http://kong.localtest.me:8000${routePath}/headers`
  );

  if (response.status() >= 300) {
    console.log(
      response.status(),
      response.statusText(),
      response.request().url()
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

  await expect(page.locator("pre")).toBeInViewport();

  const content = await page.locator("pre").evaluate((el) => el.textContent);
  console.log(content);
  const jsonData = JSON.parse(content);

  for (const validator of validators) {
    await validator(page, jsonData);
  }
}

export const checks: any = {
  expected_headers: async (page: Page, jsonData: any) => {
    // Check for existence of upstream request headers
    expect(jsonData.headers["X-Credential-Identifier"]).toBe("local");
    expect(jsonData.headers["X-Forwarded-Host"]).toBe("kong.localtest.me");

    for (const propName of ["X-Access-Token", "X-Id-Token", "X-Userinfo"]) {
      expect(jsonData.headers).toHaveProperty(propName);
    }
  },

  expected_cookies_exist: async (page: Page, jsonData: any) => {
    const cookies = await page.context().cookies();
    console.log(cookies);

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

    //If redis, then the cookie size does not become too big
    //expect(cookies.filter((c) => c.name == "session_2").length).toBe(1);
  },

  expected_cookie_config: async (page: Page, jsonData: any) => {
    const cookies = await page.context().cookies();

    const keycloakQuarkus =
      cookies.filter((c) => c.name == "AUTH_SESSION_ID").length == 1;

    const expectedCookieValues = keycloakQuarkus
      ? {
          AUTH_SESSION_ID:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
          KC_AUTH_SESSION_HASH:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":false,"secure":false,"sameSite":"Strict"}',
          KEYCLOAK_IDENTITY:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
          KEYCLOAK_SESSION:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":false,"secure":false,"sameSite":"Lax"}',
          session:
            '{"domain":"kong.localtest.me","path":"/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
          session_2:
            '{"domain":"kong.localtest.me","path":"/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
        }
      : {
          AUTH_SESSION_ID_LEGACY:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
          KEYCLOAK_IDENTITY_LEGACY:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
          KEYCLOAK_SESSION_LEGACY:
            '{"domain":"keycloak.localtest.me","path":"/auth/realms/e2e/","httpOnly":false,"secure":false,"sameSite":"Lax"}',
          session:
            '{"domain":"kong.localtest.me","path":"/","httpOnly":true,"secure":false,"sameSite":"Lax"}',
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
      expect(expected).toBe(actual);
    }
  },
};
