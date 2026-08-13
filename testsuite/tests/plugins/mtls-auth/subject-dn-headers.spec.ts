import { test, expect } from "@playwright/test";
import {
  uniquePrefix,
  mtlsProxyGet,
  disposeMtlsContexts,
  provisionPluginRoute,
  cleanupByPrefix,
  certExpectations,
  echoedHeader,
} from "../../../helpers/mtls-auth";

const PREFIX = uniquePrefix("mtls-auth");

const CN_HEADER = "X-Cert-Cn";
const ORG_HEADER = "X-Cert-Org";
const SERIAL_HEADER = "X-Cert-Serial";

test.describe("mtls-auth — CN and Organization headers from the subject DN", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
    await disposeMtlsContexts();
  });

  // [Verifies: mtls-auth.subject-dn-derived-headers.simple-extraction]
  test("CN and Organization extracted from a simple subject DN", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        upstream_cert_cn_header: CN_HEADER,
        upstream_cert_org_header: ORG_HEADER,
      },
    });

    // alice subject: CN=Alice Example,O=Example Org,C=US
    const res = await mtlsProxyGet(request, routePath, { clientCert: "alice" });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    expect(echoedHeader(headers, CN_HEADER)).toBe("Alice Example");
    expect(echoedHeader(headers, ORG_HEADER)).toBe("Example Org");
  });

  // [Verifies: mtls-auth.subject-dn-derived-headers.escaped-comma-decoded]
  test("escaped comma in the CN is decoded", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { upstream_cert_cn_header: CN_HEADER },
    });

    // comma-cn subject renders in the nginx DN as CN=Smith\, Jr.,O=Example Org,C=US
    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "comma-cn",
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    const cn = echoedHeader(headers, CN_HEADER);
    expect(cn).toBe("Smith, Jr.");
    expect(cn!).not.toContain("\\");
  });

  // [Verifies: mtls-auth.subject-dn-derived-headers.hex-escape-decoded]
  test("hex-escaped UTF-8 octets in the CN are decoded", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { upstream_cert_cn_header: CN_HEADER },
    });

    // utf8-cn subject renders in the nginx DN as CN=Caf\C3\A9,…
    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "utf8-cn",
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    const cn = echoedHeader(headers, CN_HEADER);
    expect(cn).toBe("Café");
    expect(cn!).not.toContain("\\C3");
  });

  // [Verifies: mtls-auth.subject-dn-derived-headers.duplicate-attribute-last-wins]
  test("duplicate CN keeps the last ASN.1 occurrence, not the last nginx-DN token", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { upstream_cert_cn_header: CN_HEADER },
    });

    // dup-cn ASN.1 subject order is CN=Second, OU=Sales, CN=First (nginx
    // renders the reverse: CN=First,OU=Sales,CN=Second). Last ASN.1 CN is
    // "First"; a parser taking the last CN= token of the nginx string would
    // wrongly produce "Second".
    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "dup-cn",
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    const cn = echoedHeader(headers, CN_HEADER);
    expect(cn).toBe("First");
    expect(cn).not.toBe("Second");
  });

  // [Verifies: mtls-auth.subject-dn-derived-headers.cn-missing-header-cleared]
  test("missing CN clears the configured header while other headers are still set", async ({
    request,
  }) => {
    const noCn = certExpectations("no-cn");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        upstream_cert_cn_header: CN_HEADER,
        upstream_cert_org_header: ORG_HEADER,
        upstream_cert_serial_header: SERIAL_HEADER,
      },
    });

    // no-cn subject: O=Example Org,C=US (no CN RDN). The client also tries to
    // smuggle a value under the configured CN header name.
    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "no-cn",
      headers: { [CN_HEADER]: "attacker-supplied-cn" },
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    expect(echoedHeader(headers, CN_HEADER)).toBeUndefined();
    expect(echoedHeader(headers, ORG_HEADER)).toBe("Example Org");
    expect(echoedHeader(headers, SERIAL_HEADER)).toBe(noCn.serialHex);
  });

  // [Verifies: mtls-auth.subject-dn-derived-headers.org-missing-header-cleared]
  test("missing Organization clears the configured header while other headers are still set", async ({
    request,
  }) => {
    const noOrg = certExpectations("no-org");
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        upstream_cert_cn_header: CN_HEADER,
        upstream_cert_org_header: ORG_HEADER,
        upstream_cert_serial_header: SERIAL_HEADER,
      },
    });

    // no-org subject: CN=NoOrg Example,C=US (no O RDN).
    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "no-org",
      headers: { [ORG_HEADER]: "attacker-supplied-org" },
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    expect(echoedHeader(headers, ORG_HEADER)).toBeUndefined();
    expect(echoedHeader(headers, CN_HEADER)).toBe("NoOrg Example");
    expect(echoedHeader(headers, SERIAL_HEADER)).toBe(noOrg.serialHex);
  });

  // [Verifies: mtls-auth.subject-dn-derived-headers.overwrites-client-cn-header]
  test("plugin-computed CN overwrites a client-supplied header of the same name", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { upstream_cert_cn_header: CN_HEADER },
    });

    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "alice",
      headers: { [CN_HEADER]: "attacker-forged-cn" },
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    // Exactly the computed value: forged value neither kept nor appended.
    expect(echoedHeader(headers, CN_HEADER)).toBe("Alice Example");
  });

  // [Verifies: mtls-auth.subject-dn-derived-headers.overwrites-client-org-header]
  test("plugin-computed Organization overwrites a client-supplied header of the same name", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { upstream_cert_org_header: ORG_HEADER },
    });

    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "alice",
      headers: { [ORG_HEADER]: "attacker-forged-org" },
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    expect(echoedHeader(headers, ORG_HEADER)).toBe("Example Org");
  });
});
