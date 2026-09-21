import { test, expect } from "@playwright/test";
import { KONG_PROXY_TLS_URL } from "../../../helpers/kong";
import {
  uniquePrefix,
  mtlsProxyGet,
  disposeMtlsContexts,
  provisionPluginRoute,
  cleanupByPrefix,
  echoedHeader,
} from "../../../helpers/mtls-auth";

const PREFIX = uniquePrefix("mtls-auth");

const SNI_HEADER = "X-Tls-Server-Name";
const CN_HEADER = "X-Cert-Cn";

// The SNI the TLS client presents is the hostname it connects to.
const SNI_HOSTNAME = new URL(KONG_PROXY_TLS_URL).hostname;

test.describe("mtls-auth — server name (SNI) header", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
    await disposeMtlsContexts();
  });

  // [Verifies: mtls-auth.server-name-header.sni-present]
  test("configured header carries the SNI hostname", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { upstream_server_name_header: SNI_HEADER },
    });

    const res = await mtlsProxyGet(request, routePath, { clientCert: "alice" });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    expect(echoedHeader(headers, SNI_HEADER)).toBe(SNI_HOSTNAME);
  });

  // [Verifies: mtls-auth.server-name-header.sni-absent-header-cleared]
  test("missing SNI clears the configured header while other headers are still set", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        upstream_server_name_header: SNI_HEADER,
        upstream_cert_cn_header: CN_HEADER,
      },
    });

    // sni: false connects to the IP literal so the handshake carries no
    // server_name; the client also tries to smuggle a value under the
    // configured header name.
    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "alice",
      sni: false,
      headers: { [SNI_HEADER]: "attacker.example" },
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    expect(echoedHeader(headers, SNI_HEADER)).toBeUndefined();
    expect(echoedHeader(headers, CN_HEADER)).toBe("Alice Example");
  });

  // [Verifies: mtls-auth.server-name-header.unset-omitted]
  test("no SNI header is added when the option is not configured", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {},
    });

    const res = await mtlsProxyGet(request, routePath, { clientCert: "alice" });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    // Only the standard proxy headers may carry the hostname; nothing else
    // (i.e. no plugin-added SNI header) does.
    const allowed = ["host", "x-forwarded-host"];
    for (const [name, value] of Object.entries(headers)) {
      if (!allowed.includes(name.toLowerCase())) {
        expect(String(value)).not.toBe(SNI_HOSTNAME);
      }
    }
  });

  // [Verifies: mtls-auth.server-name-header.overwrites-client-header]
  test("plugin-computed SNI overwrites a client-supplied header of the same name", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: { upstream_server_name_header: SNI_HEADER },
    });

    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "alice",
      headers: { [SNI_HEADER]: "attacker.example" },
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    // Exactly the TLS SNI: forged value neither kept nor appended.
    expect(echoedHeader(headers, SNI_HEADER)).toBe(SNI_HOSTNAME);
  });
});
