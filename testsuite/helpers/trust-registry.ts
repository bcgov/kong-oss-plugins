import { APIRequestContext } from '@playwright/test';
import { KONG_ADMIN_URL, provisionKong, waitForRouteReady, uniquePrefix, proxyGet, proxyRequest } from './kong';
import { upstreamServiceDefaults } from './upstream';
export { uniquePrefix, proxyGet, proxyRequest };
let sequence = 0;
export async function provisionPluginRoute(request: APIRequestContext, options: {
    prefix: string;
    config: {
        key_set?: string;
    };
    serviceTags?: string[];
    capture?: string;
}) {
    const n = ++sequence;
    const base = `/${options.prefix}-${n}`;
    const routePath = options.capture ? `${base}/${options.capture}` : base;
    const service = await provisionKong(request, `${KONG_ADMIN_URL}/services`, { name: `${options.prefix}-svc-${n}`, ...upstreamServiceDefaults, tags: options.serviceTags });
    const route = await provisionKong(request, `${KONG_ADMIN_URL}/routes`, { name: `${options.prefix}-rt-${n}`, hosts: ['kong.localtest.me'], paths: [options.capture ? `~${base}/(?<key_set>[^/]+)` : base], strip_path: true, service: { id: service.body.id } });
    const plugin = await provisionKong(request, `${KONG_ADMIN_URL}/plugins`, { name: 'trust-registry', route: { id: route.body.id }, config: options.config });
    await waitForRouteReady(request, routePath, { timeoutMs: 30000, consecutive: 9 });
    // Routes and attached plugins may reach a DP in separate updates.
    // Wait for JWKS so an upstream 200 cannot satisfy plugin readiness.
    let consecutive = 0;
    const ready = await proxyGet(request, routePath, {
        attempts: 40,
        shouldRetry: async response => {
            const body = await response.json();
            consecutive = Object.prototype.hasOwnProperty.call(body, 'keys') ? consecutive + 1 : 0;
            return consecutive < 9;
        },
    });
    if (consecutive < 9 || !Object.prototype.hasOwnProperty.call(await ready.json(), 'keys')) {
        throw new Error('trust-registry plugin has not propagated to the route');
    }
    return { routePath, serviceId: service.body.id, routeId: route.body.id, pluginId: plugin.body.id };
}
export async function cleanupByPrefix(request: APIRequestContext, prefix: string) {
    for (const endpoint of ['routes', 'services', 'keys', 'key-sets']) {
        let next: string | null = `${KONG_ADMIN_URL}/${endpoint}?size=1000`;
        while (next) {
            const response = await request.get(next);
            if (!response.ok())
                throw new Error(`cleanup ${endpoint}: ${response.status()} ${await response.text()}`);
            const page = await response.json();
            for (const entity of page.data) {
                if (entity.name?.startsWith(prefix) || entity.kid?.startsWith(prefix)) {
                    const deleted = await request.delete(`${KONG_ADMIN_URL}/${endpoint}/${entity.id}`);
                    if (!deleted.ok())
                        throw new Error(`delete ${endpoint}: ${deleted.status()}`);
                }
            }
            next = page.next ? new URL(page.next, KONG_ADMIN_URL).href : null;
        }
    }
}
