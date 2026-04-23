import { test, expect } from "@playwright/test";
import crypto from "crypto";
import { importPKCS8, importJWK, CompactSign, compactVerify } from "jose";
import Ajv from "ajv";
import {
  provisionJwksRoutes,
  registerPemKey,
  registerJwkKey,
  createKeyset,
  deleteKey,
  deleteKeyset,
  waitForJwks,
  waitForKidAbsent,
  waitForKeysetJwks,
} from "../../../helpers/trust-registry-ai";
import jwksSchema from "../../../helpers/schemas/jwks.schema.json";
import logger from "../../../helpers/logger";

const RUN_ID = Math.floor(Math.random() * 1e8)
  .toString()
  .padStart(8, "0");

// Keys and keysets registered within a test — cleared by afterEach.
let testKeys: string[] = [];
let testKeysets: string[] = [];

test.describe("trust-registry-ai plugin", () => {
  let proxyBaseUrl: string;
  let cleanupRoutes: () => Promise<void>;

  test.beforeAll(async ({ request }) => {
    const provision = await provisionJwksRoutes(request, RUN_ID);
    proxyBaseUrl = provision.proxyBaseUrl;
    cleanupRoutes = provision.cleanup;
    logger.debug({ proxyBaseUrl }, "trust-registry-ai routes provisioned");
  });

  test.afterAll(async () => {
    await cleanupRoutes();
  });

  test.afterEach(async ({ request }) => {
    for (const keyId of testKeys) {
      await deleteKey(request, keyId);
    }
    testKeys = [];
    for (const ksId of testKeysets) {
      await deleteKeyset(request, ksId);
    }
    testKeysets = [];
  });

  // ── T010 ─────────────────────────────────────────────────────────────────
  // [Verifies: US1-AS1, SC-001]
  test("T010 GET /.well-known/jwks.json returns all N registered keys", async ({
    request,
  }) => {
    const { publicKey: rsaPub1 } = crypto.generateKeyPairSync("rsa", {
      modulusLength: 2048,
      publicKeyEncoding: { type: "spki", format: "pem" },
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
    });
    const { publicKey: rsaPub2 } = crypto.generateKeyPairSync("rsa", {
      modulusLength: 2048,
      publicKeyEncoding: { type: "spki", format: "pem" },
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
    });
    const { publicKey: ecPub } = crypto.generateKeyPairSync("ec", {
      namedCurve: "P-256",
      publicKeyEncoding: { type: "spki", format: "pem" },
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
    });

    const rsaJwk = crypto.createPublicKey(rsaPub1).export({ format: "jwk" });
    const ecJwk  = crypto.createPublicKey(ecPub).export({ format: "jwk" });

    const kid1 = `t010-rsa-jwk-${RUN_ID}`;
    const kid2 = `t010-ec-jwk-${RUN_ID}`;
    const kid3 = `t010-rsa-pem-${RUN_ID}`;

    testKeys.push(await registerJwkKey(request, `key-${kid1}`, kid1, rsaJwk));
    testKeys.push(await registerJwkKey(request, `key-${kid2}`, kid2, ecJwk));
    testKeys.push(await registerPemKey(request, `key-${kid3}`, kid3, rsaPub2));

    // Wait for CP→DP propagation of key data before asserting.
    const { status, body } = await waitForJwks(
      request, `${proxyBaseUrl}/.well-known/jwks.json`, [kid1, kid2, kid3]
    );
    expect(status).toBe(200);
    expect(body.keys).toHaveLength(3); // SC-001
    expect(body.keys.map((k: any) => k.kid)).toContain(kid1);
    expect(body.keys.map((k: any) => k.kid)).toContain(kid2);
    expect(body.keys.map((k: any) => k.kid)).toContain(kid3);

    // Verify Content-Type on a fresh call (status already confirmed above).
    const resp2 = await request.get(`${proxyBaseUrl}/.well-known/jwks.json`);
    expect(resp2.headers()["content-type"]).toContain("application/json");
  });

  // ── T011 ─────────────────────────────────────────────────────────────────
  // [Verifies: US1-AS2, SC-003]
  test("T011 PEM-registered key appears in JWKS with correct fields and valid schema", async ({
    request,
  }) => {
    const { publicKey: pemPub } = crypto.generateKeyPairSync("rsa", {
      modulusLength: 2048,
      publicKeyEncoding: { type: "spki", format: "pem" },
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
    });
    const kid = `t011-rsa-pem-${RUN_ID}`;
    testKeys.push(await registerPemKey(request, `key-${kid}`, kid, pemPub));

    const { status, body } = await waitForJwks(
      request, `${proxyBaseUrl}/.well-known/jwks.json`, [kid]
    );
    expect(status).toBe(200);

    const jwk = body.keys.find((k: any) => k.kid === kid);
    expect(jwk).toBeDefined();
    expect(jwk.kid).toBe(kid);
    expect(["RSA", "EC"]).toContain(jwk.kty);
    expect(jwk.use).toBe("sig"); // handler injects use=sig for PEM-derived keys

    // SC-003: validate full response against RFC 7517 JWKS schema
    const ajv = new Ajv();
    const validate = ajv.compile(jwksSchema);
    expect(validate(body), JSON.stringify(validate.errors)).toBe(true);
  });

  // ── T012 ─────────────────────────────────────────────────────────────────
  // [Verifies: US1-AS3, FR-010]
  // Assumption: afterEach cleanup leaves Kong with zero keys registered.
  test("T012 no keys registered → GET /.well-known/jwks.json returns {keys: []}", async ({
    request,
  }) => {
    // Wait for prior tests' key deletions to propagate before asserting the
    // empty-keys state, otherwise this test can fail on stale propagation.
    const t011Kid = `t011-rsa-pem-${RUN_ID}`;
    await waitForKidAbsent(request, `${proxyBaseUrl}/.well-known/jwks.json`, t011Kid);

    const resp = await request.get(`${proxyBaseUrl}/.well-known/jwks.json`);
    expect(resp.status()).toBe(200);
    const body = await resp.json();
    expect(body).toEqual({ keys: [] });
  });

  // ── T013 ─────────────────────────────────────────────────────────────────
  // [Verifies: US2-AS1, SC-002]
  test("T013 keyset-scoped endpoint returns only that keyset's keys", async ({
    request,
  }) => {
    const ksSign  = `signing-${RUN_ID}`;
    const ksOther = `other-${RUN_ID}`;
    testKeysets.push(await createKeyset(request, ksSign));
    testKeysets.push(await createKeyset(request, ksOther));

    const kidA = `t013-sign-a-${RUN_ID}`;
    const kidB = `t013-sign-b-${RUN_ID}`;
    const kidC = `t013-other-${RUN_ID}`;

    for (const kid of [kidA, kidB, kidC]) {
      const { publicKey: pem } = crypto.generateKeyPairSync("rsa", {
        modulusLength: 2048,
        publicKeyEncoding: { type: "spki", format: "pem" },
        privateKeyEncoding: { type: "pkcs8", format: "pem" },
      });
      const ks = kid === kidC ? ksOther : ksSign;
      testKeys.push(await registerPemKey(request, `key-${kid}`, kid, pem, ks));
    }

    const { status, body } = await waitForKeysetJwks(
      request, `${proxyBaseUrl}/keysets/${ksSign}/.well-known/jwks.json`
    );
    expect(status).toBe(200);
    expect(body.keys).toHaveLength(2); // SC-002: exactly two, no false positives

    const returnedKids = body.keys.map((k: any) => k.kid);
    expect(returnedKids).toContain(kidA);
    expect(returnedKids).toContain(kidB);
    expect(returnedKids).not.toContain(kidC);
  });

  // ── T014 ─────────────────────────────────────────────────────────────────
  // [Verifies: US2-AS2]
  test("T014 empty keyset → GET /keysets/{name}/... returns {keys: []}", async ({
    request,
  }) => {
    const ksName = `empty-${RUN_ID}`;
    testKeysets.push(await createKeyset(request, ksName));

    const { status, body } = await waitForKeysetJwks(
      request, `${proxyBaseUrl}/keysets/${ksName}/.well-known/jwks.json`
    );
    expect(status).toBe(200);
    expect(body).toEqual({ keys: [] });
  });

  // ── T015 ─────────────────────────────────────────────────────────────────
  // [Verifies: US2-AS3, FR-009]
  test("T015 nonexistent keyset → 404 with message field", async ({
    request,
  }) => {
    const resp = await request.get(
      `${proxyBaseUrl}/keysets/nonexistent-${RUN_ID}/.well-known/jwks.json`
    );
    expect(resp.status()).toBe(404);
    const body = await resp.json();
    expect(body.message).toBe("Key set not found");
  });

  // ── T016 ─────────────────────────────────────────────────────────────────
  // [Verifies: FR-011]
  //
  // FR-011 specifies that unconvertible keys are omitted and logged. In
  // practice Kong's Admin API validates both PEM and JWK content at
  // registration time (returns 400 for invalid key material), so it is not
  // possible to inject an unloadable key via normal API calls. The defensive
  // skip-and-log code in handler.lua therefore cannot be triggered through
  // integration-test infrastructure.
  //
  // Coverage split:
  //   • The error-return path of pem_to_jwk (nil + error string) is verified
  //     at the unit level by T009 case (c).
  //   • This integration test verifies the positive side of FR-011: a valid
  //     key IS included in the JWKS response, confirming the handler correctly
  //     passes through convertible keys.
  test("T016 valid key is included in JWKS response [FR-011 positive path]", async ({
    request,
  }) => {
    const { publicKey: goodPem } = crypto.generateKeyPairSync("rsa", {
      modulusLength: 2048,
      publicKeyEncoding: { type: "spki", format: "pem" },
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
    });
    const kidGood = `t016-good-${RUN_ID}`;
    testKeys.push(await registerPemKey(request, `key-${kidGood}`, kidGood, goodPem));

    const { status, body } = await waitForJwks(
      request, `${proxyBaseUrl}/.well-known/jwks.json`, [kidGood]
    );
    expect(status).toBe(200);
    expect(body.keys.map((k: any) => k.kid)).toContain(kidGood);
  });

  // ── T017 ─────────────────────────────────────────────────────────────────
  // [Verifies: SC-004]
  test("T017 end-to-end sign → publish → fetch → verify loop", async ({
    request,
  }) => {
    const { publicKey: pemPub, privateKey: pemPriv } =
      crypto.generateKeyPairSync("rsa", {
        modulusLength: 2048,
        publicKeyEncoding: { type: "spki", format: "pem" },
        privateKeyEncoding: { type: "pkcs8", format: "pem" },
      });

    const kid = `t017-sc004-${RUN_ID}`;
    testKeys.push(await registerPemKey(request, `key-${kid}`, kid, pemPub));

    // Sign a JWS (compact serialization) over a known payload
    const privateKeyObj = await importPKCS8(pemPriv, "RS256");
    const payload = new TextEncoder().encode(
      JSON.stringify({ sub: "test", iat: Date.now() })
    );
    const jws = await new CompactSign(payload)
      .setProtectedHeader({ alg: "RS256", kid })
      .sign(privateKeyObj);

    // Fetch JWKS from Kong — wait for key to propagate first
    const { status, body: jwks } = await waitForJwks(
      request, `${proxyBaseUrl}/.well-known/jwks.json`, [kid]
    );
    expect(status).toBe(200);

    const jwk = jwks.keys.find((k: any) => k.kid === kid);
    expect(jwk).toBeDefined();

    // Verify the JWS against the JWK published by Kong (SC-004)
    const publicKeyObj = await importJWK({ ...jwk, alg: "RS256" }, "RS256");
    const { payload: verifiedPayload } = await compactVerify(jws, publicKeyObj);
    expect(verifiedPayload).toBeTruthy();
    logger.debug({ kid }, "SC-004 sign→publish→fetch→verify loop passed");
  });
});
