import { APIRequestContext } from "playwright";
import {
  KONG_ADMIN_URL,
  provisionKong,
  waitForRouteReady,
  uniquePrefix,
  mtlsClientCert,
  mtlsProxyGet,
  MtlsProxyRequestInit,
  MtlsProxyResponse,
} from "./kong";
import { upstreamServiceDefaults } from "./upstream";

export { uniquePrefix };

/** Default-deny response body mtls-acl must return on every rejection. */
export const DENY_BODY = { message: "You cannot consume this service" };

/** Stable tag used to recover a global mtls-auth leaked by a prior worker. */
const GLOBAL_MTLS_AUTH_TEST_TAG = "e2e-mtls-acl-global-auth";

const MTLS_STABLE_PROBES = 9;
const MTLS_PROPAGATION_TIMEOUT_MS = 30_000;
const MTLS_PROBE_INTERVAL_MS = 250;

let counter = 0;

export type ProvisionOptions = {
  prefix: string;
  /** mtls-acl plugin config (from the spec's Configuration schema). */
  config: Record<string, unknown>;
  serviceTags?: string[];
  /**
   * Where to enable the producer plugin `mtls-auth` (populates
   * `kong.ctx.shared.mtls_auth` after client-cert verification):
   * - "route" (default): on the same route as mtls-acl
   * - "service": on the service that owns the route
   * - "none": do not provision mtls-auth at all
   */
  authScope?: "route" | "service" | "none";
  /** mtls-auth config; defaults to {} (schema defaults). */
  authConfig?: Record<string, unknown>;
};

export type ProvisionResult = {
  routePath: string;
  serviceId: string;
  routeId: string;
  pluginId: string;
  authPluginId?: string;
};

/**
 * Provision service + route + route-scoped mtls-acl plugin (+ optionally the
 * mtls-auth producer) and wait until the route is live on all DP replicas.
 *
 * The mtls-acl plugin is created with `protocols: ["https"]` (its schema only
 * permits https); the route keeps its default protocols so the plain-http
 * readiness probe still works.
 */
export async function provisionPluginRoute(
  request: APIRequestContext,
  options: ProvisionOptions
): Promise<ProvisionResult> {
  const { prefix, config, serviceTags, authConfig } = options;
  const authScope = options.authScope ?? "route";
  const n = ++counter;

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
    name: "mtls-acl",
    route: { id: routeId },
    protocols: ["https"],
    config,
  });
  const pluginId = plugin.body.id as string;

  let authPluginId: string | undefined;
  if (authScope !== "none") {
    const scope =
      authScope === "service"
        ? { service: { id: serviceId } }
        : { route: { id: routeId } };
    const authPlugin = await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
      name: "mtls-auth",
      ...scope,
      config: authConfig ?? {},
    });
    authPluginId = authPlugin.body.id as string;
  }

  await waitForRouteReady(request, routePath, {
    timeoutMs: 30_000,
    consecutive: 9,
  });

  return { routePath, serviceId, routeId, pluginId, authPluginId };
}

/**
 * Create a *global* mtls-auth plugin (no route/service scope). Callers must
 * remove it in a try/finally with {@link deleteGlobalMtlsAuthAndWait}; suite
 * hooks should also call {@link cleanupGlobalMtlsAuth} to recover a plugin
 * leaked by a crashed worker. Cascade route cleanup cannot remove it.
 */
export async function createGlobalMtlsAuth(
  request: APIRequestContext,
  options: {
    authConfig?: Record<string, unknown>;
    tags?: string[];
  } = {}
): Promise<string> {
  const res = await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, {
    name: "mtls-auth",
    config: options.authConfig ?? {},
    tags: Array.from(
      new Set([GLOBAL_MTLS_AUTH_TEST_TAG, ...(options.tags ?? [])])
    ),
  });
  return res.body.id as string;
}

export async function deletePlugin(
  request: APIRequestContext,
  pluginId: string
): Promise<void> {
  const res = await request.delete(`${KONG_ADMIN_URL}/plugins/${pluginId}`);
  if (res.status() !== 204 && res.status() !== 404) {
    throw new Error(
      `failed to delete plugin ${pluginId}: ${res.status()} ${await res.text()}`
    );
  }
}

/**
 * GET over the mTLS entry point, retrying until `expectedStatus` shows up.
 *
 * `waitForRouteReady` only proves the *route* is live on all DP replicas;
 * plugins created in the same provisioning burst can land on a data plane a
 * sync round later, briefly serving the pre-plugin behavior. Retrying on the
 * unexpected status absorbs that lag; callers still hard-assert the returned
 * response, so a genuine mismatch fails after the retry budget.
 */
export async function mtlsGetExpecting(
  request: APIRequestContext,
  routePath: string,
  expectedStatus: number,
  init?: Omit<MtlsProxyRequestInit, "method" | "shouldRetry">
): Promise<MtlsProxyResponse> {
  return mtlsProxyGet(request, routePath, {
    attempts: 20,
    ...init,
    shouldRetry: (res) => res.status() !== expectedStatus,
  });
}

type MtlsGetInit = Omit<
  MtlsProxyRequestInit,
  "method" | "shouldRetry"
>;

