// ════════════════════════════════════════════════════
//  Voz do Anjo — Service Worker v2
//  Cache-first para o shell do app; network-first para
//  recursos remotos (Supabase, Google Fonts, etc.)
// ════════════════════════════════════════════════════

const CACHE_NAME = 'vozdoanjo-v2';

// Recursos do shell que devem sempre estar disponíveis offline
const SHELL_ASSETS = [
  '/',
  '/index.html',
  '/app.html',
  '/manifest.json',
  '/icon.png',
  '/icon-192.png',
  '/icon-512.png',
];

// ── Install: pré-cacheia o shell ────────────────────
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(SHELL_ASSETS))
  );
  self.skipWaiting();
});

// ── Activate: remove caches antigos ────────────────
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// ── Fetch: estratégia híbrida ───────────────────────
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Ignora requests não-GET e cross-origin (Supabase, CDN)
  if (request.method !== 'GET') return;
  if (url.origin !== self.location.origin) return;

  // Shell assets → cache-first
  if (SHELL_ASSETS.includes(url.pathname) || url.pathname === '/index.html') {
    event.respondWith(
      caches.match(request).then(cached => cached || fetch(request))
    );
    return;
  }

  // Demais assets → stale-while-revalidate
  event.respondWith(
    caches.open(CACHE_NAME).then(cache =>
      cache.match(request).then(cached => {
        const networkFetch = fetch(request).then(response => {
          if (response && response.status === 200 && response.type === 'basic') {
            cache.put(request, response.clone());
          }
          return response;
        }).catch(() => cached);
        return cached || networkFetch;
      })
    )
  );
});
