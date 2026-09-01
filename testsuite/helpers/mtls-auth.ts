import * as crypto from "crypto";
import { APIRequestContext } from "playwright";
import {
  KONG_ADMIN_URL,
  provisionKong,
  waitForRouteReady,
  uniquePrefix,
  mtlsClientCert,
  mtlsProxyGet,
  mtlsProxyRequest,
  disposeMtlsContexts,
} from "./kong";
import { upstreamServiceDefaults } from "./upstream";

export {
  uniquePrefix,
  mtlsClientCert,
  mtlsProxyGet,
  mtlsProxyRequest,
  disposeMtlsContexts,
};

/**
 * Subject DNs of the mTLS client-cert fixtures exactly as nginx renders
 * `$ssl_client_s_dn` (RFC 2253) — from the fixture inventory in
 * `testsuite/local/kong/fixtures/keys/mtls/README.md`.
 */
export const MTLS_SUBJECT_DN: Record<string, string> = {
  alice: "CN=Alice Example,O=Example Org,C=US",
  "comma-cn": "CN=Smith\\, Jr.,O=Example Org,C=US",
  "utf8-cn": "CN=Caf\\C3\\A9,O=Example Org,C=US",
  "dup-cn": "CN=Second,OU=Sales,CN=First",
  "no-cn": "O=Example Org,C=US",
  "no-org": "CN=NoOrg Example,C=US",
  untrusted: "CN=Mallory Example,O=Mallory Org,C=US",
};

/** Issuer DN (verbatim, RFC 2253) of every leaf signed by the trusted client CA. */
export const MTLS_ISSUER_DN = "CN=Kong e2e Client CA,O=Kong e2e Test,C=US";

export type CertExpectations = {
  /** Certificate PEM exactly as stored in the fixture file. */
  pem: string;
  /** SHA-1 of the DER certificate, lowercase hex, no separators (40 chars). */
  fingerprintSha1Hex: string;
  /** Serial number, uppercase hex, no separators (openssl `serial=` form). */
  serialHex: string;
  /** Serial number in decimal — what the serial header must NOT be. */
  serialDecimal: string;
  /** nginx `$ssl_client_s_dn` rendering (undefined for fixtures not in the table). */
  subjectDn?: string;
  /** nginx `$ssl_client_i_dn` rendering for client-ca-signed leaves. */
  issuerDn: string;
};

/**
 * Expected certificate-derived values for a fixture cert, computed from the
 * fixture files (never hardcoded fingerprints/serials).
 */
export function certExpectations(name: string): CertExpectations {
  const cert = mtlsClientCert(name);
  const serialHex = cert.x509.serialNumber.toUpperCase();
  return {
    pem: cert.pem,
    fingerprintSha1Hex: crypto
      .createHash("sha1")
      .update(cert.x509.raw)
      .digest("hex"),
    serialHex,
    serialDecimal: BigInt(`0x${serialHex}`).toString(10),
    subjectDn: MTLS_SUBJECT_DN[name],
    issuerDn: MTLS_ISSUER_DN,
  };
}

/**
 * Case-insensitive lookup in an httpbun `/headers` echo object (httpbun
 * canonicalizes header names). Returns undefined when absent.
 */
export function echoedHeader(
  headers: Record<string, unknown>,
  name: string
): string | undefined {
  const wanted = name.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === wanted) {
      return String(value);
    }
  }
  return undefined;
}

export type ExtraPlugin = {
  name: string;
  config: Record<string, unknown>;
};

export type ProvisionPluginRouteOptions = {
  prefix: string;
  /** mtls-auth config — fields per the spec's Configuration schema requirement. */
  config: Record<string, unknown>;
  serviceTags?: string[];
  /**
   * Additional route-scoped plugins (e.g. a post-function observer for the
   * shared-context scenarios), provisioned after mtls-auth.
   */
  extraPlugins?: ExtraPlugin[];
};

let entityCounter = 0;

