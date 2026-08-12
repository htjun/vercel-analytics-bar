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

export default defineConfig({
  base: "./",
  build: {
    outDir: "../../VercelAnalyticsBar/Resources/ChartInspector",
    emptyOutDir: true,
  },
  plugins: [sanitizeBundledDependencies(), react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
  },
});
