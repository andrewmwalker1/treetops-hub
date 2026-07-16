import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  // Custom domain (hub.treetops.co.uk) serves from the root, so no subpath needed.
  base: "/",
});
