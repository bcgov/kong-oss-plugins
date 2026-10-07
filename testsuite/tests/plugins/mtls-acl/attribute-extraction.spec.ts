import { test, expect } from "@playwright/test";
import { uniquePrefix, disposeMtlsContexts } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  cleanupGlobalMtlsAuth,
  createGlobalMtlsAuth,
  deleteGlobalMtlsAuthAndWait,
  certCommonName,
  mtlsGetExpecting,
  mtlsGetAfterAclReady,
  waitForMtlsAclDeny,
  DENY_BODY,
} from "../../../helpers/mtls-acl";

const PREFIX = uniquePrefix("mtls-acl-extract");
const ALICE_CN = certCommonName("alice");

test.describe("mtls-acl — certificate attribute extraction", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupGlobalMtlsAuth(request);
    // Only this file's PREFIX — wiping a shared base races with parallel workers.
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupGlobalMtlsAuth(request);
    await cleanupByPrefix(request, PREFIX);
    await disposeMtlsContexts();
  });

  // [Verifies: mtls-acl.certificate-attribute-extraction.configured-attribute-selected]
  test("the configured attribute is the one evaluated", async ({ request }) => {
    // allow contains only the certificate's CN — none of its other attribute
    // values (fingerprint, serial, DNs, organization) appear in the list.
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        certificate_attribute: "common_name",
        allow: [ALICE_CN],
      },
    });

    const res = await mtlsGetAfterAclReady(request, routePath, {
      denied: { clientCert: "no-cn" },
      allowed: { clientCert: "alice" },
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.headers).toBeTruthy(); // upstream echo reached
  });

  // [Verifies: mtls-acl.certificate-attribute-extraction.service-auth-route-acl]
  test("service-scoped mtls-auth supplies context to route-scoped mtls-acl", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      authScope: "service",
      config: {
        certificate_attribute: "common_name",
        allow: [ALICE_CN],
      },
    });

    const res = await mtlsGetAfterAclReady(request, routePath, {
      denied: { clientCert: "no-cn" },
      allowed: { clientCert: "alice" },
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).headers).toBeTruthy();
  });

  // [Verifies: mtls-acl.certificate-attribute-extraction.global-auth-scoped-acl]
  // Parallel-run hazard: while the global mtls-auth exists (a few seconds,
  // CP→DP sync included), it gates *all* unverified https traffic through
  // the gateway, so sibling workers' https requests without a trusted client
  // cert can transiently see 401. CI (workers=1) is unaffected.
  test("global mtls-auth supplies context to a scoped mtls-acl", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      authScope: "none",
      config: {
        certificate_attribute: "common_name",
        allow: [ALICE_CN],
      },
    });

    const globalAuthId = await createGlobalMtlsAuth(request, {
      tags: [PREFIX],
    });
    try {
      // Retries also absorb the propagation lag of the just-created global plugin.
      const res = await mtlsGetAfterAclReady(request, routePath, {
        denied: { clientCert: "no-cn" },
        allowed: { clientCert: "alice" },
      });
      expect(res.status()).toBe(200);
      expect((await res.json()).headers).toBeTruthy();
    } finally {
      await deleteGlobalMtlsAuthAndWait(request, globalAuthId, routePath);
    }
  });

  // [Verifies: mtls-acl.certificate-attribute-extraction.missing-attribute-rejected]
  test("attribute missing from the shared context is rejected", async ({
    request,
  }) => {
    // The no-cn fixture verifies successfully but its subject DN carries no
    // CN, so the shared context has no common_name key. allow contents are
    // irrelevant — it even contains the certificate's O value.
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        certificate_attribute: "common_name",
        allow: ["Example Org"],
      },
    });

    const res = await mtlsGetExpecting(request, routePath, 403, {
      clientCert: "no-cn",
    });
    expect(res.status()).toBe(403);
    expect(await res.json()).toEqual(DENY_BODY);
  });

  // [Verifies: mtls-acl.certificate-attribute-extraction.client-request-cannot-supply-value]
  test("client request content cannot supply the value", async ({ request }) => {
    // No mtls-auth anywhere on the chain and no client certificate: nothing
    // populates kong.ctx.shared.mtls_auth. The request header carrying an
    // exact allow-list value must play no part in the decision.
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      authScope: "none",
      config: {
        certificate_attribute: "common_name",
        allow: [ALICE_CN],
      },
    });

    const res = await waitForMtlsAclDeny(request, routePath, {
      headers: {
        "X-Client-Cert-Common-Name": ALICE_CN,
        "X-Common-Name": ALICE_CN,
      },
    });
    expect(res.status()).toBe(403);
    expect(await res.json()).toEqual(DENY_BODY);
  });
});
