'use strict';

// 查寝助手 PWA Service Worker
// 策略：
// 1. 导航请求（HTML）网络优先，失败时回退缓存的应用外壳；
// 2. 同源静态资源（JS / 字体 / 图标 / assets）缓存优先，后台更新；
// 3. 跨域请求不拦截。
// CACHE_VERSION 由 tool\inject_sw_manifest.ps1 在每次构建时按 commit SHA
// 自动替换（必须随产物变化，否则浏览器逐字节比对认为 SW 未更新），旧缓存
// 会在 activate 时清理。

const CACHE_VERSION = 'dorm-inspection-dev';

// 注意：PRECACHE_URLS 由 tool\inject_sw_manifest.ps1 在 flutter build web 后
// 自动替换为 build\web 下全部产物的相对路径列表，请勿手改这一行。
const PRECACHE_URLS = ['./'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_VERSION);
      // 预缓存全部构建产物，单个失败不影响整体安装
      await Promise.all(
        PRECACHE_URLS.map((url) =>
          cache.add(new Request(url, { cache: 'reload' })).catch(() => null),
        ),
      );
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) => key !== CACHE_VERSION)
          .map((key) => caches.delete(key)),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // 导航请求：网络优先，离线回退应用外壳
  if (request.mode === 'navigate') {
    event.respondWith(
      (async () => {
        try {
          const fresh = await fetch(request);
          const cache = await caches.open(CACHE_VERSION);
          cache.put('./index.html', fresh.clone());
          return fresh;
        } catch (_) {
          const cached =
            (await caches.match('./index.html')) ||
            (await caches.match('./'));
          if (cached) return cached;
          throw new Error('offline and no cached shell');
        }
      })(),
    );
    return;
  }

  // 静态资源：缓存优先，后台更新
  event.respondWith(
    (async () => {
      const cached = await caches.match(request, {
        ignoreSearch: false,
      });
      const networkFetch = fetch(request)
        .then((response) => {
          if (response && response.status === 200) {
            const copy = response.clone();
            caches.open(CACHE_VERSION).then((cache) => {
              cache.put(request, copy);
            });
          }
          return response;
        })
        .catch(() => null);
      return cached || (await networkFetch) || Response.error();
    })(),
  );
});
