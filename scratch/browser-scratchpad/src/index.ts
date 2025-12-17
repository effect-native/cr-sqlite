import { serve, file } from "bun";
import { resolve } from "path";
import index from "./index.html";

// Path to the browser-dist WASM files
const browserDistDir = resolve(import.meta.dir, "..", "..", "..", "zig", "browser-dist");

const server = serve({
  routes: {
    // Serve index.html for the root
    "/": index,

    // Serve CR-SQLite multi-tab worker files
    "/crsql-multitab.js": () => {
      const f = file(resolve(browserDistDir, "crsql-multitab.js"));
      return new Response(f, {
        headers: { "Content-Type": "application/javascript" },
      });
    },

    "/coordinator.js": () => {
      const f = file(resolve(browserDistDir, "coordinator.js"));
      return new Response(f, {
        headers: { "Content-Type": "application/javascript" },
      });
    },

    "/provider.js": () => {
      const f = file(resolve(browserDistDir, "provider.js"));
      return new Response(f, {
        headers: { "Content-Type": "application/javascript" },
      });
    },

    "/sql-wasm.js": () => {
      const f = file(resolve(browserDistDir, "sql-wasm.js"));
      return new Response(f, {
        headers: { "Content-Type": "application/javascript" },
      });
    },

    "/sql-wasm.wasm": () => {
      const f = file(resolve(browserDistDir, "sql-wasm.wasm"));
      return new Response(f, {
        headers: { "Content-Type": "application/wasm" },
      });
    },

    // Fallback: serve static files from src/ for the React app
    "/*": index,
  },

  development: process.env.NODE_ENV !== "production" && {
    // Enable browser hot reloading in development
    hmr: true,

    // Echo console logs from the browser to the server
    console: true,
  },
});

console.log(`
=== CR-SQLite Browser Demo ===

Server running at: ${server.url}

Open TWO browser tabs to this URL to test cross-tab sync!

Tab 1 and Tab 2 will share the same database through a SharedWorker.
Changes made in one tab will be visible in the other.

Press Ctrl+C to stop the server.
`);
