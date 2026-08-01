"use client";

import DOMPurify from "dompurify";
import {
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronDown,
  ChevronRight,
  ChevronUp,
  Clock3,
  File,
  FileText,
  FolderOpen,
  List,
  Maximize2,
  Minus,
  Moon,
  PanelLeftClose,
  PanelLeftOpen,
  Palette,
  Plus,
  RotateCcw,
  Search,
  Settings2,
  Sun,
  TerminalSquare,
  X,
} from "lucide-react";
import { marked } from "marked";
import {
  ChangeEvent,
  DragEvent,
  MouseEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  chooseDesktopFile,
  chooseDesktopFolder,
  isDesktopApp,
  listenForDesktopDrop,
  listenForDesktopOpen,
  loadDesktopPath,
  markDesktopFrontendReady,
  openDesktopUrl,
  refreshDesktopFile,
  startDesktopWindowDrag,
  type DesktopOpenResult,
} from "./desktop-bridge";

type Theme =
  | "paper"
  | "sepia"
  | "eink"
  | "night"
  | "midnight"
  | "terminal";

type RecentDocument = {
  kind: "file" | "folder";
  lastOpened: number;
  name: string;
  path: string;
};

type TerminalPalette = {
  accent: string;
  background: string;
  heading1: string;
  heading2: string;
  heading3: string;
  muted: string;
  surface: string;
  text: string;
};

type OutlineItem = {
  depth: number;
  id: string;
  label: string;
};

type FileEntry = {
  content?: string;
  handle?: FileSystemFileHandle;
  lastModified?: number;
  name: string;
  path: string;
  sourcePath?: string;
};

declare global {
  interface Window {
    launchQueue?: {
      setConsumer: (
        consumer: (params: { files: FileSystemFileHandle[] }) => void,
      ) => void;
    };
    showDirectoryPicker?: () => Promise<FileSystemDirectoryHandle>;
    showOpenFilePicker?: (options?: {
      multiple?: boolean;
      types?: Array<{
        accept: Record<string, string[]>;
        description: string;
      }>;
    }) => Promise<FileSystemFileHandle[]>;
  }
}

const DEMO_FILES: FileEntry[] = [
  {
    name: "Boas-vindas.md",
    path: "Boas-vindas.md",
    content: `---
status: pronto para ler
tipo: demonstração local
---

# Um lugar calmo para seus Markdown.

O **Lume** abre arquivos \`.md\` sem transformar uma leitura rápida em um projeto. Seus arquivos continuam no seu computador — sem conta, upload ou nuvem.

> [!NOTE]
> Abra um arquivo, solte-o nesta janela ou escolha uma pasta inteira. O Lume acompanha alterações salvas em outros apps automaticamente.

## Feito para leitura

- Markdown com tabelas, listas de tarefas e blocos de código
- Sumário que acompanha o documento
- Links wiki no formato \`[[Links wiki]]\`
- Busca dentro do documento e seis temas de leitura

| Ideia | No Lume |
| --- | --- |
| Abrir rápido | Um gesto, sem workspace |
| Navegar notas | Links wiki + histórico |
| Manter leve | Leitura primeiro, edição fora |

## Um exemplo de código

\`\`\`typescript
const leitura = {
  distrações: 0,
  arquivos: "locais",
  tema: "do seu jeito",
};
\`\`\`

Continue em [[Links wiki|como os links funcionam]] ou veja [[Atalhos]].`,
  },
  {
    name: "Links wiki.md",
    path: "Links wiki.md",
    content: `# Links wiki

Links com colchetes duplos viram navegação local:

- \`[[Nome da nota]]\`
- \`[[Nome da nota|texto alternativo]]\`
- \`[[Nome da nota#Seção]]\`

Links Markdown tradicionais como \`[Atalhos](Atalhos.md)\` também funcionam. O Lume procura primeiro ao lado do arquivo atual e depois pelo nome dentro da pasta aberta.

## Sem aprisionar seus arquivos

O conteúdo permanece Markdown comum. Nenhum banco de dados, formato proprietário ou metadado obrigatório é inserido.

Voltar para [[Boas-vindas]].`,
  },
  {
    name: "Atalhos.md",
    path: "Atalhos.md",
    content: `# Atalhos

| Atalho | Ação |
| --- | --- |
| \`⌘ K\` | Abrir o navegador rápido |
| \`⌘ F\` | Buscar dentro do documento |
| \`⌘ G\` / \`⌘ ⇧ G\` | Próxima ocorrência / anterior |
| \`⌘ O\` | Abrir um arquivo |
| \`⌘ ⇧ O\` | Abrir uma pasta |
| \`⌘ +\` / \`⌘ -\` | Ajustar o texto |
| \`⌘ 0\` | Restaurar tamanho |
| \`⌘ P\` | Imprimir ou salvar em PDF |
| \`Esc\` | Fechar busca |

## Dica

Você pode arrastar qualquer arquivo \`.md\` para a janela. Se abriu uma pasta, use os links \`[[wiki]]\` para passear entre as notas.

Voltar para [[Boas-vindas]].`,
  },
];

const themeOptions: Array<{
  description: string;
  icon: typeof Sun;
  label: string;
  quick: boolean;
  swatches: [string, string, string];
  value: Theme;
}> = [
  {
    description: "Claro, editorial e neutro.",
    icon: Sun,
    label: "Papel",
    quick: true,
    swatches: ["#fbfaf6", "#252521", "#b84b2c"],
    value: "paper",
  },
  {
    description: "Calor suave dos leitores de e-book.",
    icon: Sun,
    label: "Sépia",
    quick: false,
    swatches: ["#f3ead9", "#3f3328", "#9a6037"],
    value: "sepia",
  },
  {
    description: "Cinza de papel e contraste confortável.",
    icon: FileText,
    label: "E-ink",
    quick: false,
    swatches: ["#eeeeea", "#20211f", "#476457"],
    value: "eink",
  },
  {
    description: "Azul profundo para leitura noturna.",
    icon: Moon,
    label: "Noite",
    quick: true,
    swatches: ["#121620", "#e8eaf2", "#8ea5ff"],
    value: "night",
  },
  {
    description: "Carvão escuro com acentos âmbar.",
    icon: Moon,
    label: "Meia-noite",
    quick: false,
    swatches: ["#101115", "#e6e1d8", "#d5a35e"],
    value: "midnight",
  },
  {
    description: "Mono verde e paleta totalmente ajustável.",
    icon: TerminalSquare,
    label: "Terminal",
    quick: true,
    swatches: ["#0b0f0c", "#d9f2de", "#63d483"],
    value: "terminal",
  },
];

