import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

export default defineConfig({
  // Custom domain (hub.treetops.co.uk) serves from the root, so no subpath needed.
  base: "/",
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      strategies: "injectManifest",
      srcDir: ".",
      filename: "sw.js",
      injectManifest: {
        globPatterns: ["**/*.{js,css,html,png,svg,ico}"],
      },
      includeAssets: ["favicon-32.png", "apple-touch-icon.png"],
      manifest: {
        name: "Tree Tops Hub",
        short_name: "Tree Tops",
        description: "The guest hub for Tree Tops Caravan Park — notices, forms and park info.",
        start_url: "/",
        scope: "/",
        display: "standalone",
        background_color: "#F5F0E3",
        theme_color: "#0B5C38",
        orientation: "portrait",
        icons: [
          { src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
          { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
          { src: "/icon-512-maskable.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
    }),
  ],
});
