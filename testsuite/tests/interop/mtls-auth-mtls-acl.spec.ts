// Interop: mtls-auth (producer) → mtls-acl (consumer) over the shared
// per-request certificate context kong.ctx.shared.mtls_auth. The mtls-auth
// spec is the source of truth for the contract asserted here:
// - fingerprint is SHA-1 hex of the DER certificate, without colons
// - serial is hexadecimal (not decimal)
//
// The contract's "populated only after successful verification → consumers
// fail closed on absence" clause is only constructible when mtls-auth is
// *not applicable* to the request (whenever it is applicable, it terminates
// unverified requests itself before mtls-acl runs); that construction is
// covered by the mtls-acl per-plugin default-deny and
// client-request-cannot-supply-value tests.
import * as crypto from "crypto";
import { test, expect } from "@playwright/test";
import {
  uniquePrefix,
  mtlsClientCert,
  disposeMtlsContexts,
} from "../../helpers/kong";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  mtlsGetAfterAclReady,
} from "../../helpers/mtls-acl";

const PREFIX = uniquePrefix("mtls-interop");

test.describe("interop — mtls-auth feeds kong.ctx.shared.mtls_auth to mtls-acl", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
    await disposeMtlsContexts();
  });

  // [Verifies: mtls-acl.certificate-attribute-extraction.configured-attribute-selected]
  test("fingerprint is SHA-1 hex of the DER certificate without colons", async ({
    request,
  }) => {
    const alice = mtlsClientCert("alice");
    const sha1Hex = crypto
      .createHash("sha1")
      .update(alice.x509.raw)
      .digest("hex");

    // Only colon-less hex spellings of the SHA-1 digest are allowed; a
    // colon-separated or non-SHA-1 fingerprint cannot match either entry.
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        certificate_attribute: "fingerprint",
        allow: [sha1Hex, sha1Hex.toUpperCase()],
      },
    });

    const res = await mtlsGetAfterAclReady(request, routePath, {
      denied: { clientCert: "no-cn" },
      allowed: { clientCert: "alice" },
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).headers).toBeTruthy(); // upstream echo reached
  });

  // [Verifies: mtls-acl.certificate-attribute-extraction.configured-attribute-selected]
  test("serial is hexadecimal, not decimal", async ({ request }) => {
    const alice = mtlsClientCert("alice");
    const serialHex = alice.x509.serialNumber; // hex, from the certificate
    const serialDecimal = BigInt(`0x${serialHex}`).toString(10);
    expect(serialDecimal).not.toBe(serialHex.toLowerCase());

    // Only hex spellings are allowed — a decimal rendering cannot match.
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        certificate_attribute: "serial",
        allow: [serialHex.toLowerCase(), serialHex.toUpperCase()],
      },
    });

    const res = await mtlsGetAfterAclReady(request, routePath, {
      denied: { clientCert: "no-cn" },
      allowed: { clientCert: "alice" },
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).headers).toBeTruthy();
  });
});
