import { test, expect } from "@playwright/test";
import { uniquePrefix, disposeMtlsContexts } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  cleanupByPrefix,
  mtlsGetExpecting,
  DENY_BODY,
} from "../../../helpers/mtls-acl";

const PREFIX = uniquePrefix("mtls-acl-deny-default");

test.describe("mtls-acl — default deny", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
    await disposeMtlsContexts();
  });

  // [Verifies: mtls-acl.default-deny.missing-context-rejected]
  test("missing shared certificate context is rejected with 403 and the deny body", async ({
    request,
  }) => {
    // mtls-auth is not applicable to this request (not provisioned on the
    // route or service, and no client certificate is presented), so no
    // preceding plugin populates kong.ctx.shared.mtls_auth.
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      authScope: "none",
      config: {
        certificate_attribute: "common_name",
        allow: ["Alice Example"],
      },
    });

    const res = await mtlsGetExpecting(request, routePath, 403);
    expect(res.status()).toBe(403);
    expect(await res.json()).toEqual(DENY_BODY);
  });
});
