import { APIRequestContext } from "playwright";
import { provisionKong } from "./kong";
import logger from "./logger";

const ADMIN_URL = "http://kong.localtest.me:8001";

export type JwksProvision = {
  proxyBaseUrl: string;
  cleanup: () => Promise<void>;
};

// Delete any routes and services left over from previous failed test runs so
// that a fresh run starts from a clean slate.
async function cleanupStale(request: APIRequestContext): Promise<void> {
  try {
    const r = await request.get(`${ADMIN_URL}/routes?size=100`);
    const body = await r.json();
    for (const route of body.data ?? []) {
      if (typeof route.name === "string" && route.name.startsWith("tra-")) {
        await request.fetch(`${ADMIN_URL}/routes/${route.id}`, {
          method: "DELETE",
        });
        logger.debug({ name: route.name }, "pre-cleanup: deleted stale route");
      }
    }
  } catch (e) {
    logger.debug(e, "pre-cleanup: route scan failed (non-fatal)");
  }

  try {
    const r = await request.get(`${ADMIN_URL}/services?size=100`);
    const body = await r.json();
    for (const svc of body.data ?? []) {
      if (
        typeof svc.name === "string" &&
        svc.name.startsWith("trust-registry-ai-svc-")
      ) {
        await request.fetch(`${ADMIN_URL}/services/${svc.id}`, {
          method: "DELETE",
        });
        logger.debug({ name: svc.name }, "pre-cleanup: deleted stale service");
      }
    }
  } catch (e) {
    logger.debug(e, "pre-cleanup: service scan failed (non-fatal)");
  }
}

