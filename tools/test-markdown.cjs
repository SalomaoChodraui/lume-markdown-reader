// Node tests for Resources/Web/lume-markdown.js. Run: node tools/test-markdown.cjs
const assert = require("node:assert/strict");
const path = require("node:path");
const web = path.join(__dirname, "..", "Resources", "Web");
const marked = require(path.join(web, "marked.umd.js"));
const { createParser, toHTML } = require(path.join(web, "lume-markdown.js"));
const parser = createParser(marked);
const html = (src) => toHTML(parser, src).trim();
let passed = 0;
function test(name, fn) { fn(); passed += 1; console.log(`PASS ${name}`); }

test("wiki link becomes a local link", () => {
  assert.equal(html("Veja [[Atalhos]]."), '<p>Veja <a class="wikilink" href="#wiki/Atalhos">Atalhos</a>.</p>');
});
test("wiki link with alias and heading", () => {
  assert.match(html("[[Links wiki#Seção|como funciona]]"), /href="#wiki\/Links%20wiki%23Se%C3%A7%C3%A3o">como funciona<\/a>/);
});
test("wiki link inside inline code stays literal", () => {
  assert.equal(html("Formato `[[Links wiki]]`"), "<p>Formato <code>[[Links wiki]]</code></p>");
});
test("wiki link inside a code block stays literal", () => {
  assert.match(html("```\n[[Nota]]\n```"), /<code>\[\[Nota\]\]\n<\/code>/);
});
test("image embed", () => {
  assert.equal(html("![[foto.png]]"), '<p><img src="foto.png" alt="foto.png"></p>');
});
test("labels are escaped", () => {
  assert.match(html("[[a|<b>x</b>]]"), /&lt;b&gt;x&lt;\/b&gt;/);
});
test("tables render with gfm", () => {
  assert.match(html("| a | b |\n| - | - |\n| 1 | 2 |"), /<table>/);
});
console.log(`${passed} markdown tests passed`);
