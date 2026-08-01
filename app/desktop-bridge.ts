import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { openUrl } from "@tauri-apps/plugin-opener";

export type DesktopFileEntry = {
  content: string;
  lastModified: number;
  name: string;
  path: string;
  sourcePath: string;
};

export type DesktopOpenResult = {
  files: DesktopFileEntry[];
  kind: "file" | "folder";
  name: string;
};

export type DesktopRefreshResult = {
  content: string;
  lastModified: number;
};

export function isDesktopApp() {
  return isTauri();
}

export function loadDesktopPath(path: string) {
  return invoke<DesktopOpenResult>("open_markdown_path", { path });
}

export function refreshDesktopFile(path: string) {
  return invoke<DesktopRefreshResult>("refresh_markdown_file", { path });
}

export function markDesktopFrontendReady() {
  return invoke<string[]>("frontend_ready");
}

export function chooseDesktopFile() {
  return openDialog({
    directory: false,
    fileAccessMode: "scoped",
    filters: [
      {
        extensions: ["md", "markdown", "mdown"],
        name: "Markdown",
      },
    ],
    multiple: false,
    title: "Abrir arquivo Markdown",
  });
}

export function chooseDesktopFolder() {
  return openDialog({
    directory: true,
    fileAccessMode: "scoped",
    multiple: false,
    recursive: true,
    title: "Abrir pasta de Markdown",
  });
}

export function openDesktopUrl(url: string) {
  return openUrl(url);
}

export function startDesktopWindowDrag() {
  return getCurrentWindow().startDragging();
}

export function listenForDesktopOpen(
  handler: (paths: string[]) => void,
): Promise<UnlistenFn> {
  return listen<string[]>("open-markdown-files", ({ payload }) => {
    handler(payload);
  });
}

export function listenForDesktopDrop(
  handler: (event: { paths?: string[]; type: string }) => void,
): Promise<UnlistenFn> {
  return getCurrentWebview().onDragDropEvent(({ payload }) => {
    handler(payload);
  });
}
