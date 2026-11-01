// Markdown to HTML, with no DOM: the reader and the Node tests share it.
// Wiki links are a marked extension, so they never apply inside code.
(function (root) {
  "use strict";

  const WIKI = /^(!)?\[\[([^\]|#\n]+)(?:#([^\]|\n]+))?(?:\|([^\]\n]+))?\]\]/;
  const IMAGE = /\.(png|jpe?g|gif|webp|svg|avif|heic)$/i;

  function escapeHTML(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  const wikiLink = {
    name: "wikilink",
    level: "inline",
    start(src) {
      const index = src.indexOf("[[");
      if (index < 0) return undefined;
      return index > 0 && src[index - 1] === "!" ? index - 1 : index;
    },
    tokenizer(src) {
      const match = WIKI.exec(src);
      if (!match) return undefined;
      return {
        type: "wikilink",
        raw: match[0],
        embed: Boolean(match[1]),
        target: match[2].trim(),
        heading: (match[3] || "").trim(),
        alias: (match[4] || "").trim(),
      };
    },
    renderer(token) {
      const label = escapeHTML(token.alias || token.heading || token.target);
      if (token.embed && IMAGE.test(token.target)) {
        return `<img src="${escapeHTML(token.target)}" alt="${label}">`;
      }
      const target = token.target + (token.heading ? `#${token.heading}` : "");
      return `<a class="wikilink" href="#wiki/${encodeURIComponent(target)}">${label}</a>`;
    },
  };

  function createParser(markedLib) {
    const parser = new markedLib.Marked({ async: false, breaks: false, gfm: true });
    parser.use({ extensions: [wikiLink] });
    return parser;
  }

  function toHTML(parser, markdown) {
    return parser.parse(String(markdown || ""));
  }

  const api = { createParser, escapeHTML, toHTML };
  root.LumeMarkdown = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
