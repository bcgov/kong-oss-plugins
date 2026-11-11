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
    const kid = `${PREFIX}-kid-${++n}`;
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
// [Verifies: trust-registry.keyset-selection.all-keys]
test('enumerates keys from two sets', async ({ request }) => {
    const a = await key(request, await set(request));
    const b = await key(request, await set(request));
    const route = await provisionPluginRoute(request, { prefix: PREFIX, config: {} });
    expect((await published(request, route.routePath)).keys).toEqual(expect.arrayContaining([JSON.parse(a.jwk), JSON.parse(b.jwk)]));
});
// [Verifies: trust-registry.keyset-selection.configured]
test('selects only configured set', async ({ request }) => {
    const a = await set(request);
    const ka = await key(request, a);
    await key(request, await set(request));
    const route = await provisionPluginRoute(request, { prefix: PREFIX, config: { key_set: a.name } });
    expect(await published(request, route.routePath)).toEqual({ keys: [JSON.parse(ka.jwk)] });
});
// [Verifies: trust-registry.keyset-selection.capture-precedence]
test('capture takes precedence', async ({ request }) => {
    const a = await set(request);
    const ka = await key(request, a);
    const b = await set(request);
    await key(request, b);
    const route = await provisionPluginRoute(request, { prefix: PREFIX, config: { key_set: b.name }, capture: a.name });
    expect(await published(request, route.routePath)).toEqual({ keys: [JSON.parse(ka.jwk)] });
});
// [Verifies: trust-registry.keyset-selection.missing-capture]
test('unknown capture does not fall back', async ({ request }) => {
    const a = await set(request);
    await key(request, a);
    const route = await provisionPluginRoute(request, { prefix: PREFIX, config: { key_set: a.name }, capture: a.name });
    const response = await proxyGet(request, route.routePath.replace(a.name, `${PREFIX}-unknown`), { attempts: 1 });
    expect(response.status()).toBe(404);
    expect(await response.json()).toEqual({ message: 'Key set not found' });
});
// [Verifies: trust-registry.keyset-selection.missing-config]
test('unknown configured set returns 404', async ({ request }) => {
    const a = await set(request);
    const route = await provisionPluginRoute(request, { prefix: PREFIX, config: { key_set: a.name } });
    const patch = await request.patch(`${KONG_ADMIN_URL}/plugins/${route.pluginId}`, { data: { config: { key_set: `${PREFIX}-unknown` } } });
    expect(patch.ok()).toBeTruthy();
    await expect.poll(async () => {
        const response = await proxyGet(request, route.routePath, { attempts: 1 });
        return { status: response.status(), body: await response.json() };
    }, { timeout: 30000 }).toEqual({ status: 404, body: { message: 'Key set not found' } });
});
// [Verifies: trust-registry.keyset-selection.empty-set]
test('empty set serializes keys as object', async ({ request }) => {
    const a = await set(request);
    const route = await provisionPluginRoute(request, { prefix: PREFIX, config: { key_set: a.name } });
    expect(await published(request, route.routePath)).toEqual({ keys: {} });
});
// [Verifies: trust-registry.keyset-selection.post-request]
test('POST returns same JWKS as GET', async ({ request }) => {
    const a = await set(request);
    const k = await key(request, a);
    const route = await provisionPluginRoute(request, { prefix: PREFIX, config: { key_set: a.name } });
    expect(await published(request, route.routePath)).toEqual({ keys: [JSON.parse(k.jwk)] });
    expect(await published(request, route.routePath, 'POST')).toEqual({ keys: [JSON.parse(k.jwk)] });
});