// Provisions a service + two JWKS routes + trust-registry-ai plugin.
// Uses kong.localtest.me as the proxy host (reliable DNS, already used by
// other plugin tests in this suite).
// Route 1: GET /.well-known/jwks.json  (all-keys endpoint)
// Route 2: GET /keysets/{name}/.well-known/jwks.json  (keyset endpoint)
export async function provisionJwksRoutes(
  request: APIRequestContext,
  runId: string
): Promise<JwksProvision> {
  await cleanupStale(request);

  const uid = runId.toString().padStart(8, "0").substring(0, 8);
  const svcId      = `${uid}-0000-0000-0000-00000000cafe`;
  const routeAllId = `${uid}-0001-0000-0000-00000000cafe`;
  const routeKsId  = `${uid}-0002-0000-0000-00000000cafe`;
  const proxyHost  = "kong.localtest.me";

  await provisionKong(request, `${ADMIN_URL}/services`, {
    id: svcId,
    name: `trust-registry-ai-svc-${uid}`,
    host: "httpbin.org",
    port: 80,
    protocol: "http",
  });

  await provisionKong(request, `${ADMIN_URL}/routes`, {
    id: routeAllId,
    name: `tra-all-${uid}`,
    hosts: [proxyHost],
    paths: ["/.well-known/jwks.json"],
    methods: ["GET"],
    strip_path: false,
    service: { id: svcId },
  });

  await provisionKong(request, `${ADMIN_URL}/routes`, {
    id: routeKsId,
    name: `tra-keyset-${uid}`,
    hosts: [proxyHost],
    // ~ prefix = regex route; dots escaped so Kong treats them as literals
    paths: ["~/keysets/(?<key_set>[^/]+)/\\.well-known/jwks\\.json"],
    methods: ["GET"],
    strip_path: false,
    service: { id: svcId },
  });

  await provisionKong(request, `${ADMIN_URL}/plugins`, {
    name: "trust-registry-ai",
    service: { id: svcId },
    config: {},
  });

  const cleanup = async () => {
    for (const routeId of [routeAllId, routeKsId]) {
      try {
        await request.fetch(`${ADMIN_URL}/routes/${routeId}`, {
          method: "DELETE",
        });
      } catch (e) {
        logger.debug(e, `cleanup: failed to delete route ${routeId}`);
      }
    }
    try {
      await request.fetch(`${ADMIN_URL}/services/${svcId}`, {
        method: "DELETE",
      });
    } catch (e) {
      logger.debug(e, `cleanup: failed to delete service ${svcId}`);
    }
  };

  // Kong CP→DP propagation takes a moment. Retry the all-keys endpoint until
  // it becomes active (same pattern as callAPI's 404-retry in the test suite).
  const probeUrl = `http://${proxyHost}:8000/.well-known/jwks.json`;
  for (let attempt = 0; attempt < 20; attempt++) {
    try {
      const probe = await request.get(probeUrl);
      if (probe.status() === 200) break;
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }

  return {
    proxyBaseUrl: `http://${proxyHost}:8000`,
    cleanup,
  };
}

export async function registerPemKey(
  request: APIRequestContext,
  name: string,
  kid: string,
  pem: string,
  keysetName?: string
): Promise<string> {
  const payload: any = { name, kid, pem: { public_key: pem } };
  if (keysetName) payload.set = { name: keysetName };
  const resp = await provisionKong(request, `${ADMIN_URL}/keys`, payload);
  return resp.body.id as string;
}

export async function registerJwkKey(
  request: APIRequestContext,
  name: string,
  kid: string,
  jwkObj: object,
  keysetName?: string
): Promise<string> {
  const payload: any = {
    name,
    kid,
    jwk: JSON.stringify({ ...jwkObj, kid }),
  };
  if (keysetName) payload.set = { name: keysetName };
  const resp = await provisionKong(request, `${ADMIN_URL}/keys`, payload);
  return resp.body.id as string;
}

export async function createKeyset(
  request: APIRequestContext,
  name: string
): Promise<string> {
  const resp = await provisionKong(request, `${ADMIN_URL}/key-sets`, { name });
  return resp.body.id as string;
}

// Poll a JWKS proxy URL until the response contains all requiredKids, or until
// maxWaitMs elapses. Returns the final response. Use when key data registered
// via Admin API may not yet have propagated to the DP.
export async function waitForJwks(
  request: APIRequestContext,
  url: string,
  requiredKids: string[],
  maxWaitMs: number = 12000
): Promise<{ status: number; body: any }> {
  const deadline = Date.now() + maxWaitMs;
  let lastStatus = 0;
  let lastBody: any = null;
  while (Date.now() < deadline) {
    try {
      const resp = await request.get(url);
      lastStatus = resp.status();
      lastBody = await resp.json();
      if (lastStatus === 200 && Array.isArray(lastBody?.keys)) {
        const presentKids = new Set(lastBody.keys.map((k: any) => k.kid));
        if (requiredKids.every((kid) => presentKids.has(kid))) {
          return { status: lastStatus, body: lastBody };
        }
      }
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  return { status: lastStatus, body: lastBody };
}

// Poll a JWKS URL until the specified kid is no longer present, or until
// maxWaitMs elapses. Used to let key-deletion propagate before asserting an
// empty-keys state.
export async function waitForKidAbsent(
  request: APIRequestContext,
  url: string,
  kid: string,
  maxWaitMs: number = 12000
): Promise<void> {
  const deadline = Date.now() + maxWaitMs;
  while (Date.now() < deadline) {
    try {
      const resp = await request.get(url);
      if (resp.status() === 200) {
        const body = await resp.json();
        const keys = Array.isArray(body?.keys) ? body.keys : [];
        if (!keys.some((k: any) => k.kid === kid)) return;
      }
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
}

// Poll a keyset-scoped JWKS URL until it returns 200 (keyset data propagated).
export async function waitForKeysetJwks(
  request: APIRequestContext,
  url: string,
  maxWaitMs: number = 10000
): Promise<{ status: number; body: any }> {
  const deadline = Date.now() + maxWaitMs;
  let lastStatus = 0;
  let lastBody: any = null;
  while (Date.now() < deadline) {
    try {
      const resp = await request.get(url);
      lastStatus = resp.status();
      lastBody = await resp.json();
      if (lastStatus === 200) return { status: lastStatus, body: lastBody };
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  return { status: lastStatus, body: lastBody };
}

export async function deleteKey(
  request: APIRequestContext,
  keyId: string
): Promise<void> {
  try {
    await request.fetch(`${ADMIN_URL}/keys/${keyId}`, { method: "DELETE" });
  } catch (e) {
    logger.debug(e, `cleanup: failed to delete key ${keyId}`);
  }
}

export async function deleteKeyset(
  request: APIRequestContext,
  keysetId: string
): Promise<void> {
  try {
    await request.fetch(`${ADMIN_URL}/key-sets/${keysetId}`, {
      method: "DELETE",
    });
  } catch (e) {
    logger.debug(e, `cleanup: failed to delete keyset ${keysetId}`);
  }
}