const RECENT_DOCUMENTS_STORAGE_KEY = "lume-recent-documents-v2";
const TERMINAL_PALETTE_STORAGE_KEY = "lume-terminal-palette-v1";
const DEFAULT_TERMINAL_PALETTE: TerminalPalette = {
  accent: "#63d483",
  background: "#0b0f0c",
  heading1: "#f2f7d7",
  heading2: "#7ee787",
  heading3: "#79c0ff",
  muted: "#7f9f87",
  surface: "#111812",
  text: "#d9f2de",
};

const terminalColorFields: Array<{
  key: keyof TerminalPalette;
  label: string;
}> = [
  { key: "background", label: "Fundo" },
  { key: "surface", label: "Painéis" },
  { key: "text", label: "Texto" },
  { key: "muted", label: "Texto secundário" },
  { key: "accent", label: "Acento" },
  { key: "heading1", label: "Título H1" },
  { key: "heading2", label: "Título H2" },
  { key: "heading3", label: "Título H3" },
];

function loadTerminalPalette(): TerminalPalette {
  if (typeof window === "undefined") return DEFAULT_TERMINAL_PALETTE;
  try {
    const stored = JSON.parse(
      localStorage.getItem(TERMINAL_PALETTE_STORAGE_KEY) || "{}",
    ) as Partial<TerminalPalette>;
    return Object.fromEntries(
      Object.entries(DEFAULT_TERMINAL_PALETTE).map(([key, fallback]) => [
        key,
        /^#[0-9a-f]{6}$/i.test(stored[key as keyof TerminalPalette] || "")
          ? stored[key as keyof TerminalPalette]
          : fallback,
      ]),
    ) as TerminalPalette;
  } catch {
    return DEFAULT_TERMINAL_PALETTE;
  }
}

function loadRecentDocuments(): RecentDocument[] {
  if (typeof window === "undefined") return [];
  try {
    const stored = JSON.parse(
      localStorage.getItem(RECENT_DOCUMENTS_STORAGE_KEY) || "[]",
    ) as RecentDocument[];
    return stored
      .filter(
        (item) =>
          item &&
          (item.kind === "file" || item.kind === "folder") &&
          typeof item.lastOpened === "number" &&
          typeof item.name === "string" &&
          typeof item.path === "string",
      )
      .map((item) => ({
        ...item,
        name:
          item.kind === "file" && item.name === "Arquivo avulso"
            ? item.path.split("/").pop() || item.name
            : item.name,
      }))
      .slice(0, 8);
  } catch {
    return [];
  }
}

function formatRecentTime(timestamp: number) {
  const elapsedMinutes = Math.max(
    0,
    Math.floor((Date.now() - timestamp) / 60_000),
  );
  if (elapsedMinutes < 1) return "agora";
  if (elapsedMinutes < 60) return `há ${elapsedMinutes} min`;
  const elapsedHours = Math.floor(elapsedMinutes / 60);
  if (elapsedHours < 24) return `há ${elapsedHours} h`;
  const elapsedDays = Math.floor(elapsedHours / 24);
  if (elapsedDays < 7) return `há ${elapsedDays} d`;
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "short",
  }).format(timestamp);
}

