import react from "@vitejs/plugin-react";
import { defineConfig, type Plugin } from "vite";

const remoteFontImport =
  /@import url\(['"]https:\/\/fonts\.googleapis\.com\/css2\?family=Geist\+Mono[^'"]*['"]\);/;

function sanitizeBundledDependencies(): Plugin {
  return {
    name: "sanitize-bundled-dependencies",
    enforce: "pre",
    transform(source, id) {
      if (!id.endsWith("/dialkit/dist/styles.css")) return;
      return source.replace(remoteFontImport, "");
    },
    renderChunk(source) {
      return source.replaceAll("https://react.dev/errors/", "react-error-");
    },
  };
}

function supportBundledWebView(): Plugin {
  return {
    name: "support-bundled-web-view",
    apply: "build",
    transformIndexHtml(html) {
      return html.replace('<script type="module" crossorigin', '<script defer');
    },
  };
}

export default defineConfig({
  base: "./",
  build: {
    outDir: "../../VercelAnalyticsBar/Resources/ChartInspector",
    emptyOutDir: true,
    modulePreload: false,
    rollupOptions: {
      output: {
        format: "iife",
      },
    },
  },
  plugins: [sanitizeBundledDependencies(), react(), supportBundledWebView()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
  },
});
