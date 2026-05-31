import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";
import path from "node:path";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: ["favicon.svg", "apple-touch-icon.png"],
      manifest: {
        name: "NizKhata — Every rupee, accounted for.",
        short_name: "NizKhata",
        description:
          "Shared, multi-workspace accounting: multi-line transactions, accounts, contacts, debts, dues and financial-year tax summaries with role-based access.",
        theme_color: "#7c3aed",
        background_color: "#0b1120",
        display: "standalone",
        orientation: "portrait",
        start_url: "/",
        scope: "/",
        icons: [
          { src: "pwa-192x192.png", sizes: "192x192", type: "image/png" },
          { src: "pwa-512x512.png", sizes: "512x512", type: "image/png" },
          {
            src: "maskable-512x512.png",
            sizes: "512x512",
            type: "image/png",
            purpose: "maskable",
          },
        ],
      },
      workbox: {
        globPatterns: ["**/*.{js,css,html,svg,png,woff2}"],
        // Don't precache the SPA shell against Firestore/Google API calls.
        navigateFallbackDenylist: [/^\/__/, /firestore/, /googleapis/],
        runtimeCaching: [
          {
            // App static assets — cache first.
            urlPattern: ({ request }) =>
              ["style", "script", "worker", "font", "image"].includes(
                request.destination,
              ),
            handler: "StaleWhileRevalidate",
            options: { cacheName: "assets" },
          },
        ],
      },
      devOptions: {
        enabled: false,
      },
    }),
  ],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
    },
  },
  build: {
    rollupOptions: {
      output: {
        // Split big vendor libs into their own long-lived chunks so they cache
        // independently of app code (which changes far more often). recharts is
        // only used by Reports/Dashboard, so isolating it keeps it cacheable.
        manualChunks: {
          firebase: ["firebase/app", "firebase/auth", "firebase/firestore"],
          react: ["react", "react-dom", "react-router-dom"],
          charts: ["recharts"],
        },
      },
    },
    // App chunks are well under this; the limit only silenced the old warning
    // for the single monolithic bundle, which no longer exists.
    chunkSizeWarningLimit: 800,
  },
});
