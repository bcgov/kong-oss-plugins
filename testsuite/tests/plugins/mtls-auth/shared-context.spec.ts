import { test, expect } from "@playwright/test";
import {
  uniquePrefix,
  mtlsProxyGet,
  disposeMtlsContexts,
  provisionPluginRoute,
  cleanupByPrefix,
  certExpectations,
  echoedHeader,
  sharedContextObserver,
  decodeSharedValue,
  MTLS_SUBJECT_DN,
  MTLS_ISSUER_DN,
} from "../../../helpers/mtls-auth";

const PREFIX = uniquePrefix("mtls-auth");

// Observable seam per the spec: a plugin running later in the same request's
// access phase (here Kong's bundled post-function) reads
// kong.ctx.shared.mtls_auth and publishes it as upstream request headers.

const ALL_KEYS =
  "cert,common_name,fingerprint,issuer_dn,organization,serial,subject_dn";

function sharedValue(
  headers: Record<string, unknown>,
  key: string
): string | undefined {
  const raw = echoedHeader(headers, `X-Shared-${key.replace(/_/g, "-")}`);
  return raw === undefined ? undefined : decodeSharedValue(raw);
}

test.describe("mtls-auth — shared certificate context for downstream plugins", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
    await disposeMtlsContexts();
  });

  // [Verifies: mtls-auth.shared-certificate-context.populated-on-verified-request]
  test("context carries every certificate attribute on a verified request, with no config", async ({
    request,
  }) => {
    const alice = certExpectations("alice");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {}, // context is populated independent of configuration
      extraPlugins: [sharedContextObserver()],
    });

    const res = await mtlsProxyGet(request, routePath, { clientCert: "alice" });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    expect(echoedHeader(headers, "X-Shared-Keys")).toBe(ALL_KEYS);

    const cert = sharedValue(headers, "cert");
    expect(cert).toBeDefined();
    expect(decodeURIComponent(cert!).trim()).toBe(alice.pem.trim());
    expect(sharedValue(headers, "fingerprint")).toBe(alice.fingerprintSha1Hex);
    expect(sharedValue(headers, "serial")).toBe(alice.serialHex);
    expect(sharedValue(headers, "issuer_dn")).toBe(MTLS_ISSUER_DN);
    expect(sharedValue(headers, "subject_dn")).toBe(MTLS_SUBJECT_DN["alice"]);
    expect(sharedValue(headers, "common_name")).toBe("Alice Example");
    expect(sharedValue(headers, "organization")).toBe("Example Org");
  });

  // [Verifies: mtls-auth.shared-certificate-context.cn-missing-key-absent]
  test("missing CN leaves the common_name key absent while other keys are populated", async ({
    request,
  }) => {
    const noCn = certExpectations("no-cn");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {},
      extraPlugins: [sharedContextObserver()],
    });

    // no-cn subject: O=Example Org,C=US (no CN RDN)
    const res = await mtlsProxyGet(request, routePath, { clientCert: "no-cn" });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    // Key set has no common_name entry at all (absent, not empty).
    expect(echoedHeader(headers, "X-Shared-Keys")).toBe(
      "cert,fingerprint,issuer_dn,organization,serial,subject_dn"
    );
    expect(sharedValue(headers, "common_name")).toBeUndefined();

    expect(sharedValue(headers, "organization")).toBe("Example Org");
    expect(sharedValue(headers, "fingerprint")).toBe(noCn.fingerprintSha1Hex);
    expect(sharedValue(headers, "serial")).toBe(noCn.serialHex);
    expect(sharedValue(headers, "issuer_dn")).toBe(MTLS_ISSUER_DN);
    expect(sharedValue(headers, "subject_dn")).toBe(MTLS_SUBJECT_DN["no-cn"]);
    const cert = sharedValue(headers, "cert");
    expect(cert).toBeDefined();
    expect(decodeURIComponent(cert!).trim()).toBe(noCn.pem.trim());
  });

  // [Verifies: mtls-auth.shared-certificate-context.org-missing-key-absent]
  test("missing Organization leaves the organization key absent while other keys are populated", async ({
    request,
  }) => {
    const noOrg = certExpectations("no-org");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {},
      extraPlugins: [sharedContextObserver()],
    });

    // no-org subject: CN=NoOrg Example,C=US (no O RDN)
    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "no-org",
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    expect(echoedHeader(headers, "X-Shared-Keys")).toBe(
      "cert,common_name,fingerprint,issuer_dn,serial,subject_dn"
    );
    expect(sharedValue(headers, "organization")).toBeUndefined();

    expect(sharedValue(headers, "common_name")).toBe("NoOrg Example");
    expect(sharedValue(headers, "fingerprint")).toBe(noOrg.fingerprintSha1Hex);
    expect(sharedValue(headers, "serial")).toBe(noOrg.serialHex);
    expect(sharedValue(headers, "issuer_dn")).toBe(MTLS_ISSUER_DN);
    expect(sharedValue(headers, "subject_dn")).toBe(MTLS_SUBJECT_DN["no-org"]);
    const cert = sharedValue(headers, "cert");
    expect(cert).toBeDefined();
    expect(decodeURIComponent(cert!).trim()).toBe(noOrg.pem.trim());
  });
});
