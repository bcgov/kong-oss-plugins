import {
  expect,
  Cookie,
  Page,
  Response,
  APIRequestContext,
} from "@playwright/test";
import { provisionNewService } from "./kong";
import { createClient } from "./keycloak";

interface Hooks {
  onLoginError?: (response: Response) => Promise<void>;
  onLoginSuccess?: (response: Response) => Promise<void>;
  onContent?: (jsonData: any, cookie: Cookie[]) => Promise<void>;
}

const defaultHooks: Hooks = {
  onLoginError: async (response: Response) => {
    const queryParams = new URL(response.request().url()).searchParams;
    console.log(queryParams);

    expect(response.status()).toBeLessThan(300);
  },
  onLoginSuccess: async (response: Response) => {},
  onContent: async (jsonData: any, cookies: Cookie[]) => {},
};

export default async function runE2Etest(
  page: Page,
  request: APIRequestContext,
  clientOverrides: any,
  pluginOverride: any,
  hooks: Hooks = defaultHooks
) {
  // Create a new client on Keycloak (using default local/keycloak/client.json)
  const clientDetails = await createClient(request, clientOverrides);

  // Provision a new service/route on Kong
  const iteration = Math.round(Math.random() * 100000000);
  const newRoutePath = await provisionNewService(
    request,
    "http:///kong.localtest.me:5501",
    iteration,
    {
      name: "oidc",
      overrides: {
        ...{
          discovery:
            "http://keycloak.localtest.me:9081/auth/realms/e2e/.well-known/openid-configuration",
        },
        ...pluginOverride,
      },
    },
    clientDetails
  );

  console.log({ url: `http://kong.localtest.me:5500${newRoutePath}/headers` });

  // Use the new client setup to login
  const response = await page.goto(
    `http://kong.localtest.me:5500${newRoutePath}/headers`
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
  await page.locator("button[type=submit]").click();

  await expect(page.locator("pre")).toBeInViewport();

  const content = await page.locator("pre").evaluate((el) => el.textContent);

  const jsonData = JSON.parse(content);

  // Check for existence of upstream request headers
  expect(jsonData.headers["X-Credential-Identifier"]).toBe("local");
  expect(jsonData.headers["X-Forwarded-Host"]).toBe("kong.localtest.me");

  for (const propName of ["X-Access-Token", "X-Id-Token", "X-Userinfo"]) {
    expect(jsonData.headers).toHaveProperty(propName);
  }

  // Check for existence of cookies
  const cookies = await page.context().cookies();
  for (const propName of ["X-Access-Token", "X-Id-Token", "X-Userinfo"]) {
    expect(jsonData.headers).toHaveProperty(propName);
  }

  expect(cookies.filter((c) => c.name == "AUTH_SESSION_ID").length).toBe(1);
  expect(cookies.filter((c) => c.name == "KC_AUTH_SESSION_HASH").length).toBe(
    1
  );
  expect(cookies.filter((c) => c.name == "KEYCLOAK_IDENTITY").length).toBe(1);
  expect(cookies.filter((c) => c.name == "KEYCLOAK_SESSION").length).toBe(1);
  expect(cookies.filter((c) => c.name == "session").length).toBe(1);
  expect(cookies.filter((c) => c.name == "session_2").length).toBe(1);

  expect(cookies.length).toBe(6);

  const expectedCookieValues = {
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

  await (hooks.onContent ? hooks.onContent : defaultHooks.onContent)(
    jsonData,
    cookies
  );
}
