// Работа без интернета.
//
// Стратегия «сначала сеть, потом кэш»: при наличии интернета
// всегда загружается свежая версия (и сохраняется в кэш), без
// интернета приложение открывается из кэша. Данные пользователя
// хранятся отдельно (localStorage) и этим файлом не затрагиваются.

const CACHE = 'moy-budget-v1';
const NETWORK_TIMEOUT_MS = 4000;

const CORE = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(CORE))
      .catch(() => {})
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))),
      )
      .then(() => self.clients.claim()),
  );
});

// Кэшируем свои файлы и шрифты Google (их подгружает Flutter).
function cacheable(url) {
  return (
    url.origin === self.location.origin ||
    url.hostname === 'fonts.gstatic.com' ||
    url.hostname === 'www.gstatic.com'
  );
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (!cacheable(url)) return;

  event.respondWith(networkFirst(request));
});

async function networkFirst(request) {
  const cache = await caches.open(CACHE);

  const network = fetch(request).then((response) => {
    if (response && (response.ok || response.type === 'opaque')) {
      cache.put(request, response.clone());
    }
    return response;
  });

  // Если сеть медленная — отдаём из кэша, а свежая версия
  // всё равно сохранится к следующему запуску.
  const timeout = new Promise((resolve) =>
    setTimeout(resolve, NETWORK_TIMEOUT_MS, null),
  );

  try {
    const fast = await Promise.race([network, timeout]);
    if (fast) return fast;
    const cached = await cache.match(request, { ignoreSearch: true });
    return cached || (await network);
  } catch (e) {
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;
    if (request.mode === 'navigate') {
      const index = await cache.match('index.html');
      if (index) return index;
    }
    throw e;
  }
}