export async function provisionPluginRoute(
  request: APIRequestContext,
  options: ProvisionPluginRouteOptions
): Promise<{
  routePath: string;
  serviceId: string;
  routeId: string;
  pluginId: string;
}> {
  const n = ++entityCounter;
  const { prefix, config, serviceTags, extraPlugins } = options;

  const service = await provisionKong(request, `${KONG_ADMIN_URL}/services`, {
    name: `${prefix}-svc-${n}`,
    ...upstreamServiceDefaults,
    ...(serviceTags ? { tags: serviceTags } : {}),
  });
  const serviceId = service.body.id as string;

  const routePath = `/${prefix}-${n}`;
  const route = await provisionKong(request, `${KONG_ADMIN_URL}/routes`, {
    name: `${prefix}-rt-${n}`,
    hosts: ["kong.localtest.me"],
    paths: [routePath],
    strip_path: true,
    service: { id: serviceId },
  });
  const routeId = route.body.id as string;

  const plugin = await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
    name: "mtls-auth",
    route: { id: routeId },
    // mtls-auth is https-only per its spec's Configuration schema requirement.
    protocols: ["https"],
    config,
  });
  const pluginId = plugin.body.id as string;

  for (const extra of extraPlugins ?? []) {
    await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
      name: extra.name,
      route: { id: routeId },
      config: extra.config,
    });
  }

  await waitForRouteReady(request, routePath, {
    timeoutMs: 30_000,
    consecutive: 9,
  });

  return { routePath, serviceId, routeId, pluginId };
}

async function listAllPages(
  request: APIRequestContext,
  firstUrl: string
): Promise<any[]> {
  const items: any[] = [];
  let url: string | null = firstUrl;
  while (url) {
    const res = await request.get(url);
    if (!res.ok()) {
      break;
    }
    const body = await res.json();
    items.push(...(body.data ?? []));
    url = body.next ? `${KONG_ADMIN_URL}${body.next}` : null;
  }
  return items;
}

/**
 * Delete every route and service whose name starts with `prefix`
 * (route-scoped plugins cascade with their route).
 */
export async function cleanupByPrefix(
  request: APIRequestContext,
  prefix: string
): Promise<void> {
  const routes = await listAllPages(
    request,
    `${KONG_ADMIN_URL}/routes?size=1000`
  );
  for (const route of routes) {
    if (typeof route.name === "string" && route.name.startsWith(prefix)) {
      await request.delete(`${KONG_ADMIN_URL}/routes/${route.id}`);
    }
  }
  const services = await listAllPages(
    request,
    `${KONG_ADMIN_URL}/services?size=1000`
  );
  for (const service of services) {
    if (typeof service.name === "string" && service.name.startsWith(prefix)) {
      await request.delete(`${KONG_ADMIN_URL}/services/${service.id}`);
    }
  }
}

/**
 * Lua body for {@link sharedContextObserver}. `setHeader` is a Kong setter
 * expression (`kong.service.request.set_header` or `kong.response.set_header`).
 */
function sharedContextObserverLua(setHeader: string): string {
  return `
    local shared = kong.ctx.shared.mtls_auth
    if shared == nil then
      ${setHeader}("X-Shared-Keys", "__absent__")
      return
    end
    local names = {}
    for key in pairs(shared) do
      names[#names + 1] = key
    end
    table.sort(names)
    ${setHeader}("X-Shared-Keys", table.concat(names, ","))
    for _, key in ipairs(names) do
      ${setHeader}(
        "X-Shared-" .. string.gsub(key, "_", "-"),
        ngx.encode_base64(tostring(shared[key]))
      )
    end
  `;
}

/**
 * Route-scoped observer for the spec's shared-certificate-context seam: a
 * bundled `post-function` plugin (runs after mtls-auth) that publishes
 * `kong.ctx.shared.mtls_auth`:
 *
 * - access: upstream request headers, echoed by httpbun on a proxied request
 * - header_filter: the same headers on the client response, so a request
 *   that `kong.response.exit`s in access (verification-gate reject) is still
 *   observable
 *
 * - `X-Shared-Keys`: sorted comma-joined key set of the table, or
 *   `__absent__` when the context entry is missing.
 * - `X-Shared-<key>` (underscores → hyphens): base64 of each present value.
 */
export function sharedContextObserver(): ExtraPlugin {
  return {
    name: "post-function",
    config: {
      access: [sharedContextObserverLua("kong.service.request.set_header")],
      header_filter: [sharedContextObserverLua("kong.response.set_header")],
    },
  };
}

/** Decode an `X-Shared-<key>` header value produced by the observer. */
export function decodeSharedValue(value: string): string {
  return Buffer.from(value, "base64").toString("utf8");
}
