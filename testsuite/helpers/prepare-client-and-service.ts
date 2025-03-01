import {
  expect,
  Cookie,
  Page,
  Response,
  APIRequestContext,
} from "@playwright/test";
import { provisionNewService } from "./kong";
import { createClient } from "./keycloak";
import logger from "./logger";

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

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
    "http:///kong.localtest.me:8001",
    iteration,
    {
      name: plugin,
      overrides: pluginOverride,
    },
    clientDetails
  );

  // In Kong 3 there seems to be an async republish of routes
  // which can result in the route not being live immediately
  await sleep(2000);

  logger.debug(
    { url: `http://kong.localtest.me:8000${routePath}/headers` },
    "new service url"
  );
  return { routePath, clientDetails };
}
