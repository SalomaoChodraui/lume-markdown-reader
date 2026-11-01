// The reading page inside the WKWebView. Swift calls Lume.render, Lume.search,
// Lume.scrollToHeading and Lume.setAppearance; the page answers through the
// "lume" message handler (outline, scroll, search, link, copy).
(function () {
  "use strict";

  const parser = LumeMarkdown.createParser(marked);
  const article = document.getElementById("doc");
  const CALLOUTS = {
    NOTE: "Nota",
    TIP: "Dica",
    IMPORTANT: "Importante",
    WARNING: "Atenção",
    CAUTION: "Cuidado",
  };
  let docDir = "";
  let searchQuery = "";
  let activeMatch = 0;
  let headings = [];
  let scrollTimer = 0;

  function post(name, body) {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lume;
    if (handler) handler.postMessage(Object.assign({ name }, body || {}));
  }

  function scrollBehavior() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth";
  }

  function slugify(value) {
    return value
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .trim()
      .replace(/[^\w\s-]/g, "")
      .replace(/\s+/g, "-")
      .replace(/-+/g, "-");
  }

  function joinPath(dir, relative) {
    const parts = [];
    `${dir}/${relative}`.split("/").forEach((part) => {
      if (!part || part === ".") return;
      if (part === "..") parts.pop();
      else parts.push(part);
    });
    return "/" + parts.join("/");
  }

  function isExternal(href) {
    return /^[a-z][a-z0-9+.-]*:/i.test(href);
  }

  function decorate() {
    // Headings get stable ids for the outline and for links to a section.
    const used = new Map();
    headings = [];
    article.querySelectorAll("h1, h2, h3").forEach((heading) => {
      const label = heading.textContent.trim() || "Seção";
      const base = slugify(label) || "secao";
      const count = used.get(base) || 0;
      used.set(base, count + 1);
      heading.id = count ? `${base}-${count + 1}` : base;
      headings.push({ id: heading.id, label, depth: Number(heading.tagName.slice(1)) });
    });

    // GitHub alerts: > [!NOTE] becomes a callout with a word, never color alone.
    article.querySelectorAll("blockquote").forEach((quote) => {
      const first = quote.querySelector("p");
      const text = first && first.firstChild;
      if (!text || text.nodeType !== Node.TEXT_NODE) return;
      const match = /^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*/i.exec(text.nodeValue);
      if (!match) return;
      const kind = match[1].toUpperCase();
      text.nodeValue = text.nodeValue.slice(match[0].length);
      if (first.firstChild && first.firstChild.nodeName === "BR") first.firstChild.remove();
      if (!first.textContent.trim() && !first.children.length) first.remove();
      quote.classList.add("callout", `callout-${kind.toLowerCase()}`);
      const title = document.createElement("p");
      title.className = "callout-title";
      title.textContent = CALLOUTS[kind];
      quote.prepend(title);
    });

    article.querySelectorAll("pre").forEach((pre) => {
      const button = document.createElement("button");
      button.className = "copy-code";
      button.type = "button";
      button.textContent = "Copiar";
      button.setAttribute("aria-label", "Copiar código");
      pre.prepend(button);
    });

    // Local images load through the lume:// scheme, which reads the disk.
    article.querySelectorAll("img[src]").forEach((image) => {
      const src = image.getAttribute("src");
      if (!src || isExternal(src) || !docDir) return;
      let relative = src;
      try {
        relative = decodeURI(src);
      } catch (_error) {
        // A malformed escape keeps the path as written.
      }
      const absolute = relative.startsWith("/") ? relative : joinPath(docDir, relative);
      image.src = "lume://file" + encodeURI(absolute);
    });
  }

  function clearHighlights() {
    article.querySelectorAll("mark.lume-match").forEach((mark) => {
      mark.replaceWith(document.createTextNode(mark.textContent));
    });
    article.normalize();
  }

  function highlight() {
    clearHighlights();
    const query = searchQuery.trim();
    if (!query) {
      post("search", { count: 0, active: 0 });
      return;
    }
    const pattern = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "giu");
    const walker = document.createTreeWalker(article, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!node.nodeValue.trim() || node.parentElement.closest("button, script, style")) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);

    let index = 0;
    nodes.forEach((node) => {
      const source = node.nodeValue;
      const matches = [...source.matchAll(pattern)];
      if (!matches.length) return;
      const fragment = document.createDocumentFragment();
      let cursor = 0;
      matches.forEach((match) => {
        if (match.index > cursor) fragment.append(source.slice(cursor, match.index));
        const mark = document.createElement("mark");
        mark.className = "lume-match";
        mark.dataset.index = String(index);
        mark.textContent = match[0];
        fragment.append(mark);
        index += 1;
        cursor = match.index + match[0].length;
      });
      if (cursor < source.length) fragment.append(source.slice(cursor));
      node.replaceWith(fragment);
    });

    const count = index;
    if (count) activeMatch = ((activeMatch % count) + count) % count;
    else activeMatch = 0;
    const active = article.querySelector(`mark.lume-match[data-index="${activeMatch}"]`);
    if (active) {
      active.classList.add("active");
      active.scrollIntoView({ behavior: scrollBehavior(), block: "center" });
    }
    post("search", { count, active: activeMatch });
  }

  function currentHeading() {
    let current = headings.length ? headings[0].id : "";
    for (const heading of headings) {
      const element = document.getElementById(heading.id);
      if (element && element.getBoundingClientRect().top <= 96) current = heading.id;
      else break;
    }
    return current;
  }

  function scrollRatio() {
    const max = document.documentElement.scrollHeight - window.innerHeight;
    return max > 0 ? window.scrollY / max : 0;
  }

  function reportScroll() {
    post("scroll", { ratio: scrollRatio(), heading: currentHeading() });
  }

  window.addEventListener("scroll", () => {
    window.clearTimeout(scrollTimer);
    scrollTimer = window.setTimeout(reportScroll, 120);
  });

  document.addEventListener("click", (event) => {
    const copy = event.target.closest(".copy-code");
    if (copy) {
      const code = copy.parentElement.querySelector("code");
      post("copy", { text: code ? code.textContent : "" });
      copy.textContent = "Copiado";
      window.setTimeout(() => (copy.textContent = "Copiar"), 1600);
      return;
    }
    const anchor = event.target.closest("a[href]");
    if (!anchor) return;
    event.preventDefault();
    const href = anchor.getAttribute("href");
    if (href.startsWith("#wiki/")) {
      post("link", { kind: "wiki", target: decodeURIComponent(href.slice(6)) });
    } else if (href.startsWith("#")) {
      const target = document.getElementById(decodeURIComponent(href.slice(1)));
      if (target) target.scrollIntoView({ behavior: scrollBehavior(), block: "start" });
    } else if (isExternal(href)) {
      post("link", { kind: "external", target: href });
    } else {
      post("link", { kind: "relative", target: decodeURIComponent(href) });
    }
  });

  window.Lume = {
    render(payload) {
      docDir = payload.docDir || "";
      article.innerHTML = DOMPurify.sanitize(LumeMarkdown.toHTML(parser, payload.markdown));
      decorate();
      if (searchQuery) highlight();
      post("outline", { items: headings });
      if (payload.heading) {
        this.scrollToHeading(payload.heading, false);
      } else {
        const max = document.documentElement.scrollHeight - window.innerHeight;
        window.scrollTo(0, Math.max(0, (payload.ratio || 0) * max));
      }
      reportScroll();
    },

    // Re-renders the same document after an outside change, keeping the place.
    refresh(payload) {
      const ratio = scrollRatio();
      this.render(Object.assign({}, payload, { ratio, heading: "" }));
    },

    setAppearance(payload) {
      const html = document.documentElement;
      html.className = `theme-${payload.theme} width-${payload.width}`;
      html.style.setProperty("--reader-scale", String(payload.scale));
      Object.entries(payload.terminal || {}).forEach(([key, value]) => {
        html.style.setProperty(`--terminal-${key}`, value);
      });
    },

    scrollToHeading(id, animated) {
      const slug = document.getElementById(id) ? id : slugify(id);
      const target = document.getElementById(slug);
      if (target) {
        target.scrollIntoView({ behavior: animated === false ? "auto" : scrollBehavior(), block: "start" });
      }
    },

    search(query, active) {
      searchQuery = query || "";
      activeMatch = active || 0;
      highlight();
    },
  };

  post("ready");
})();
