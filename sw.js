import { precacheAndRoute, cleanupOutdatedCaches } from "workbox-precaching";
import { clientsClaim } from "workbox-core";
import { registerRoute } from "workbox-routing";
import { StaleWhileRevalidate } from "workbox-strategies";

self.skipWaiting();
clientsClaim();
cleanupOutdatedCaches();

// vite-plugin-pwa injects the list of built files to precache here at build time.
precacheAndRoute(self.__WB_MANIFEST);

// Offline support: cache every piece of app content (notices, emergency
// contacts, directory, forms, etc — all fetched from the same Supabase
// `app_data` table) as it's loaded. Serves the last-known copy instantly,
// then quietly refreshes in the background if there's a connection —
// so it's fast when online and still works when there isn't a signal.
// Since the app loads everything upfront on open (not lazily per-screen),
// the very first successful launch primes the cache for the whole app.
registerRoute(
  ({ url }) => url.pathname === "/rest/v1/app_data",
  new StaleWhileRevalidate({ cacheName: "app-data-cache" })
);

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { title: "Tree Tops Hub", body: event.data ? event.data.text() : "" };
  }
  const title = data.title || "Tree Tops Hub";
  const options = {
    body: data.body || "",
    icon: "/icon-192.png",
    badge: "/icon-192.png",
    tag: data.tag || data.noticeId || undefined,
    data: { url: data.url || (data.noticeId ? `/?notice=${data.noticeId}` : "/") },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const targetUrl = event.notification.data?.url || "/";
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if (client.url.includes(targetUrl.split("?")[0]) && "focus" in client) {
          client.navigate(targetUrl);
          return client.focus();
        }
      }
      return self.clients.openWindow(targetUrl);
    })
  );
});
