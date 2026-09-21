import { APIRequestContext } from "@playwright/test";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  KONG_ADMIN_URL,
  KONG_PROXY_URL,
  proxyGet,
  provisionKong,
  waitForRouteReady,
} from "./kong";
import { upstreamServiceDefaults } from "./upstream";

export const TOKEN_EXCHANGE_MOCK_CAPTURE_URL =
  process.env.TOKEN_EXCHANGE_MOCK_CAPTURE_URL ?? "http://127.0.0.1:18080";
export const TOKEN_EXCHANGE_MOCK_TOKEN_URL =
  process.env.TOKEN_EXCHANGE_MOCK_TOKEN_URL ??
  "http://token-exchange-mock:8080/token";

export const KEY_PATHS = {
  rsa2048: "/tmp/kong/fixtures/keys/rsa-2048.pem",
  ecP256: "/tmp/kong/fixtures/keys/ec-p256.pem",
  ecP384: "/tmp/kong/fixtures/keys/ec-p384.pem",
  ecP521: "/tmp/kong/fixtures/keys/ec-p521.pem",
  malformed: "/tmp/kong/fixtures/keys/README.md",
  unreadable: "/tmp/kong/fixtures/keys/does-not-exist.pem",
} as const;

export const PUBLIC_KEY_FILES = {
  rsa2048: path.resolve(__dirname, "../local/kong/fixtures/keys/rsa-2048.pub.pem"),
  ecP256: path.resolve(__dirname, "../local/kong/fixtures/keys/ec-p256.pub.pem"),
  ecP384: path.resolve(__dirname, "../local/kong/fixtures/keys/ec-p384.pub.pem"),
  ecP521: path.resolve(__dirname, "../local/kong/fixtures/keys/ec-p521.pub.pem"),
} as const;

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

export type TokenEndpointCapture = {
  id: number;
  method: string;
  path: string;
  headers: Record<string, string>;
  form: Record<string, string>;
  receivedAt: number;
};

export type DecodedAssertion = {
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
  signingInput: Buffer;
  signature: Buffer;
};

let entityCounter = 0;

export function tokenEndpoint(
  mode: string,
  params: Record<string, string | number> = {}
): string {
  const url = new URL(`${TOKEN_EXCHANGE_MOCK_TOKEN_URL}/${mode}`);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, String(value));
  }
  return url.toString();
}

export function selfSignedTokenEndpoint(): string {
  return "https://token-exchange-mock:8443/token/success";
}

export function proxyPluginGet(
  request: APIRequestContext,
  proxyUrl: string,
  headers?: Record<string, string>
) {
  return proxyGet(request, new URL(proxyUrl).pathname, { headers });
}

export function decodeClientAssertion(assertion: string): DecodedAssertion {
  const segments = assertion.split(".");
  if (segments.length !== 3) {
    throw new Error(`expected compact JWS with three segments, got ${segments.length}`);
  }

  return {
    header: JSON.parse(Buffer.from(segments[0], "base64url").toString("utf8")),
    payload: JSON.parse(Buffer.from(segments[1], "base64url").toString("utf8")),
    signingInput: Buffer.from(`${segments[0]}.${segments[1]}`),
    signature: Buffer.from(segments[2], "base64url"),
  };
}

export function verifyClientAssertion(
  assertion: string,
  publicKeyFile: string,
  digest: "sha256" | "sha384" | "sha512",
  ellipticCurve = false
): boolean {
  const decoded = decodeClientAssertion(assertion);
  const key = fs.readFileSync(publicKeyFile, "utf8");
  return crypto.verify(
    digest,
    decoded.signingInput,
    ellipticCurve ? { key, dsaEncoding: "ieee-p1363" } : key,
    decoded.signature
  );
}

export async function provisionPluginRoute(
  request: APIRequestContext,
  options: ProvisionOptions
) {
  const suffix = ++entityCounter;
  const serviceName = `${options.prefix}-svc-${suffix}`;
  const routeName = `${options.prefix}-rt-${suffix}`;
  const routePath = `/${options.prefix}-${suffix}`;

  const service = await provisionKong(request, `${KONG_ADMIN_URL}/services`, {
    name: serviceName,
    ...upstreamServiceDefaults,
    ...(options.serviceTags ? { tags: options.serviceTags } : {}),
  });
  const serviceId = service.body.id as string;

  const route = await provisionKong(request, `${KONG_ADMIN_URL}/routes`, {
    name: routeName,
    service: { id: serviceId },
    hosts: ["kong.localtest.me"],
    paths: [routePath],
    strip_path: true,
  });
  const routeId = route.body.id as string;

  const plugin = await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
    name: "token-exchange",
    route: { id: routeId },
    config: options.config,
  });

  await waitForRouteReady(request, routePath, { stableMs: 1_000 });

  return {
    routePath,
    proxyUrl: `${KONG_PROXY_URL}${routePath}`,
    serviceId,
    routeId,
    pluginId: plugin.body.id as string,
  };
}

async function listEntities(request: APIRequestContext, collection: "routes" | "services") {
  const entities: Array<{ id: string; name?: string }> = [];
  let next: string | null = `${KONG_ADMIN_URL}/${collection}?size=1000`;

  while (next) {
    const response = await request.get(next);
    if (!response.ok()) {
      throw new Error(`failed to list Kong ${collection}: ${response.status()}`);
    }
    const body = await response.json();
    entities.push(...body.data);
    next = body.next
      ? body.next.startsWith("http")
        ? body.next
        : `${KONG_ADMIN_URL}${body.next}`
      : null;
  }

  return entities;
}

export async function cleanupByPrefix(
  request: APIRequestContext,
  prefix: string
): Promise<void> {
  const routes = await listEntities(request, "routes");
  for (const route of routes.filter((item) => item.name?.startsWith(prefix))) {
    const response = await request.delete(`${KONG_ADMIN_URL}/routes/${route.id}`);
    if (!response.ok() && response.status() !== 404) {
      throw new Error(`failed to delete route ${route.id}: ${response.status()}`);
    }
  }

  const services = await listEntities(request, "services");
  for (const service of services.filter((item) => item.name?.startsWith(prefix))) {
    const response = await request.delete(`${KONG_ADMIN_URL}/services/${service.id}`);
    if (!response.ok() && response.status() !== 404) {
      throw new Error(`failed to delete service ${service.id}: ${response.status()}`);
    }
  }
}

export async function resetTokenEndpointCaptures(
  request: APIRequestContext
): Promise<void> {
  const response = await request.delete(`${TOKEN_EXCHANGE_MOCK_CAPTURE_URL}/captures`);
  if (!response.ok()) {
    throw new Error(`failed to reset token endpoint captures: ${response.status()}`);
  }
}

export async function capturesForClient(
  request: APIRequestContext,
  clientId: string
): Promise<TokenEndpointCapture[]> {
  const response = await request.get(
    `${TOKEN_EXCHANGE_MOCK_CAPTURE_URL}/captures/${encodeURIComponent(clientId)}`
  );
  if (!response.ok()) {
    throw new Error(`failed to read token endpoint captures: ${response.status()}`);
  }
  return (await response.json()).captures;
}
