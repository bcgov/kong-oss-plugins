import { test, expect } from "@playwright/test";
import { uniquePrefix, disposeMtlsContexts } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  certCommonName,
  mtlsGetExpecting,
  DENY_BODY,
} from "../../../helpers/mtls-acl";

const PREFIX = uniquePrefix("mtls-acl-denylist");
const ALICE_CN = certCommonName("alice"); // "Alice Example"

test.describe("mtls-acl — deny-list evaluation", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
    await disposeMtlsContexts();
  });

  // [Verifies: mtls-acl.deny-list-evaluation.no-match-grants-access]
  test("attribute value not in the deny list is granted access", async ({
    request,
  }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        certificate_attribute: "common_name",
        deny: ["Bob Example", "Another Client"],
      },
    });

    const res = await mtlsGetExpecting(request, routePath, 200, {
      clientCert: "alice",
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).headers).toBeTruthy(); // upstream echo reached
  });

  // [Verifies: mtls-acl.deny-list-evaluation.case-only-mismatch-grants-access]
  test("case-only mismatch against the deny list is granted access", async ({
    request,
  }) => {
    const caseVariant = ALICE_CN.toLowerCase();
    expect(caseVariant).not.toBe(ALICE_CN); // differs only in letter case

    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        certificate_attribute: "common_name",
        deny: [caseVariant],
      },
    });

    const res = await mtlsGetExpecting(request, routePath, 200, {
      clientCert: "alice",
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).headers).toBeTruthy();
  });

  // [Verifies: mtls-acl.deny-list-evaluation.match-rejected]
  test("attribute value in the deny list is rejected", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        certificate_attribute: "common_name",
        deny: [ALICE_CN],
      },
    });

    const res = await mtlsGetExpecting(request, routePath, 403, {
      clientCert: "alice",
    });
    expect(res.status()).toBe(403);
    expect(await res.json()).toEqual(DENY_BODY);
  });
});
