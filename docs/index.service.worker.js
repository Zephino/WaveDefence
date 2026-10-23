// Progressive Web App service worker for Wave Defence.
// After one online download, phones can open and play with no internet.
// Incrementing CACHE_VERSION forces a refresh when online.
/** @type {string} */
const CACHE_VERSION = '00.02.94';
/** @type {string} */
const CACHE_PREFIX = 'Wave Defence-sw-cache-';
const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;
/** @type {string} */
const OFFLINE_URL = 'index.offline.html';
/** @type {boolean} */
const ENSURE_CROSSORIGIN_ISOLATION_HEADERS = true;

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
	'index.manifest.json',
	'index.192x192.png',
];
/** @type {string[]} */
const CACHEABLE_FILES = ['index.wasm', 'index.pck'];
/** @type {string[]} */
const MUSIC_FILES = [
	'music/web_loop_01.wav',
	'music/web_loop_02.wav',
	'music/web_loop_03.wav',
	'music/web_loop_04.wav',
	'music/web_loop_05.wav',
];
const FULL_CACHE = CACHED_FILES.concat(CACHEABLE_FILES).concat(MUSIC_FILES);

/**
 * Cache each URL on its own so one failure (e.g. huge wasm on flaky LTE) does not abort the rest.
 * @param {Cache} cache
 * @param {string[]} urls
 */
async function precacheUrls(cache, urls) {
	await Promise.all(
		urls.map(async (url) => {
			try {
				const res = await fetch(url, { cache: 'reload' });
				if (res && res.ok) {
					await cache.put(url, res.clone());
				}
			} catch (e) {
				console.warn('SW precache failed:', url, e); // eslint-disable-line no-console
			}
		})
	);
}

self.addEventListener('install', (event) => {
	// OFFLINE_FULL_CACHE: download shell + wasm + pck + music while online.
	event.waitUntil(
		caches
			.open(CACHE_NAME)
			.then((cache) => precacheUrls(cache, FULL_CACHE))
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
			.then(function () {
				return self.clients.claim();
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
 * Path relative to the SW scope (handles /WaveDefence/… and ?v= cache bust).
 * @param {string} url
 * @returns {string}
 */
function scopedPath(url) {
	try {
		const u = new URL(url, self.location.href);
		const scopeUrl = new URL(self.registration.scope);
		let path = u.pathname;
		if (path.startsWith(scopeUrl.pathname)) {
			path = path.slice(scopeUrl.pathname.length);
		}
		return path.replace(/^\//, '');
	} catch (e) {
		return '';
	}
}

/**
 * @param {string} url
 * @returns {string}
 */
function localName(url) {
	const path = scopedPath(url);
	const parts = path.split('/');
	return parts[parts.length - 1] || '';
}

/**
 * @param {string} url
 * @returns {boolean}
 */
function isFullCacheUrl(url) {
	const path = scopedPath(url);
	const name = localName(url);
	if (FULL_CACHE.indexOf(path) >= 0) {
		return true;
	}
	if (FULL_CACHE.indexOf(name) >= 0) {
		return true;
	}
	if (path.indexOf('music/') === 0 && name.indexOf('web_loop_') === 0) {
		return true;
	}
	return false;
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
	const path = scopedPath(request.url);
	const name = localName(request.url);
	const keys = [path, name, './' + path, './' + name].filter(Boolean);
	for (let i = 0; i < keys.length; i++) {
		hit = await cache.match(keys[i]);
		if (hit) {
			return hit;
		}
	}
	return undefined;
}

/**
 * @param {Response|undefined} cached
 * @returns {Response|undefined}
 */
function withIsolation(cached) {
	if (!cached) {
		return cached;
	}
	return ENSURE_CROSSORIGIN_ISOLATION_HEADERS
		? ensureCrossOriginIsolationHeaders(cached)
		: cached;
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
		const path = scopedPath(event.request.url);
		const name = localName(event.request.url);
		if (path) {
			cache.put(path, response.clone());
		}
		if (name && name !== path) {
			cache.put(name, response.clone());
		}
	}
	return response;
}

/**
 * Serve the cached game shell when offline (do not wait for a network timeout).
 * @param {Cache} cache
 * @param {Request} request
 * @returns {Promise<Response>}
 */
async function cachedGameOrOfflinePage(cache, request) {
	const cachedNav = await matchIgnoreSearch(cache, request);
	if (cachedNav) {
		return withIsolation(cachedNav);
	}
	const cachedIndex = await cache.match('index.html');
	if (cachedIndex) {
		return withIsolation(cachedIndex);
	}
	const offline = await caches.match(OFFLINE_URL);
	return offline || Response.error();
}

self.addEventListener('fetch', (event) => {
	const isNavigate = event.request.mode === 'navigate';
	const cacheableAsset = isFullCacheUrl(event.request.url);
	if (isNavigate || cacheableAsset) {
		event.respondWith(
			(async () => {
				const cache = await caches.open(CACHE_NAME);
				const offline = typeof self.navigator !== 'undefined' && self.navigator.onLine === false;

				if (isNavigate) {
					// OFFLINE_CACHE_FIRST: no internet → open cached game immediately.
					if (offline) {
						return cachedGameOrOfflinePage(cache, event.request);
					}
					// NETWORK_FIRST_HTML: online so Update app / new builds still land.
					try {
						return await fetchAndCache(event, cache, true);
					} catch (e) {
						console.error('Network error: ', e); // eslint-disable-line no-console
						return cachedGameOrOfflinePage(cache, event.request);
					}
				}

				let cached = await matchIgnoreSearch(cache, event.request);
				if (cached != null) {
					return withIsolation(cached);
				}
				if (offline) {
					return caches.match(OFFLINE_URL);
				}
				try {
					return await fetchAndCache(event, cache, true);
				} catch (e) {
					console.error('Network error: ', e); // eslint-disable-line no-console
					return caches.match(OFFLINE_URL);
				}
			})()
		);
		return;
	}

	// Same-origin assets we did not list: try cache, then network (never hang offline).
	if (event.request.url.startsWith(self.registration.scope)) {
		event.respondWith(
			(async () => {
				const cache = await caches.open(CACHE_NAME);
				const cached = await matchIgnoreSearch(cache, event.request);
				if (cached) {
					return withIsolation(cached);
				}
				if (typeof self.navigator !== 'undefined' && self.navigator.onLine === false) {
					return Response.error();
				}
				try {
					let response = await fetch(event.request);
					if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
						response = ensureCrossOriginIsolationHeaders(response);
					}
					return response;
				} catch (e) {
					return Response.error();
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
