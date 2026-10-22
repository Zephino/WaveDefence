// Progressive Web App service worker for Wave Defence.
// Caches the full game (shell + wasm + pck) so installed phones can play offline
// after one successful online download. Incrementing CACHE_VERSION forces refresh.
/** @type {string} */
const CACHE_VERSION = '00.02.91';
/** @type {string} */
const CACHE_PREFIX = 'Wave Defence-sw-cache-';
const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;
/** @type {string} */
const OFFLINE_URL = 'index.offline.html';
/** @type {boolean} */
const ENSURE_CROSSORIGIN_ISOLATION_HEADERS = true;
// Shell + helpers cached on install.
/** @type {string[]} */
const CACHED_FILES = [
	'index.html',
	'index.js',
	'index.offline.html',
	'index.icon.png',
	'index.apple-touch-icon.png',
	'index.audio.worklet.js',
	'index.audio.position.worklet.js',
	'mobile_play.js',
];
// Game pack — also prefetched on install so offline play works on phones.
/** @type {string[]} */
const CACHEABLE_FILES = ['index.wasm', 'index.pck'];
const FULL_CACHE = CACHED_FILES.concat(CACHEABLE_FILES);

self.addEventListener('install', (event) => {
	// OFFLINE_FULL_CACHE: download shell + wasm + pck while online so airplane mode works later.
	event.waitUntil(
		caches
			.open(CACHE_NAME)
			.then((cache) => cache.addAll(FULL_CACHE))
			.then(() => self.skipWaiting())
	);
});

self.addEventListener('activate', (event) => {
	event.waitUntil(
		caches
			.keys()
			.then(function (keys) {
				return Promise.all(
					keys
						.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
						.map((key) => caches.delete(key))
				);
			})
			.then(function () {
				return 'navigationPreload' in self.registration
					? self.registration.navigationPreload.enable()
					: Promise.resolve();
			})
	);
});

/**
 * @param {Response} response
 * @returns {Response}
 */
function ensureCrossOriginIsolationHeaders(response) {
	if (
		response.headers.get('Cross-Origin-Embedder-Policy') === 'require-corp' &&
		response.headers.get('Cross-Origin-Opener-Policy') === 'same-origin'
	) {
		return response;
	}
	const crossOriginIsolatedHeaders = new Headers(response.headers);
	crossOriginIsolatedHeaders.set('Cross-Origin-Embedder-Policy', 'require-corp');
	crossOriginIsolatedHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
	return new Response(response.body, {
		status: response.status,
		statusText: response.statusText,
		headers: crossOriginIsolatedHeaders,
	});
}

/**
 * Basename without query/hash (handles cache-bust ?v=).
 * @param {string} url
 * @returns {string}
 */
function localName(url) {
	try {
		const path = new URL(url, self.location.href).pathname;
		const parts = path.split('/');
		return parts[parts.length - 1] || '';
	} catch (e) {
		return '';
	}
}

/**
 * @param {Cache} cache
 * @param {Request} request
 * @returns {Promise<Response|undefined>}
 */
async function matchIgnoreSearch(cache, request) {
	let hit = await cache.match(request, { ignoreSearch: true });
	if (hit) {
		return hit;
	}
	const name = localName(request.url);
	if (name && FULL_CACHE.indexOf(name) >= 0) {
		hit = await cache.match(name);
		if (hit) {
			return hit;
		}
		hit = await cache.match('./' + name);
	}
	return hit;
}

/**
 * @param {FetchEvent} event
 * @param {Cache} cache
 * @param {boolean} isCacheable
 * @returns {Promise<Response>}
 */
async function fetchAndCache(event, cache, isCacheable) {
	/** @type {Response} */
	let response = await event.preloadResponse;
	if (response == null) {
		response = await self.fetch(event.request);
	}
	if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
		response = ensureCrossOriginIsolationHeaders(response);
	}
	if (isCacheable) {
		cache.put(event.request, response.clone());
		const name = localName(event.request.url);
		if (name && FULL_CACHE.indexOf(name) >= 0) {
			cache.put(name, response.clone());
		}
	}
	return response;
}

self.addEventListener('fetch', (event) => {
	const isNavigate = event.request.mode === 'navigate';
	const name = localName(event.request.url);
	const isCacheable = FULL_CACHE.indexOf(name) >= 0 || isNavigate;
	if (isNavigate || isCacheable) {
		event.respondWith(
			(async () => {
				const cache = await caches.open(CACHE_NAME);
				if (isNavigate) {
					// NETWORK_FIRST_HTML: prefer network so Update app works; fall back to cached game offline.
					try {
						const response = await fetchAndCache(event, cache, true);
						return response;
					} catch (e) {
						console.error('Network error: ', e); // eslint-disable-line no-console
						const cachedNav = await matchIgnoreSearch(cache, event.request);
						if (cachedNav) {
							return ENSURE_CROSSORIGIN_ISOLATION_HEADERS
								? ensureCrossOriginIsolationHeaders(cachedNav)
								: cachedNav;
						}
						const cachedIndex = await cache.match('index.html');
						if (cachedIndex) {
							return ENSURE_CROSSORIGIN_ISOLATION_HEADERS
								? ensureCrossOriginIsolationHeaders(cachedIndex)
								: cachedIndex;
						}
						return caches.match(OFFLINE_URL);
					}
				}
				let cached = await matchIgnoreSearch(cache, event.request);
				if (cached != null) {
					if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
						cached = ensureCrossOriginIsolationHeaders(cached);
					}
					return cached;
				}
				try {
					return await fetchAndCache(event, cache, isCacheable);
				} catch (e) {
					console.error('Network error: ', e); // eslint-disable-line no-console
					return caches.match(OFFLINE_URL);
				}
			})()
		);
	} else if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
		event.respondWith(
			(async () => {
				let response = await fetch(event.request);
				return ensureCrossOriginIsolationHeaders(response);
			})()
		);
	}
});

self.addEventListener('message', (event) => {
	if (event.origin !== self.origin) {
		return;
	}
	const id = event.source.id || '';
	const msg = event.data || '';
	self.clients.get(id).then(function (client) {
		if (!client) {
			return;
		}
		if (msg === 'claim') {
			self.skipWaiting().then(() => self.clients.claim());
		} else if (msg === 'clear') {
			caches.delete(CACHE_NAME);
		} else if (msg === 'update') {
			self
				.skipWaiting()
				.then(() => self.clients.claim())
				.then(() => self.clients.matchAll())
				.then((all) => all.forEach((c) => c.navigate(c.url)));
		}
	});
});
