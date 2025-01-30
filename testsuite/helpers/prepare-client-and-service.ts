import {
  expect,
  Cookie,
  Page,
  Response,
  APIRequestContext,
} from "@playwright/test";
import { provisionNewService } from "./kong";
import { createClient } from "./keycloak";

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
    "http:///kong.localtest.me:5501",
    iteration,
    {
      name: plugin,
      overrides: pluginOverride,
    },
    clientDetails
  );

  console.log({ url: `http://kong.localtest.me:5500${routePath}/headers` });
  return { routePath, clientDetails };
}
