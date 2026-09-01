import * as crypto from "crypto";
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

const alice = certExpectations("alice");

test.describe("mtls-auth — certificate detail headers for upstream", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
    await disposeMtlsContexts();
  });

  // [Verifies: mtls-auth.certificate-detail-headers.all-configured]
  test("all five configured headers carry the certificate details", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        upstream_cert_header: "X-Client-Cert-Pem",
        upstream_cert_fingerprint_header: "X-Client-Cert-Fingerprint",
        upstream_cert_serial_header: "X-Client-Cert-Serial",
        upstream_cert_i_dn_header: "X-Client-Cert-Issuer-Dn",
        upstream_cert_s_dn_header: "X-Client-Cert-Subject-Dn",
      },
    });

    const res = await mtlsProxyGet(request, routePath, { clientCert: "alice" });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    // PEM, URL-encoded: no raw newlines on the wire, decodes to the fixture PEM.
    const pemHeader = echoedHeader(headers, "X-Client-Cert-Pem");
    expect(pemHeader).toBeDefined();
    expect(pemHeader!).not.toContain("\n");
    expect(pemHeader!).toMatch(/%0A/i);
    expect(decodeURIComponent(pemHeader!).trim()).toBe(alice.pem.trim());

    expect(echoedHeader(headers, "X-Client-Cert-Fingerprint")).toBe(
      alice.fingerprintSha1Hex
    );
    expect(echoedHeader(headers, "X-Client-Cert-Serial")).toBe(alice.serialHex);
    expect(echoedHeader(headers, "X-Client-Cert-Issuer-Dn")).toBe(
      alice.issuerDn
    );
    expect(echoedHeader(headers, "X-Client-Cert-Subject-Dn")).toBe(
      alice.subjectDn
    );
  });

  // [Verifies: mtls-auth.certificate-detail-headers.colliding-names-last-wins]
  test("colliding header names: subject DN (later setter) wins over serial", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        upstream_cert_serial_header: "X-Client-Cert",
        upstream_cert_s_dn_header: "X-Client-Cert",
      },
    });

    const res = await mtlsProxyGet(request, routePath, { clientCert: "alice" });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    const collided = echoedHeader(headers, "X-Client-Cert");
    expect(collided).toBe(alice.subjectDn);
    expect(collided).not.toContain(alice.serialHex);
  });

  // [Verifies: mtls-auth.certificate-detail-headers.fingerprint-sha1-hex]
  test("fingerprint is lowercase SHA-1 hex of the DER certificate", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        upstream_cert_fingerprint_header: "X-Client-Cert-Fingerprint",
      },
    });

    const res = await mtlsProxyGet(request, routePath, { clientCert: "alice" });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    const fingerprint = echoedHeader(headers, "X-Client-Cert-Fingerprint");
    expect(fingerprint).toBeDefined();
    // 40 lowercase hex chars: SHA-1 length, no colons, no spaces.
    expect(fingerprint!).toMatch(/^[0-9a-f]{40}$/);
    expect(fingerprint!).toBe(alice.fingerprintSha1Hex);
    // Explicitly not SHA-256.
    const sha256 = crypto
      .createHash("sha256")
      .update(new crypto.X509Certificate(alice.pem).raw)
      .digest("hex");
    expect(fingerprint!).not.toBe(sha256);
  });

  // [Verifies: mtls-auth.certificate-detail-headers.serial-hex]
  test("serial is hexadecimal with no separators, not decimal", async ({
    request,
  }) => {
    // Precondition from the scenario: a cert whose decimal and hex serial
    // renderings differ (true for the fixture's random serial).
    expect(alice.serialHex).not.toBe(alice.serialDecimal);

    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        upstream_cert_serial_header: "X-Client-Cert-Serial",
      },
    });

    const res = await mtlsProxyGet(request, routePath, { clientCert: "alice" });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    const serial = echoedHeader(headers, "X-Client-Cert-Serial");
    expect(serial).toBeDefined();
    expect(serial!).toMatch(/^[0-9A-Fa-f]+$/); // no colons, no spaces
    expect(serial!).toBe(alice.serialHex);
    expect(serial!).not.toBe(alice.serialDecimal);
  });

  // [Verifies: mtls-auth.certificate-detail-headers.unset-omitted]
  test("no certificate detail headers are added when none are configured", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {},
    });

    const res = await mtlsProxyGet(request, routePath, { clientCert: "alice" });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    // No upstream request header carries any certificate-derived value.
    for (const value of Object.values(headers).map(String)) {
      expect(value).not.toContain(alice.fingerprintSha1Hex);
      expect(value.toUpperCase()).not.toContain(alice.serialHex);
      expect(value).not.toContain(alice.subjectDn!);
      expect(value).not.toContain(alice.issuerDn);
      expect(value).not.toContain("BEGIN CERTIFICATE");
      expect(value).not.toContain("BEGIN%20CERTIFICATE");
    }
  });

  // [Verifies: mtls-auth.certificate-detail-headers.overwrites-client-header]
  test("plugin-computed value overwrites a client-supplied header of the same name", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        upstream_cert_fingerprint_header: "X-Cert-Fingerprint",
      },
    });

    const res = await mtlsProxyGet(request, routePath, {
      clientCert: "alice",
      headers: { "X-Cert-Fingerprint": "attacker-forged-value" },
    });
    expect(res.status()).toBe(200);
    const headers = (await res.json()).headers;

    // Exactly the computed value: forged value neither kept nor appended.
    expect(echoedHeader(headers, "X-Cert-Fingerprint")).toBe(
      alice.fingerprintSha1Hex
    );
  });
});