function isExactDenyBody(body: unknown): boolean {
  return (
    typeof body === "object" &&
    body !== null &&
    !Array.isArray(body) &&
    Object.keys(body).length === 1 &&
    (body as { message?: unknown }).message === DENY_BODY.message
  );
}

/**
 * Require a stable streak of exact mtls-acl denials across fresh TLS
 * connections. `Connection: close` matters because nginx chooses a DP once
 * per stream connection; without it, repeated requests can stay pinned to a
 * single replica and cannot prove that the plugin has propagated to all DPs.
 */
export async function waitForMtlsAclDeny(
  request: APIRequestContext,
  routePath: string,
  init: MtlsGetInit = {}
): Promise<MtlsProxyResponse> {
  const deadline = Date.now() + MTLS_PROPAGATION_TIMEOUT_MS;
  let consecutive = 0;
  let lastOutcome = "no response";

  while (Date.now() < deadline) {
    try {
      const res = await mtlsProxyGet(request, routePath, {
        ...init,
        attempts: 1,
        headers: {
          ...init.headers,
          Connection: "close",
        },
      });
      const status = res.status();
      let body: unknown;
      if (status === 403) {
        try {
          body = await res.json();
        } catch {
          body = undefined;
        }
      }

      if (status === 403 && isExactDenyBody(body)) {
        consecutive += 1;
        if (consecutive >= MTLS_STABLE_PROBES) {
          return res;
        }
      } else {
        consecutive = 0;
      }
      lastOutcome = `${status} ${JSON.stringify(body)}`;
    } catch (err) {
      consecutive = 0;
      lastOutcome = err instanceof Error ? err.message : String(err);
    }

    await new Promise((resolve) =>
      setTimeout(resolve, MTLS_PROBE_INTERVAL_MS)
    );
  }

  throw new Error(
    `mtls-acl did not return ${MTLS_STABLE_PROBES} consecutive exact denials within ${MTLS_PROPAGATION_TIMEOUT_MS}ms; last outcome: ${lastOutcome}`
  );
}

/**
 * Prove mtls-acl has propagated before exercising a successful request.
 *
 * A route can become ready before its plugins. In that window an unprotected
 * route also returns 200, so a grant-path test cannot use its own successful
 * response as the readiness signal. The denied probe must present a trusted
 * certificate/value that the configured ACL rejects; the plugin's exact 403
 * responses over fresh connections prove the ACL is active across the DP
 * pool before the allowed request is sent.
 */
export async function mtlsGetAfterAclReady(
  request: APIRequestContext,
  routePath: string,
  options: {
    denied: MtlsGetInit;
    allowed: MtlsGetInit;
  }
): Promise<MtlsProxyResponse> {
  await waitForMtlsAclDeny(request, routePath, options.denied);

  return mtlsGetExpecting(request, routePath, 200, options.allowed);
}

/** Delete a global mtls-auth plugin and wait for its removal on every DP. */
export async function deleteGlobalMtlsAuthAndWait(
  request: APIRequestContext,
  pluginId: string,
  aclRoutePath: string
): Promise<void> {
  await deletePlugin(request, pluginId);
  await waitForMtlsAclDeny(request, aclRoutePath);
}

/** Subject CN of an mTLS fixture certificate (e.g. "Alice Example"). */
export function certCommonName(fixtureName: string): string {
  const subject = mtlsClientCert(fixtureName).x509.subject;
  const cn = subject
    .split("\n")
    .find((line) => line.startsWith("CN="));
  if (!cn) {
    throw new Error(`fixture ${fixtureName} has no CN in subject: ${subject}`);
  }
  return cn.slice("CN=".length);
}

async function listAll(
  request: APIRequestContext,
  collection: "routes" | "services" | "plugins"
): Promise<
  Array<{ id: string; name: string | null; tags?: string[] | null }>
> {
  const items: Array<{
    id: string;
    name: string | null;
    tags?: string[] | null;
  }> = [];
  let url: string | null = `${KONG_ADMIN_URL}/${collection}?size=1000`;
  while (url) {
    const res = await request.get(url);
    const body = await res.json();
    items.push(...(body.data ?? []));
    url = body.next ? `${KONG_ADMIN_URL}${body.next}` : null;
  }
  return items;
}

/** Delete global mtls-auth plugins left by this test suite or a prior retry. */
export async function cleanupGlobalMtlsAuth(
  request: APIRequestContext
): Promise<void> {
  const plugins = await listAll(request, "plugins");
  for (const plugin of plugins) {
    if (
      plugin.name === "mtls-auth" &&
      plugin.tags?.includes(GLOBAL_MTLS_AUTH_TEST_TAG)
    ) {
      await deletePlugin(request, plugin.id);
    }
  }
}

/**
 * Delete this file's routes (route-scoped plugins cascade) and then its
 * services, matched by name prefix. Never call with a shared base prefix.
 */
export async function cleanupByPrefix(
  request: APIRequestContext,
  prefix: string
): Promise<void> {
  const routes = await listAll(request, "routes");
  for (const route of routes) {
    if (route.name?.startsWith(prefix)) {
      await request.delete(`${KONG_ADMIN_URL}/routes/${route.id}`);
    }
  }
  const services = await listAll(request, "services");
  for (const service of services) {
    if (service.name?.startsWith(prefix)) {
      await request.delete(`${KONG_ADMIN_URL}/services/${service.id}`);
    }
  }
}
