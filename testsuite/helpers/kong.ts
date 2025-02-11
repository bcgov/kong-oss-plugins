import { APIRequestContext } from "playwright";
import logger from "./logger";

const base_service = {
  id: "00000000-0000-0000-0000-00000000000",
  name: "NAME",
  host: "httpbin.org",
  port: 443,
  protocol: "https",
};

const base_route = {
  id: "00000000-0000-0000-0000-00000000000",
  name: "NAME",
  hosts: ["kong.localtest.me"],
  paths: ["/001"],
  strip_path: true,
  methods: ["GET"],
  service: {
    id: "",
  },
};

type KongProvisionResponse = {
  status: number;
  body: any;
};

export async function provisionNewService(
  request: APIRequestContext,
  baseURL: string,
  id: number,
  plugin: { name: string; overrides: {} },
  clientDetails: { clientId: string; clientSecret: string }
): Promise<string> {
  const unqId = id.toString().padStart(8, "0");
  const newId = id.toString().padStart(8, "0");

  const service = {
    ...base_service,
    ...{
      id: `${unqId}-0000-0000-0000-0000${newId}`,
      name: `svc-${unqId}-${newId}`,
    },
  };
  const route = {
    ...base_route,
    ...{
      id: `${unqId}-0000-0000-0000-0000${newId}`,
      // Kong 3 -- paths: [`~/${newId}/.*`],
      paths: [`/${newId}`],
      name: `svc-${unqId}-${newId}-route`,
      service: { id: service.id },
    },
  };
  const pluginConfig = {
    ...{ name: plugin.name, config: plugin.overrides },
    ...{ route: { id: route.id } },
  };

  if (plugin.name == "oidc") {
    pluginConfig.config["client_id"] = clientDetails.clientId;
    if (clientDetails.clientSecret === null) {
      pluginConfig.config["client_secret"] = "XX"; // can not be null or empty
    } else {
      pluginConfig.config["client_secret"] = clientDetails.clientSecret;
    }
    pluginConfig.config["redirect_uri"] = `/${newId}/cb`;
  } else if (plugin.name == "jwt-keycloak") {
    // pluginConfig.config["allowed_aud"] = clientDetails.clientId;
  }

  await provisionKong(request, `${baseURL}/services`, service);
  await provisionKong(request, `${baseURL}/routes`, route);
  await provisionKong(request, `${baseURL}/plugins`, pluginConfig);

  return `/${newId}`;
}

export async function provisionKong(
  request: APIRequestContext,
  endpoint: string,
  payload: any
) {
  const options: any = {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    data: JSON.stringify(payload),
  };

  const response = await request.fetch(endpoint, options);

  let responseBody: any;
  try {
    responseBody = await response.json();
  } catch (e) {
    logger.debug(e, "Error parsing json response");
    responseBody = null;
  }

  if (response.status() >= 300) {
    const errors = await response.text();
    logger.error(errors, "failed to provision kong");
    throw new Error("failed to provision kong");
  }

  return {
    status: response.status(),
    body: responseBody,
  } as KongProvisionResponse;
}
