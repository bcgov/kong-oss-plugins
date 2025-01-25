import { readFileSync } from "fs";
import { v4 as uuidv4 } from "uuid";
import { callAPI, setRequestBody, setHeaders } from "./api";
import { APIRequestContext } from "playwright";
import { expect } from "@playwright/test";
import { mergeDeep } from "./deep-merge";

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

export async function createClient(request: APIRequestContext, overrides = {}) {
  const bearerToken = await adminLogin();

  const payload = JSON.parse(
    readFileSync("./local/keycloak/client.json", "utf8")
  );

  const uid = uuidv4().replace(/-/g, "").toUpperCase().substring(0, 5);

  payload.clientId = "test-client-" + uid;

  const requestBody = mergeDeep(payload, overrides, {
    description: JSON.stringify(overrides, null, 2),
  });
  setRequestBody(requestBody);
  setHeaders({
    Authorization: "Bearer " + bearerToken,
  });

  const {
    apiRes: { status, headers },
  } = await callAPI(
    request,
    `http:///keycloak.localtest.me:9081/auth/admin/realms/e2e/clients`,
    "POST"
  );
  expect(status).toBe(201);
  console.log(headers["location"]);
  return { clientId: payload.clientId, clientSecret: payload.secret };
}
