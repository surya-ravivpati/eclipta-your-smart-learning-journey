import { defineConfig } from "vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import { nitro } from "nitro/vite";
import viteReact from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import tsConfigPaths from "vite-tsconfig-paths";

// Vanilla TanStack Start config — no Lovable wrapper. The server build is
// handled by nitro; the deploy target is Vercel (nitro also auto-detects the
// `vercel` preset from the VERCEL env var during a Vercel build, but we set it
// explicitly so a local `vite build` produces the same `.vercel/output`).
//
// Plugin order matters: tsConfigPaths and tailwind first, then tanstackStart,
// then nitro, then the React plugin (must come after tanstackStart).
export default defineConfig({
  plugins: [
    tsConfigPaths(),
    tailwindcss(),
    tanstackStart(),
    nitro({
      preset: "vercel",
      compatibilityDate: "2025-09-24",
    }),
    viteReact(),
  ],
  // Guard against duplicate React copies from transitive deps.
  resolve: {
    dedupe: ["react", "react-dom", "@tanstack/react-router"],
  },
  server: {
    port: 5173,
  },
});
