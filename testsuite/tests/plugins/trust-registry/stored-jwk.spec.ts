import { test, expect, APIRequestContext } from '@playwright/test';
import { createPublicKey } from 'crypto';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { KONG_ADMIN_URL, provisionKong } from '../../../helpers/kong';
import { uniquePrefix, provisionPluginRoute, cleanupByPrefix, proxyGet, proxyRequest } from '../../../helpers/trust-registry';
const PREFIX = uniquePrefix('trust-registry');
const pem = (name: string) => readFileSync(resolve(__dirname, '../../../local/kong/fixtures/keys', name), 'utf8');
const rsa = createPublicKey(pem('rsa-2048.pub.pem')).export({ format: 'jwk' });
let n = 0;
async function set(request: APIRequestContext) {
    return (await provisionKong(request, `${KONG_ADMIN_URL}/key-sets`, { name: `${PREFIX}-set-${++n}` })).body;
}
async function key(request: APIRequestContext, keyset: any, fields: any = {}) {
    const kid = fields.jwk ? JSON.parse(fields.jwk).kid : `${PREFIX}-kid-${++n}`;
    return (await provisionKong(request, `${KONG_ADMIN_URL}/keys`, { name: kid, kid, set: { id: keyset.id }, jwk: JSON.stringify({ ...rsa, kid }), ...fields })).body;
}
async function published(request: APIRequestContext, routePath: string, method: 'GET' | 'POST' = 'GET') {
    const response = await proxyRequest(request, routePath, { method });
    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toMatch(/^application\/json/);
    return response.json();
}
test.beforeAll(async ({ request }) => cleanupByPrefix(request, PREFIX));
test.afterAll(async ({ request }) => cleanupByPrefix(request, PREFIX));
test.afterEach(async ({ request }) => cleanupByPrefix(request, PREFIX));
// [Verifies: trust-registry.stored-jwk.pass-through]
test('stored JWK preserves kid and enc use', async ({ request }) => {
    const a = await set(request);
    const jwk = { ...rsa, kid: `${PREFIX}-stored-kid`, use: 'enc' };
    await key(request, a, { jwk: JSON.stringify(jwk) });
    const route = await provisionPluginRoute(request, { prefix: PREFIX, config: { key_set: a.name } });
    expect(await published(request, route.routePath)).toEqual({ keys: [jwk] });
});
// [Verifies: trust-registry.stored-jwk.private-members]
test('stored JWK publishes public parameters only', async ({ request }) => {
    const a = await set(request);
    const privateJwk = require('crypto').createPrivateKey(pem('rsa-2048.pem')).export({ format: 'jwk' });
    const jwk = { ...privateJwk, kid: `${PREFIX}-private` };
    await key(request, a, { jwk: JSON.stringify(jwk) });
    const route = await provisionPluginRoute(request, { prefix: PREFIX, config: { key_set: a.name } });
    expect(await published(request, route.routePath)).toEqual({ keys: [{ ...rsa, kid: jwk.kid }] });
});
