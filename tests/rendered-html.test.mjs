import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the Lume metadata and application shell", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Lume — leitor Markdown<\/title>/i);
  assert.match(
    html,
    /Um leitor Markdown local, rápido e bonito, com links wiki e zero distrações\./i,
  );
  assert.match(html, /manifest\.webmanifest/i);
  assert.match(html, /apple-mobile-web-app-title/i);
  assert.doesNotMatch(html, /codex-preview/i);
});

test("keeps web, PWA and desktop integrations wired", async () => {
  const [
    viewer,
    desktopBridge,
    manifestSource,
    serviceWorker,
    tauriSource,
    capabilitiesSource,
    styles,
  ] = await Promise.all([
      readFile(new URL("../app/MarkdownViewer.tsx", import.meta.url), "utf8"),
      readFile(new URL("../app/desktop-bridge.ts", import.meta.url), "utf8"),
      readFile(new URL("../public/manifest.webmanifest", import.meta.url), "utf8"),
      readFile(new URL("../public/sw.js", import.meta.url), "utf8"),
      readFile(
        new URL("../src-tauri/tauri.conf.json", import.meta.url),
        "utf8",
      ),
      readFile(
        new URL("../src-tauri/capabilities/default.json", import.meta.url),
        "utf8",
      ),
      readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    ]);

  const manifest = JSON.parse(manifestSource);
  const tauri = JSON.parse(tauriSource);
  const capabilities = JSON.parse(capabilitiesSource);
  const webExtensions = manifest.file_handlers[0].accept["text/markdown"];
  const desktopExtensions = tauri.bundle.fileAssociations[0].ext;

  assert.match(viewer, /showOpenFilePicker/);
  assert.match(viewer, /showDirectoryPicker/);
  assert.match(viewer, /serviceWorker\.register/);
  assert.match(desktopBridge, /open_markdown_path/);
  assert.match(desktopBridge, /fileAccessMode:\s*"scoped"/);
  assert.match(desktopBridge, /onDragDropEvent/);
  assert.match(desktopBridge, /startDragging/);
  assert.match(viewer, /lume-terminal-palette-v1/);
  assert.match(viewer, /lume-recent-documents-v2/);
  assert.match(viewer, /data-lume-search/);
  assert.match(viewer, /key === "f"/);
  assert.match(styles, /theme-sepia/);
  assert.match(styles, /theme-eink/);
  assert.match(styles, /theme-midnight/);
  assert.match(
    styles,
    /\.workspace\s*\{[^}]*position:\s*relative;/s,
  );
  assert.match(
    styles,
    /\.workspace\.left-closed \.document-bar\s*\{[^}]*padding-left:\s*58px;/s,
  );
  assert.match(
    styles,
    /\.workspace\.right-closed \.document-bar\s*\{[^}]*padding-right:\s*58px;/s,
  );
  assert.match(
    styles,
    /\.floating-panel-button\s*\{[^}]*top:\s*8px;/s,
  );
  assert.ok(
    capabilities.permissions.includes("core:window:allow-start-dragging"),
  );
  assert.deepEqual(webExtensions, [".md", ".markdown", ".mdown"]);
  assert.deepEqual(desktopExtensions, ["md", "markdown", "mdown"]);
  assert.match(serviceWorker, /const CACHE\s*=/);
});
