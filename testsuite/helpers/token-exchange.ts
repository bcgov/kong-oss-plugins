import { APIRequestContext } from "playwright";
import {
  KONG_ADMIN_URL,
  provisionKong,
  waitForRouteReady,
} from "./kong";
import { upstreamServiceDefaults } from "./upstream";

export type TokenExchangeConfig = {
  private_key_location: string;
  client_id: string;
  token_endpoint: string;
  algorithm?: "RS256" | "RS384" | "RS512" | "ES256" | "ES384" | "ES512";
  expiration?: number;
  key_id?: string;
  scopes?: string[];
  audience?: string;
  timeout?: number;
};

type ProvisionOptions = {
  prefix: string;
  config: TokenExchangeConfig;
  serviceTags?: string[];
};

export type CapturedExchange = {
  method: string;
  headers: Record<string, string>;
  rawBody: string;
  form: Record<string, string>;
};

const MOCK_CAPTURE_URL =
  process.env.TOKEN_EXCHANGE_MOCK_CAPTURE_URL ?? "http://127.0.0.1:18080";
const MOCK_TOKEN_URL =
  process.env.TOKEN_EXCHANGE_MOCK_TOKEN_URL ?? "http://token-exchange-mock:8080/token";

let entityCounter = 0;

export async function provisionPluginRoute(
  request: APIRequestContext,
  { prefix, config, serviceTags }: ProvisionOptions
) {
  const number = ++entityCounter;
  const suffix = String(number).padStart(4, "0");
  const serviceName = `${prefix}-svc-${suffix}`;
  const routeName = `${prefix}-rt-${suffix}`;
  const routePath = `/${prefix}-${suffix}`;

  const service = await provisionKong(request, `${KONG_ADMIN_URL}/services`, {
    name: serviceName,
    ...upstreamServiceDefaults,
    ...(serviceTags ? { tags: serviceTags } : {}),
  });
  const route = await provisionKong(request, `${KONG_ADMIN_URL}/routes`, {
    name: routeName,
    service: { id: service.body.id },
    hosts: ["kong.localtest.me"],
    paths: [routePath],
    strip_path: true,
  });
  const plugin = await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
    name: "token-exchange",
    route: { id: route.body.id },
    config,
  });

  await waitForRouteReady(request, routePath, {
    timeoutMs: 30_000,
    consecutive: 9,
  });
  return {
    routePath,
    serviceId: service.body.id as string,
    routeId: route.body.id as string,
    pluginId: plugin.body.id as string,
  };
}

async function listAll(request: APIRequestContext, initialUrl: string) {
  const entities: Array<{ id: string; name?: string }> = [];
  let next: string | null = initialUrl;
  while (next) {
    const response = await request.get(next);
    if (!response.ok()) {
      throw new Error(`failed to list Kong entities: ${response.status()} ${await response.text()}`);
    }
    const page = await response.json();
    entities.push(...page.data);
    next = page.next
      ? page.next.startsWith("http")
        ? page.next
        : `${KONG_ADMIN_URL}${page.next}`
      : null;
  }
  return entities;
}

export async function cleanupByPrefix(request: APIRequestContext, prefix: string) {
  const routes = await listAll(request, `${KONG_ADMIN_URL}/routes?size=1000`);
  for (const route of routes.filter((item) => item.name?.startsWith(prefix))) {
    const response = await request.delete(`${KONG_ADMIN_URL}/routes/${route.id}`);
    if (!response.ok() && response.status() !== 404) {
      throw new Error(`failed to delete route ${route.id}: ${response.status()}`);
    }
  }

  const services = await listAll(request, `${KONG_ADMIN_URL}/services?size=1000`);
  for (const service of services.filter((item) => item.name?.startsWith(prefix))) {
    const response = await request.delete(`${KONG_ADMIN_URL}/services/${service.id}`);
    if (!response.ok() && response.status() !== 404) {
      throw new Error(`failed to delete service ${service.id}: ${response.status()}`);
    }
  }
}

export function mockTokenEndpoint(
  capture: string,
  options?: { mode?: string; accessToken?: string }
) {
  const url = new URL(MOCK_TOKEN_URL);
  url.searchParams.set("capture", capture);
  if (options?.mode) url.searchParams.set("mode", options.mode);
  if (options?.accessToken) url.searchParams.set("access_token", options.accessToken);
  return url.toString();
}

export async function clearMockCaptures(request: APIRequestContext) {
  const response = await request.delete(`${MOCK_CAPTURE_URL}/captures`);
  if (!response.ok()) {
    throw new Error(`failed to clear token endpoint captures: ${response.status()}`);
  }
}

export async function getMockCapture(
  request: APIRequestContext,
  capture: string
): Promise<CapturedExchange | undefined> {
  const response = await request.get(
    `${MOCK_CAPTURE_URL}/captures/${encodeURIComponent(capture)}`
  );
  if (response.status() === 404) return undefined;
  if (!response.ok()) {
    throw new Error(`failed to read token endpoint capture: ${response.status()}`);
  }
  return response.json();
}
