import { readFileSync } from "fs";
import { v4 as uuidv4 } from "uuid";
import { callAPI, setRequestBody, setHeaders } from "./api";
import { APIRequestContext } from "playwright";
import { expect } from "@playwright/test";
import { mergeDeep } from "./deep-merge";
import logger from "./logger";

export async function adminLogin() {
  const result = await fetch(
    "http://keycloak.localtest.me:9081/auth/realms/master/protocol/openid-connect/token",
    {
      method: "POST",
      body: "grant_type=password&client_id=admin-cli&username=local&password=local",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
    }
  ).then((response) => response.json());
  return result.access_token;
}

export async function clientLogin(clientId: string, clientSecret: string) {
  const result = await fetch(
    "http://keycloak.localtest.me:9081/auth/realms/e2e/protocol/openid-connect/token",
    {
      method: "POST",
      body: `scope=openid&grant_type=client_credentials&client_id=${clientId}&client_secret=${clientSecret}`,
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
    }
  ).then((response) => response.json());
  return result.access_token;
}

export async function createClient(
  request: APIRequestContext,
  overrides = {},
  roles: string[] = []
) {
  const adminToken = await adminLogin();

  const payload = JSON.parse(
    readFileSync("./local/keycloak/client.json", "utf8")
  );

  const uuid = uuidv4();
  const uid = uuid.replace(/-/g, "").toUpperCase().substring(0, 5);

  payload.clientId = "test-client-" + uid;
  payload.id = uuid;

  const requestBody = mergeDeep(payload, overrides, {
    description: JSON.stringify(overrides, null, 2),
  });
  setRequestBody(requestBody);
  setHeaders({
    Authorization: "Bearer " + adminToken,
  });

  const {
    apiRes: { status, headers, body },
  } = await callAPI(
    request,
    `http:///keycloak.localtest.me:9081/auth/admin/realms/e2e/clients`,
    "POST"
  );
  expect(status).toBe(201);

  // create a role if provided
  for (const role of roles) {
    setRequestBody({ name: role, description: "", attributes: {} });
    setHeaders({
      Authorization: "Bearer " + adminToken,
    });

    const {
      apiRes: { status: statusForRole },
    } = await callAPI(
      request,
      `http:///keycloak.localtest.me:9081/auth/admin/realms/e2e/clients/${payload.id}/roles`,
      "POST"
    );
    expect(statusForRole).toBe(201);
  }

  logger.debug(headers["location"], "location header");
  return { clientId: payload.clientId, clientSecret: payload.secret };
}
