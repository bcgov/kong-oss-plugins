import {
  expect,
  Cookie,
  Page,
  Response,
  APIRequestContext,
} from "@playwright/test";
import { provisionNewService, KONG_ADMIN_URL, KONG_PROXY_URL } from "./kong";
import { createClient } from "./keycloak";
import logger from "./logger";

export default async function prepare(
  request: APIRequestContext,
  clientOverrides: any,
  plugin: string,
  pluginOverride: any,
  roles: string[] = []
) {
  // Create a new client on Keycloak (using default local/keycloak/client.json)
  const clientDetails = await createClient(request, clientOverrides, roles);

  // Provision a new service/route on Kong
  const iteration = Math.round(Math.random() * 100000000);
  const routePath = await provisionNewService(
    request,
    KONG_ADMIN_URL,
    iteration,
    {
      name: plugin,
      overrides: pluginOverride,
    },
    clientDetails
  );

  logger.debug(
    { url: `${KONG_PROXY_URL}${routePath}/headers` },
    "new service url"
  );
  return { routePath, clientDetails };
}