function getSearchSnippet(file: FileEntry, searchQuery: string) {
  const plainText = stripFrontmatter(file.content || "")
    .replace(/[`*_>#\[\]()|~-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  const cleanQuery = searchQuery.trim().toLocaleLowerCase("pt-BR");
  const matchIndex = plainText.toLocaleLowerCase("pt-BR").indexOf(cleanQuery);
  if (!cleanQuery || matchIndex < 0) return file.path;
  const start = Math.max(0, matchIndex - 42);
  const end = Math.min(plainText.length, matchIndex + cleanQuery.length + 72);
  return `${start > 0 ? "…" : ""}${plainText.slice(start, end).trim()}${end < plainText.length ? "…" : ""}`;
}

function renderSearchHighlights(
  html: string,
  searchQuery: string,
  activeMatch: number,
) {
  const cleanSearch = searchQuery.trim();
  if (!cleanSearch || typeof DOMParser === "undefined") {
    return { html, matchCount: 0 };
  }

  const documentFragment = new DOMParser().parseFromString(
    `<main>${html}</main>`,
    "text/html",
  );
  const root = documentFragment.querySelector("main");
  if (!root) return { html, matchCount: 0 };

  const escapedSearch = cleanSearch.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(escapedSearch, "giu");
  const walker = documentFragment.createTreeWalker(
    root,
    NodeFilter.SHOW_TEXT,
    {
      acceptNode(node) {
        const parent = node.parentElement;
        if (!node.nodeValue?.trim() || parent?.closest("button, script, style")) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    },
  );
  const textNodes: Text[] = [];
  let nextNode = walker.nextNode();
  while (nextNode) {
    textNodes.push(nextNode as Text);
    nextNode = walker.nextNode();
  }

  let matchIndex = 0;
  textNodes.forEach((textNode) => {
    const source = textNode.nodeValue || "";
    pattern.lastIndex = 0;
    const matches = [...source.matchAll(pattern)];
    if (!matches.length) return;

    const fragment = documentFragment.createDocumentFragment();
    let sourceIndex = 0;
    matches.forEach((match) => {
      const start = match.index || 0;
      if (start > sourceIndex) {
        fragment.append(documentFragment.createTextNode(source.slice(sourceIndex, start)));
      }
      const highlight = documentFragment.createElement("mark");
      highlight.className = `document-search-match${matchIndex === activeMatch ? " active" : ""}`;
      highlight.dataset.lumeSearch = String(matchIndex);
      highlight.textContent = match[0];
      fragment.append(highlight);
      matchIndex += 1;
      sourceIndex = start + match[0].length;
    });
    if (sourceIndex < source.length) {
      fragment.append(documentFragment.createTextNode(source.slice(sourceIndex)));
    }
    textNode.replaceWith(fragment);
  });

  return { html: root.innerHTML, matchCount: matchIndex };
}

function slugify(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-");
}

function normalizePath(value: string) {
  const parts: string[] = [];
  value
    .replaceAll("\\", "/")
    .split("/")
    .forEach((part) => {
      if (!part || part === ".") return;
      if (part === "..") parts.pop();
      else parts.push(part);
    });
  return parts.join("/");
}

function dirname(path: string) {
  const pieces = path.split("/");
  pieces.pop();
  return pieces.join("/");
}

function wikiToMarkdown(source: string) {
  return source.replace(
    /(!)?\[\[([^\]|#]+)(?:#([^\]|]+))?(?:\|([^\]]+))?\]\]/g,
    (_match, embed: string, target: string, heading: string, alias: string) => {
      const cleanTarget = target.trim();
      const cleanHeading = heading?.trim();
      const label = (alias || cleanHeading || cleanTarget).trim();
      if (embed && /\.(png|jpe?g|gif|webp|svg)$/i.test(cleanTarget)) {
        return `![${label}](${cleanTarget})`;
      }
      const payload = encodeURIComponent(
        `${cleanTarget}${cleanHeading ? `#${cleanHeading}` : ""}`,
      );
      return `[${label}](#wiki/${payload})`;
    },
  );
}

function stripFrontmatter(source: string) {
  if (!source.startsWith("---\n")) return source;
  const closing = source.indexOf("\n---", 4);
  return closing === -1 ? source : source.slice(closing + 4).trimStart();
}

function getFrontmatter(source: string) {
  if (!source.startsWith("---\n")) return [];
  const closing = source.indexOf("\n---", 4);
  if (closing === -1) return [];
  return source
    .slice(4, closing)
    .split("\n")
    .map((line) => line.split(/:(.*)/s))
    .filter(([key, value]) => key?.trim() && value?.trim())
    .map(([key, value]) => [key.trim(), value.trim()] as const);
}

async function collectDirectory(
  directory: FileSystemDirectoryHandle,
  prefix = "",
): Promise<FileEntry[]> {
  const entries: FileEntry[] = [];
  const iterable = directory as FileSystemDirectoryHandle & {
    values: () => AsyncIterableIterator<FileSystemHandle>;
  };
  for await (const handle of iterable.values()) {
    const path = prefix ? `${prefix}/${handle.name}` : handle.name;
    if (handle.kind === "directory") {
      entries.push(
        ...(await collectDirectory(handle as FileSystemDirectoryHandle, path)),
      );
    } else if (/\.md(?:own|arkdown)?$/i.test(handle.name)) {
      const fileHandle = handle as FileSystemFileHandle;
      const file = await fileHandle.getFile();
      entries.push({
        content: await file.text(),
        handle: fileHandle,
        lastModified: file.lastModified,
        name: file.name,
        path,
      });
    }
  }
  return entries.sort((a, b) => a.path.localeCompare(b.path));
}

export function MarkdownViewer() {
  const [files, setFiles] = useState<FileEntry[]>(DEMO_FILES);
  const [currentPath, setCurrentPath] = useState(DEMO_FILES[0].path);
  const [folderName, setFolderName] = useState("Primeiros passos");
  const [theme, setTheme] = useState<Theme>("paper");
  const [fontScale, setFontScale] = useState(1);
  const [leftOpen, setLeftOpen] = useState(true);
  const [rightOpen, setRightOpen] = useState(true);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [recentOpen, setRecentOpen] = useState(false);
  const [themeGalleryOpen, setThemeGalleryOpen] = useState(false);
  const [terminalSettingsOpen, setTerminalSettingsOpen] = useState(false);
  const [terminalPalette, setTerminalPalette] =
    useState<TerminalPalette>(loadTerminalPalette);
  const [query, setQuery] = useState("");
  const [documentSearchOpen, setDocumentSearchOpen] = useState(false);
  const [documentSearch, setDocumentSearch] = useState("");
  const [activeSearchMatch, setActiveSearchMatch] = useState(0);
  const [recentDocuments, setRecentDocuments] = useState<RecentDocument[]>([]);
  const [dropActive, setDropActive] = useState(false);
  const [toast, setToast] = useState("");
  const [rendered, setRendered] = useState("");
  const [outline, setOutline] = useState<OutlineItem[]>([]);
  const [history, setHistory] = useState([DEMO_FILES[0].path]);
  const [historyIndex, setHistoryIndex] = useState(0);
  const fileInput = useRef<HTMLInputElement>(null);
  const folderInput = useRef<HTMLInputElement>(null);
  const articleRef = useRef<HTMLElement>(null);
  const desktopLaunchHandledRef = useRef(false);
  const current = files.find((file) => file.path === currentPath) || files[0];
  const content = current?.content || "";
  const frontmatter = useMemo(() => getFrontmatter(content), [content]);
  const searchedDocument = useMemo(
    () =>
      documentSearchOpen
        ? renderSearchHighlights(rendered, documentSearch, activeSearchMatch)
        : { html: rendered, matchCount: 0 },
    [activeSearchMatch, documentSearch, documentSearchOpen, rendered],
  );
  const searchMatchCount = searchedDocument.matchCount;
  const quickThemeOptions = useMemo(
    () => themeOptions.filter((option) => option.quick),
    [],
  );
  const terminalThemeStyle = {
    "--terminal-accent": terminalPalette.accent,
    "--terminal-bg": terminalPalette.background,
    "--terminal-h1": terminalPalette.heading1,
    "--terminal-h2": terminalPalette.heading2,
    "--terminal-h3": terminalPalette.heading3,
    "--terminal-muted": terminalPalette.muted,
    "--terminal-surface": terminalPalette.surface,
    "--terminal-text": terminalPalette.text,
  } as React.CSSProperties;

  const notify = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(""), 2400);
  }, []);

  const recordRecentDocument = useCallback(
    (path: string, kind: RecentDocument["kind"], name: string) => {
      const nextItem: RecentDocument = {
        kind,
        lastOpened: Date.now(),
        name,
        path,
      };
      setRecentDocuments((existing) => {
        const next = [
          nextItem,
          ...existing.filter((item) => item.path !== path),
        ].slice(0, 8);
        localStorage.setItem(
          RECENT_DOCUMENTS_STORAGE_KEY,
          JSON.stringify(next),
        );
        return next;
      });
    },
    [],
  );

  const navigateTo = useCallback(
    (path: string, heading?: string, record = true) => {
      setCurrentPath(path);
      const openedFile = files.find((file) => file.path === path);
      if (isDesktopApp() && openedFile?.sourcePath) {
        recordRecentDocument(openedFile.sourcePath, "file", openedFile.name);
      }
      if (record) {
        const next = history.slice(0, historyIndex + 1);
        if (next[next.length - 1] !== path) next.push(path);
        setHistory(next);
        setHistoryIndex(next.length - 1);
      }
      window.requestAnimationFrame(() => {
        const target = heading
          ? document.getElementById(slugify(heading))
          : articleRef.current;
        target?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    },
    [files, history, historyIndex, recordRecentDocument],
  );

  const loadFile = useCallback(
    async (file: File, handle?: FileSystemFileHandle) => {
      if (!/\.md(?:own|arkdown)?$/i.test(file.name)) {
        notify("Esse arquivo não parece ser Markdown.");
        return;
      }
      const entry: FileEntry = {
        content: await file.text(),
        handle,
        lastModified: file.lastModified,
        name: file.name,
        path: file.name,
      };
      setFiles([entry]);
      setFolderName("Arquivo avulso");
      setCurrentPath(entry.path);
      setHistory([entry.path]);
      setHistoryIndex(0);
      notify(`${file.name} aberto`);
    },
    [notify],
  );

  const applyDesktopResult = useCallback(
    (result: DesktopOpenResult) => {
      if (!result.files.length) {
        notify("Nenhum Markdown encontrado nessa pasta.");
        return;
      }
      setFiles(result.files);
      setFolderName(result.name);
      setCurrentPath(result.files[0].path);
      setHistory([result.files[0].path]);
      setHistoryIndex(0);
      notify(
        result.kind === "file"
          ? `${result.files[0].name} aberto`
          : `${result.files.length} arquivos encontrados`,
      );
    },
    [notify],
  );

  const loadNativePath = useCallback(
    async (path: string) => {
      desktopLaunchHandledRef.current = true;
      setRecentOpen(false);
      try {
        const result = await loadDesktopPath(path);
        recordRecentDocument(
          path,
          result.kind,
          result.kind === "file"
            ? result.files[0]?.name || result.name
            : result.name,
        );
        applyDesktopResult(result);
      } catch (error) {
        notify(
          typeof error === "string"
            ? error
            : "Não consegui abrir esse caminho.",
        );
      }
    },
    [applyDesktopResult, notify, recordRecentDocument],
  );

  const openFile = useCallback(async () => {
    try {
      if (isDesktopApp()) {
        const selected = await chooseDesktopFile();
        if (typeof selected === "string") await loadNativePath(selected);
      } else if (window.showOpenFilePicker) {
        const [handle] = await window.showOpenFilePicker({
          multiple: false,
          types: [
            {
              accept: {
                "text/markdown": [".md", ".markdown", ".mdown"],
              },
              description: "Markdown",
            },
          ],
        });
        if (handle) await loadFile(await handle.getFile(), handle);
      } else {
        fileInput.current?.click();
      }
    } catch (error) {
      if (isDesktopApp()) {
        notify("Não consegui abrir esse arquivo.");
      } else if ((error as DOMException).name !== "AbortError") {
        fileInput.current?.click();
      }
    }
  }, [loadFile, loadNativePath, notify]);

  const openFolder = useCallback(async () => {
    try {
      if (isDesktopApp()) {
        const selected = await chooseDesktopFolder();
        if (typeof selected === "string") await loadNativePath(selected);
      } else if (window.showDirectoryPicker) {
        const directory = await window.showDirectoryPicker();
        const entries = await collectDirectory(directory);
        if (!entries.length) {
          notify("Nenhum Markdown encontrado nessa pasta.");
          return;
        }
        setFiles(entries);
        setFolderName(directory.name);
        setCurrentPath(entries[0].path);
        setHistory([entries[0].path]);
        setHistoryIndex(0);
        notify(`${entries.length} arquivos encontrados`);
      } else {
        folderInput.current?.click();
      }
    } catch (error) {
      if ((error as DOMException).name !== "AbortError") {
        notify("Não consegui abrir essa pasta.");
      }
    }
  }, [loadNativePath, notify]);

  const loadFolderFallback = useCallback(
    async (selected: FileList | null) => {
      if (!selected?.length) return;
      const next = (
        await Promise.all(
          Array.from(selected)
            .filter((file) => /\.md(?:own|arkdown)?$/i.test(file.name))
            .map(async (file) => ({
              content: await file.text(),
              lastModified: file.lastModified,
              name: file.name,
              path: file.webkitRelativePath || file.name,
            })),
        )
      ).sort((a, b) => a.path.localeCompare(b.path));
      if (!next.length) {
        notify("Nenhum Markdown encontrado nessa pasta.");
        return;
      }
      setFiles(next);
      setFolderName(next[0].path.split("/")[0] || "Pasta");
      setCurrentPath(next[0].path);
      setHistory([next[0].path]);
      setHistoryIndex(0);
    },
    [notify],
  );

  const resolveLocalLink = useCallback(
    (targetValue: string) => {
      const [rawPath, rawHeading] = decodeURIComponent(targetValue).split("#");
      const target = rawPath.replace(/\.md(?:own|arkdown)?$/i, "");
      const currentDir = dirname(currentPath);
      const candidates = files.filter((file) => {
        const withoutExtension = file.path.replace(
          /\.md(?:own|arkdown)?$/i,
          "",
        );
        const basename = file.name.replace(/\.md(?:own|arkdown)?$/i, "");
        const relative = normalizePath(
          currentDir ? `${currentDir}/${rawPath}` : rawPath,
        ).replace(/\.md(?:own|arkdown)?$/i, "");
        return (
          withoutExtension.toLowerCase() === target.toLowerCase() ||
          withoutExtension.toLowerCase() === relative.toLowerCase() ||
          basename.toLowerCase() === target.toLowerCase()
        );
      });
      if (!candidates.length) {
        notify(`Nota “${rawPath}” não encontrada`);
        return;
      }
      navigateTo(candidates[0].path, rawHeading);
    },
    [currentPath, files, navigateTo, notify],
  );

  useEffect(() => {
    const stored = localStorage.getItem("lume-theme") as Theme | null;
    if (stored && themeOptions.some((option) => option.value === stored)) {
      queueMicrotask(() => setTheme(stored));
    } else if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
      queueMicrotask(() => setTheme("night"));
    }
    if (!isDesktopApp() && "serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => undefined);
    }
    folderInput.current?.setAttribute("webkitdirectory", "");

    const storedRecentDocuments = loadRecentDocuments();
    queueMicrotask(() => setRecentDocuments(storedRecentDocuments));
    const recentTimer = window.setTimeout(() => {
      if (
        isDesktopApp() &&
        storedRecentDocuments.length > 0 &&
        !desktopLaunchHandledRef.current
      ) {
        setRecentOpen(true);
      }
    }, 450);
    return () => window.clearTimeout(recentTimer);
  }, []);

  useEffect(() => {
    localStorage.setItem("lume-theme", theme);
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  useEffect(() => {
    localStorage.setItem(
      TERMINAL_PALETTE_STORAGE_KEY,
      JSON.stringify(terminalPalette),
    );
  }, [terminalPalette]);

  useEffect(() => {
    window.launchQueue?.setConsumer(async ({ files: launched }) => {
      const [handle] = launched;
      if (handle) await loadFile(await handle.getFile(), handle);
    });
  }, [loadFile]);

  useEffect(() => {
    if (!isDesktopApp()) return;

    let disposed = false;
    let unlistenOpen: (() => void) | undefined;
    let unlistenDrop: (() => void) | undefined;

    async function startDesktopListeners() {
      unlistenOpen = await listenForDesktopOpen((paths) => {
        const [path] = paths;
        if (path) void loadNativePath(path);
      });
      unlistenDrop = await listenForDesktopDrop((event) => {
        if (event.type === "enter" || event.type === "over") {
          setDropActive(true);
        } else if (event.type === "leave") {
          setDropActive(false);
        } else if (event.type === "drop") {
          setDropActive(false);
          const [path] = event.paths || [];
          if (path) void loadNativePath(path);
        }
      });
      const pending = await markDesktopFrontendReady();
      const [path] = pending;
      if (path) void loadNativePath(path);

      if (disposed) {
        unlistenOpen();
        unlistenDrop();
      }
    }

    void startDesktopListeners();
    return () => {
      disposed = true;
      unlistenOpen?.();
      unlistenDrop?.();
    };
  }, [loadNativePath]);

  useEffect(() => {
    let active = true;
    async function render() {
      const html = await marked.parse(wikiToMarkdown(stripFrontmatter(content)), {
        breaks: false,
        gfm: true,
      });
      if (!active) return;
      const safe = DOMPurify.sanitize(html, {
        ADD_ATTR: ["target"],
      });
      const documentFragment = new DOMParser().parseFromString(
        `<main>${safe}</main>`,
        "text/html",
      );
      const headings: OutlineItem[] = [];
      const used = new Map<string, number>();
      documentFragment.querySelectorAll("h1, h2, h3").forEach((heading) => {
        const label = heading.textContent?.trim() || "Seção";
        const base = slugify(label) || "secao";
        const count = used.get(base) || 0;
        used.set(base, count + 1);
        const id = count ? `${base}-${count + 1}` : base;
        heading.id = id;
        headings.push({
          depth: Number(heading.tagName.slice(1)),
          id,
          label,
        });
      });
      documentFragment.querySelectorAll("pre").forEach((pre) => {
        const button = documentFragment.createElement("button");
        button.className = "copy-code";
        button.type = "button";
        button.textContent = "copiar";
        pre.prepend(button);
      });
      documentFragment.querySelectorAll('a[href^="http"]').forEach((anchor) => {
        anchor.setAttribute("target", "_blank");
        anchor.setAttribute("rel", "noreferrer");
      });
      setOutline(headings);
      setRendered(documentFragment.querySelector("main")?.innerHTML || "");
    }
    void render();
    return () => {
      active = false;
    };
  }, [content]);

  useEffect(() => {
    if (!current?.handle && !current?.sourcePath) return;
    const timer = window.setInterval(async () => {
      try {
        const refreshed = current.sourcePath
          ? await refreshDesktopFile(current.sourcePath)
          : await current.handle?.getFile();
        if (
          refreshed &&
          refreshed.lastModified !== current.lastModified
        ) {
          const nextContent =
            "content" in refreshed
              ? refreshed.content
              : await refreshed.text();
          setFiles((existing) =>
            existing.map((entry) =>
              entry.path === current.path
                ? {
                    ...entry,
                    content: nextContent,
                    lastModified: refreshed.lastModified,
                  }
                : entry,
            ),
          );
          notify("Atualizado");
        }
      } catch {
        window.clearInterval(timer);
      }
    }, 1600);
    return () => window.clearInterval(timer);
  }, [current, notify]);

  const goToDocumentSearchMatch = useCallback((requestedIndex: number) => {
    if (!searchMatchCount) return;
    const nextIndex =
      ((requestedIndex % searchMatchCount) + searchMatchCount) %
      searchMatchCount;
    setActiveSearchMatch(nextIndex);
  }, [searchMatchCount]);

  useEffect(() => {
    if (!documentSearchOpen || !searchMatchCount) return;
    const frame = window.requestAnimationFrame(() => {
      articleRef.current
        ?.querySelector<HTMLElement>(
          `mark[data-lume-search="${activeSearchMatch}"]`,
        )
        ?.scrollIntoView({ behavior: "smooth", block: "center" });
    });
    return () => window.cancelAnimationFrame(frame);
  }, [activeSearchMatch, documentSearchOpen, searchMatchCount]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!(event.metaKey || event.ctrlKey)) {
        if (event.key === "Escape") {
          setPaletteOpen(false);
          setRecentOpen(false);
          setThemeGalleryOpen(false);
          setTerminalSettingsOpen(false);
          setDocumentSearchOpen(false);
          setQuery("");
        }
        return;
      }
      const key = event.key.toLowerCase();
      if (key === "k") {
        event.preventDefault();
        setPaletteOpen(true);
      } else if (key === "f") {
        event.preventDefault();
        setDocumentSearchOpen(true);
      } else if (key === "g" && documentSearchOpen) {
        event.preventDefault();
        goToDocumentSearchMatch(
          activeSearchMatch + (event.shiftKey ? -1 : 1),
        );
      } else if (key === "o" && event.shiftKey) {
        event.preventDefault();
        void openFolder();
      } else if (key === "o") {
        event.preventDefault();
        void openFile();
      } else if (event.key === "+" || event.key === "=") {
        event.preventDefault();
        setFontScale((value) => Math.min(1.24, value + 0.06));
      } else if (event.key === "-") {
        event.preventDefault();
        setFontScale((value) => Math.max(0.84, value - 0.06));
      } else if (event.key === "0") {
        event.preventDefault();
        setFontScale(1);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [
    activeSearchMatch,
    documentSearchOpen,
    goToDocumentSearchMatch,
    openFile,
    openFolder,
  ]);

  const visibleFiles = useMemo(() => {
    const cleanQuery = query.trim().toLowerCase();
    if (!cleanQuery) return files;
    return files.filter(
      (file) =>
        file.path.toLowerCase().includes(cleanQuery) ||
        file.content?.toLowerCase().includes(cleanQuery),
    );
  }, [files, query]);

  function onArticleClick(event: MouseEvent<HTMLElement>) {
    const target = event.target as HTMLElement;
    const copyButton = target.closest<HTMLButtonElement>(".copy-code");
    if (copyButton) {
      const code = copyButton.parentElement?.querySelector("code")?.textContent;
      if (code) {
        void navigator.clipboard.writeText(code);
        copyButton.textContent = "copiado";
        window.setTimeout(() => (copyButton.textContent = "copiar"), 1600);
      }
      return;
    }
    const anchor = target.closest<HTMLAnchorElement>("a");
    if (!anchor) return;
    const href = anchor.getAttribute("href") || "";
    if (href.startsWith("#wiki/")) {
      event.preventDefault();
      resolveLocalLink(href.slice(6));
    } else if (/\.md(?:own|arkdown)?(?:#.*)?$/i.test(href)) {
      event.preventDefault();
      resolveLocalLink(href);
    } else if (/^https?:\/\//i.test(href) && isDesktopApp()) {
      event.preventDefault();
      void openDesktopUrl(href);
    }
  }

  function onDrop(event: DragEvent<HTMLElement>) {
    event.preventDefault();
    setDropActive(false);
    const file = event.dataTransfer.files[0];
    if (file) void loadFile(file);
  }

  function onTitlebarMouseDown(event: MouseEvent<HTMLElement>) {
    if (!isDesktopApp() || event.button !== 0) return;
    const target = event.target as HTMLElement;
    if (target.closest("button, input, a, [role='button']")) return;
    void startDesktopWindowDrag().catch(() => undefined);
  }

  function goBack() {
    if (historyIndex <= 0) return;
    const nextIndex = historyIndex - 1;
    setHistoryIndex(nextIndex);
    navigateTo(history[nextIndex], undefined, false);
  }

  function goForward() {
    if (historyIndex >= history.length - 1) return;
    const nextIndex = historyIndex + 1;
    setHistoryIndex(nextIndex);
    navigateTo(history[nextIndex], undefined, false);
  }

  return (
    <div
      className={`app-shell theme-${theme} ${dropActive ? "is-dropping" : ""}`}
      onDragEnter={() => setDropActive(true)}
      onDragLeave={(event) => {
        if (event.currentTarget === event.target) setDropActive(false);
      }}
      onDragOver={(event) => event.preventDefault()}
      onDrop={onDrop}
      style={terminalThemeStyle}
    >
      <header
        className="titlebar"
        data-tauri-drag-region={isDesktopApp() ? true : undefined}
        onMouseDown={onTitlebarMouseDown}
      >
        {isDesktopApp() && (
          <div
            aria-hidden="true"
            className="titlebar-drag-region"
            data-tauri-drag-region
            onMouseDown={onTitlebarMouseDown}
          />
        )}
        <div className="brand" aria-label="Lume">
          <span className="brand-mark">
            <span />
          </span>
          <span>Lume</span>
          <span className="brand-file">.md</span>
        </div>

        <div className="history-controls" aria-label="Histórico">
          <button
            className="icon-button"
            disabled={historyIndex <= 0}
            onClick={goBack}
            title="Voltar"
          >
            <ArrowLeft size={16} />
          </button>
          <button
            className="icon-button"
            disabled={historyIndex >= history.length - 1}
            onClick={goForward}
            title="Avançar"
          >
            <ArrowRight size={16} />
          </button>
        </div>

        <button className="quick-search" onClick={() => setPaletteOpen(true)}>
          <Search size={15} />
          <span>Buscar arquivos e conteúdo…</span>
          <kbd>⌘ K</kbd>
        </button>

        <div className="toolbar">
          {isDesktopApp() && (
            <button
              aria-label="Documentos recentes"
              className={`icon-button recent-trigger ${recentOpen ? "active" : ""}`}
              onClick={() => setRecentOpen((value) => !value)}
              title="Documentos recentes"
            >
              <Clock3 size={15} />
            </button>
          )}
          <button className="text-button" onClick={openFile}>
            <FileText size={15} />
            <span>Abrir arquivo</span>
          </button>
          <button className="text-button folder-button" onClick={openFolder}>
            <FolderOpen size={15} />
            <span>Abrir pasta</span>
          </button>
          <div className="theme-switcher" aria-label="Tema">
            {quickThemeOptions.map((option) => {
              const Icon = option.icon;
              return (
                <button
                  aria-label={`Tema ${option.label}`}
                  aria-pressed={theme === option.value}
                  className={theme === option.value ? "active" : ""}
                  key={option.value}
                  onClick={() => setTheme(option.value)}
                  title={option.label}
                >
                  <Icon size={14} />
                </button>
              );
            })}
            <button
              aria-label="Mais temas"
              aria-pressed={!quickThemeOptions.some(
                (option) => option.value === theme,
              )}
              className={
                !quickThemeOptions.some((option) => option.value === theme)
                  ? "active"
                  : ""
              }
              onClick={() => setThemeGalleryOpen(true)}
              title="Mais temas"
            >
              <Palette size={14} />
            </button>
          </div>
          {theme === "terminal" && (
            <button
              aria-label="Personalizar Terminal"
              className="icon-button terminal-settings-trigger"
              onClick={() => setTerminalSettingsOpen(true)}
              title="Personalizar Terminal"
            >
              <Settings2 size={15} />
            </button>
          )}
        </div>
      </header>

      <div
        className={`workspace ${leftOpen ? "" : "left-closed"} ${rightOpen ? "" : "right-closed"}`}
      >
        <aside className="file-sidebar">
          <div className="sidebar-heading">
            <div>
              <span className="eyebrow">Biblioteca local</span>
              <strong>{folderName}</strong>
            </div>
            <button
              className="icon-button subtle"
              onClick={() => setLeftOpen(false)}
              title="Ocultar arquivos"
            >
              <PanelLeftClose size={16} />
            </button>
          </div>
          <label className="sidebar-search">
            <Search size={14} />
            <input
              aria-label="Filtrar arquivos"
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Filtrar…"
              value={query}
            />
            {query && (
              <button onClick={() => setQuery("")} title="Limpar">
                <X size={13} />
              </button>
            )}
          </label>
          <nav className="file-list" aria-label="Arquivos Markdown">
            {visibleFiles.map((file) => {
              const pieces = file.path.split("/");
              const nested = pieces.length > 1;
              return (
                <button
                  className={file.path === currentPath ? "active" : ""}
                  key={file.path}
                  onClick={() => navigateTo(file.path)}
                  title={file.path}
                >
                  {nested ? <ChevronRight size={13} /> : <File size={13} />}
                  <span>{file.name.replace(/\.md(?:own|arkdown)?$/i, "")}</span>
                </button>
              );
            })}
          </nav>
          <div className="sidebar-footer">
            <span className="privacy-dot" />
            {files === DEMO_FILES ? "demonstração" : "somente neste dispositivo"}
            <span>{files.length} md</span>
          </div>
        </aside>

        {!leftOpen && (
          <button
            className="floating-panel-button left"
            onClick={() => setLeftOpen(true)}
            title="Mostrar arquivos"
          >
            <PanelLeftOpen size={17} />
          </button>
        )}

        <main className="reader">
          <div className="document-bar">
            <div className="document-path">
              {currentPath.split("/").map((piece, index, all) => (
                <span key={`${piece}-${index}`}>
                  {index > 0 && <ChevronRight size={12} />}
                  <span className={index === all.length - 1 ? "current" : ""}>
                    {piece}
                  </span>
                </span>
              ))}
            </div>
            <div className="reading-tools">
              <button
                aria-label="Buscar neste documento"
                className={`icon-button ${documentSearchOpen ? "active" : ""}`}
                onClick={() => setDocumentSearchOpen((value) => !value)}
                title="Buscar neste documento (⌘ F)"
              >
                <Search size={14} />
              </button>
              <button
                className="icon-button"
                onClick={() =>
                  setFontScale((value) => Math.max(0.84, value - 0.06))
                }
                title="Diminuir texto"
              >
                <Minus size={14} />
              </button>
              <span>{Math.round(fontScale * 100)}%</span>
              <button
                className="icon-button"
                onClick={() =>
                  setFontScale((value) => Math.min(1.24, value + 0.06))
                }
                title="Aumentar texto"
              >
                <Plus size={14} />
              </button>
              <button
                className="icon-button mobile-outline"
                onClick={() => setRightOpen((value) => !value)}
                title="Sumário"
              >
                <List size={15} />
              </button>
            </div>
            {documentSearchOpen && (
              <div className="document-search-panel">
                <Search size={14} />
                <input
                  aria-label="Buscar neste documento"
                  autoFocus
                  onChange={(event) => {
                    setDocumentSearch(event.target.value);
                    setActiveSearchMatch(0);
                  }}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      goToDocumentSearchMatch(
                        activeSearchMatch + (event.shiftKey ? -1 : 1),
                      );
                    } else if (event.key === "Escape") {
                      setDocumentSearchOpen(false);
                    }
                  }}
                  placeholder="Palavra ou termo…"
                  value={documentSearch}
                />
                <span className="document-search-count">
                  {documentSearch.trim()
                    ? searchMatchCount
                      ? `${activeSearchMatch + 1}/${searchMatchCount}`
                      : "0/0"
                    : ""}
                </span>
                <button
                  aria-label="Ocorrência anterior"
                  disabled={!searchMatchCount}
                  onClick={() =>
                    goToDocumentSearchMatch(activeSearchMatch - 1)
                  }
                  title="Anterior (⇧ Enter)"
                >
                  <ChevronUp size={14} />
                </button>
                <button
                  aria-label="Próxima ocorrência"
                  disabled={!searchMatchCount}
                  onClick={() =>
                    goToDocumentSearchMatch(activeSearchMatch + 1)
                  }
                  title="Próxima (Enter)"
                >
                  <ChevronDown size={14} />
                </button>
                <button
                  aria-label="Fechar busca"
                  onClick={() => setDocumentSearchOpen(false)}
                  title="Fechar"
                >
                  <X size={14} />
                </button>
              </div>
            )}
          </div>
          <div className="reader-scroll">
            <article
              className="markdown-body"
              dangerouslySetInnerHTML={{ __html: searchedDocument.html }}
              onClick={onArticleClick}
              ref={articleRef}
              style={{ "--reader-scale": fontScale } as React.CSSProperties}
            />
            <footer className="document-end">
              <span />
              fim de {current?.name || "documento"}
              <span />
            </footer>
          </div>
        </main>

        <aside className="outline-sidebar">
          <div className="sidebar-heading">
            <div>
              <span className="eyebrow">Neste arquivo</span>
              <strong>Sumário</strong>
            </div>
            <button
              className="icon-button subtle"
              onClick={() => setRightOpen(false)}
              title="Ocultar sumário"
            >
              <X size={15} />
            </button>
          </div>
          <nav className="outline-list" aria-label="Sumário do documento">
            {outline.map((item) => (
              <button
                className={`depth-${item.depth}`}
                key={item.id}
                onClick={() =>
                  document
                    .getElementById(item.id)
                    ?.scrollIntoView({ behavior: "smooth", block: "start" })
                }
              >
                {item.label}
              </button>
            ))}
          </nav>
          {!!frontmatter.length && (
            <div className="metadata-card">
              <span className="eyebrow">Propriedades</span>
              {frontmatter.map(([key, value]) => (
                <div key={key}>
                  <span>{key}</span>
                  <strong>{value}</strong>
                </div>
              ))}
            </div>
          )}
        </aside>

        {!rightOpen && (
          <button
            className="floating-panel-button right"
            onClick={() => setRightOpen(true)}
            title="Mostrar sumário"
          >
            <List size={17} />
          </button>
        )}
      </div>

      {recentOpen && (
        <div
          className="recent-backdrop"
          onMouseDown={() => setRecentOpen(false)}
        >
          <section
            aria-labelledby="recent-title"
            aria-modal="true"
            className="recent-panel"
            onMouseDown={(event) => event.stopPropagation()}
            role="dialog"
          >
            <header className="recent-panel-header">
              <div>
                <span className="eyebrow">Retomar leitura</span>
                <h2 id="recent-title">Abertos recentemente</h2>
              </div>
              <button
                className="icon-button"
                onClick={() => setRecentOpen(false)}
                title="Fechar"
              >
                <X size={16} />
              </button>
            </header>
            <div className="recent-list">
              {recentDocuments.map((item) => {
                const RecentIcon = item.kind === "folder" ? FolderOpen : FileText;
                return (
                  <button
                    className="recent-item"
                    key={item.path}
                    onClick={() => void loadNativePath(item.path)}
                    title={item.path}
                  >
                    <span className="recent-item-icon">
                      <RecentIcon size={16} />
                    </span>
                    <span>
                      <strong>{item.name}</strong>
                      <small>{item.path}</small>
                    </span>
                    <time>{formatRecentTime(item.lastOpened)}</time>
                  </button>
                );
              })}
              {!recentDocuments.length && (
                <div className="recent-empty">
                  <Clock3 size={20} />
                  <strong>Nada por aqui ainda</strong>
                  <span>Os próximos arquivos e pastas aparecerão aqui.</span>
                </div>
              )}
            </div>
            <footer className="recent-panel-footer">
              <span>O histórico fica somente neste dispositivo.</span>
              {!!recentDocuments.length && (
                <button
                  onClick={() => {
                    setRecentDocuments([]);
                    localStorage.removeItem(RECENT_DOCUMENTS_STORAGE_KEY);
                  }}
                >
                  Limpar histórico
                </button>
              )}
            </footer>
          </section>
        </div>
      )}

      {themeGalleryOpen && (
        <div
          className="theme-gallery-backdrop"
          onMouseDown={() => setThemeGalleryOpen(false)}
        >
          <section
            aria-labelledby="theme-gallery-title"
            aria-modal="true"
            className="theme-gallery"
            onMouseDown={(event) => event.stopPropagation()}
            role="dialog"
          >
            <header className="theme-gallery-header">
              <div>
                <span className="eyebrow">Paletas de leitura</span>
                <h2 id="theme-gallery-title">Escolha o clima</h2>
              </div>
              <button
                className="icon-button"
                onClick={() => setThemeGalleryOpen(false)}
                title="Fechar"
              >
                <X size={16} />
              </button>
            </header>
            <div className="theme-gallery-grid">
              {themeOptions.map((option) => {
                const ThemeIcon = option.icon;
                return (
                  <button
                    aria-pressed={theme === option.value}
                    className={`theme-card ${theme === option.value ? "active" : ""}`}
                    key={option.value}
                    onClick={() => {
                      setTheme(option.value);
                      setThemeGalleryOpen(false);
                    }}
                  >
                    <span
                      className="theme-card-preview"
                      style={
                        {
                          "--swatch-accent": option.swatches[2],
                          "--swatch-bg": option.swatches[0],
                          "--swatch-text": option.swatches[1],
                        } as React.CSSProperties
                      }
                    >
                      <i />
                      <b />
                      <em />
                    </span>
                    <span className="theme-card-copy">
                      <span>
                        <ThemeIcon size={14} />
                        <strong>{option.label}</strong>
                        {theme === option.value && <Check size={14} />}
                      </span>
                      <small>{option.description}</small>
                    </span>
                  </button>
                );
              })}
            </div>
          </section>
        </div>
      )}

      {paletteOpen && (
        <div className="palette-backdrop" onMouseDown={() => setPaletteOpen(false)}>
          <section
            aria-label="Navegador rápido"
            aria-modal="true"
            className="command-palette"
            onMouseDown={(event) => event.stopPropagation()}
            role="dialog"
          >
            <div className="palette-input">
              <Search size={18} />
              <input
                autoFocus
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Nome ou conteúdo…"
                value={query}
              />
              <kbd>esc</kbd>
            </div>
            <div className="palette-results">
              <span className="eyebrow">
                {query ? `${visibleFiles.length} resultados` : "Arquivos da pasta"}
              </span>
              {visibleFiles.slice(0, 12).map((file) => (
                <button
                  key={file.path}
                  onClick={() => {
                    navigateTo(file.path);
                    setPaletteOpen(false);
                    setQuery("");
                  }}
                >
                  <FileText size={16} />
                  <span>
                    <strong>{file.name}</strong>
                    <small>{getSearchSnippet(file, query)}</small>
                  </span>
                  {file.path === currentPath && <Check size={15} />}
                </button>
              ))}
              {!visibleFiles.length && (
                <div className="no-results">Nenhum arquivo por aqui.</div>
              )}
            </div>
          </section>
        </div>
      )}

      {terminalSettingsOpen && (
        <div
          className="terminal-settings-backdrop"
          onMouseDown={() => setTerminalSettingsOpen(false)}
        >
          <section
            aria-labelledby="terminal-settings-title"
            aria-modal="true"
            className="terminal-settings"
            onMouseDown={(event) => event.stopPropagation()}
            role="dialog"
          >
            <header className="terminal-settings-header">
              <div>
                <span className="eyebrow">Aparência</span>
                <h2 id="terminal-settings-title">Terminal do seu jeito</h2>
              </div>
              <button
                className="icon-button"
                onClick={() => setTerminalSettingsOpen(false)}
                title="Fechar"
              >
                <X size={16} />
              </button>
            </header>

            <div className="terminal-settings-content">
              <div className="terminal-color-grid">
                {terminalColorFields.map((field) => (
                  <label className="terminal-color-field" key={field.key}>
                    <span>{field.label}</span>
                    <span className="terminal-color-control">
                      <input
                        aria-label={`Cor de ${field.label.toLowerCase()}`}
                        onChange={(event) =>
                          setTerminalPalette((currentPalette) => ({
                            ...currentPalette,
                            [field.key]: event.target.value,
                          }))
                        }
                        type="color"
                        value={terminalPalette[field.key]}
                      />
                      <code>{terminalPalette[field.key].toUpperCase()}</code>
                    </span>
                  </label>
                ))}
              </div>

              <div
                className="terminal-preview"
                style={
                  {
                    "--preview-accent": terminalPalette.accent,
                    "--preview-bg": terminalPalette.background,
                    "--preview-h1": terminalPalette.heading1,
                    "--preview-h2": terminalPalette.heading2,
                    "--preview-h3": terminalPalette.heading3,
                    "--preview-muted": terminalPalette.muted,
                    "--preview-surface": terminalPalette.surface,
                    "--preview-text": terminalPalette.text,
                  } as React.CSSProperties
                }
              >
                <span className="terminal-preview-label">prévia ao vivo</span>
                <strong>
                  <i>#</i> Lume Terminal
                </strong>
                <b>
                  <i>##</i> Destaque principal
                </b>
                <em>
                  <i>###</i> Informação complementar
                </em>
                <p>
                  <span>$</span> seus arquivos continuam locais
                </p>
              </div>
            </div>

            <footer className="terminal-settings-footer">
              <button
                className="text-button"
                onClick={() =>
                  setTerminalPalette({ ...DEFAULT_TERMINAL_PALETTE })
                }
              >
                <RotateCcw size={14} />
                Restaurar padrão
              </button>
              <button
                className="text-button terminal-settings-done"
                onClick={() => setTerminalSettingsOpen(false)}
              >
                Concluído
              </button>
            </footer>
          </section>
        </div>
      )}

      {dropActive && (
        <div className="drop-overlay">
          <div>
            <Maximize2 size={25} />
            <strong>Solte para ler</strong>
            <span>Seu arquivo continua no seu dispositivo</span>
          </div>
        </div>
      )}

      {toast && <div className="toast">{toast}</div>}

      <input
        accept=".md,.markdown,.mdown,text/markdown,text/plain"
        className="visually-hidden"
        onChange={(event: ChangeEvent<HTMLInputElement>) => {
          const file = event.target.files?.[0];
          if (file) void loadFile(file);
          event.target.value = "";
        }}
        ref={fileInput}
        type="file"
      />
      <input
        className="visually-hidden"
        multiple
        onChange={(event) => {
          void loadFolderFallback(event.target.files);
          event.target.value = "";
        }}
        ref={folderInput}
        type="file"
      />
    </div>
  );
}
