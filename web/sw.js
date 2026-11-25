// Офлайн-кэш браузерной версии (для установки «на экран Домой»).
// Страница берётся из сети, чтобы приходили обновления; без интернета — из кэша.
const CACHE = 'kozyrnaya-arena-1.4.0';
const FILES = ['./', './index.html', './babylon.js', './peerjs.min.js', './icons.js', './manifest.webmanifest',
  './icon-192.png', './icon-512.png', './apple-touch-icon.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;
  const save = res => { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return res; };
  if (e.request.mode === 'navigate' || url.pathname.endsWith('/index.html')) {
    e.respondWith(fetch(e.request).then(save)
      .catch(() => caches.match(e.request).then(r => r || caches.match('./index.html'))));
    return;
  }
  e.respondWith(caches.match(e.request).then(r => r || fetch(e.request).then(save)));
});
