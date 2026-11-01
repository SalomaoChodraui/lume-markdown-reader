import Foundation
import Testing
@testable import LumeKit

@Test func frontmatterSplitsPropertiesAndBody() {
    let (properties, body) = Frontmatter.split("---\nstatus: pronto\ntipo: \"guia\"\nvazio:\n---\n\n# Título")
    #expect(properties == [Property(key: "status", value: "pronto"), Property(key: "tipo", value: "guia")])
    #expect(body == "# Título")
}

@Test func frontmatterHandlesWindowsLineEndingsAndAbsence() {
    #expect(Frontmatter.split("---\r\na: 1\r\n---\r\ntexto").body == "texto")
    #expect(Frontmatter.split("# Sem cabeçalho").properties.isEmpty)
    #expect(Frontmatter.split("---\nsem fim").body == "---\nsem fim")
}

@Test func treePutsFoldersFirstInFinderOrder() {
    let tree = FileTree.build(paths: ["Nota 10.md", "b/x.md", "Nota 2.md", "a/c/y.md"])
    #expect(tree.map(\.name) == ["a", "b", "Nota 2.md", "Nota 10.md"])
    #expect(tree[0].children?.first?.path == "a/c")
    #expect(tree[0].children?.first?.children?.first?.path == "a/c/y.md")
    #expect(tree[2].children == nil)
}

@Test func ancestorsAndNormalize() {
    #expect(FileTree.ancestors(of: "a/b/c.md") == ["a", "a/b"])
    #expect(FileTree.normalize("a/./b/../c.md") == "a/c.md")
    #expect(FileTree.directory(of: "a/b/c.md") == "a/b")
}

@Test func linksResolveNextToTheCurrentFileFirst() {
    let paths = ["Atalhos.md", "notas/Atalhos.md", "notas/Ideia.md", "Links wiki.md"]
    #expect(LinkResolver.resolve("Atalhos", from: "notas/Ideia.md", in: paths)?.path == "notas/Atalhos.md")
    #expect(LinkResolver.resolve("Atalhos", from: "Links wiki.md", in: paths)?.path == "Atalhos.md")
    #expect(LinkResolver.resolve("../Links%20wiki.md", from: "notas/Ideia.md", in: paths)?.path == "Links wiki.md")
    #expect(LinkResolver.resolve("links wiki#Seção", from: "Atalhos.md", in: paths) == .init(path: "Links wiki.md", heading: "Seção"))
    #expect(LinkResolver.resolve("Ideia", from: "Atalhos.md", in: paths)?.path == "notas/Ideia.md")
    #expect(LinkResolver.resolve("Nada", from: "Atalhos.md", in: paths) == nil)
}

@Test func searchIgnoresCaseAndAccents() {
    #expect(SearchText.matches("secao", name: "x.md", content: "Uma Seção aqui"))
    #expect(!SearchText.matches("zebra", name: "x.md", content: "nada"))
    #expect(SearchText.snippet("seção", in: "---\na: b\n---\n# Título\nTexto da seção final") == "Título Texto da seção final")
    #expect(SearchText.snippet("x", in: "") == nil)
}

@Test func readerScaleStepsAndClamps() {
    #expect(ReaderScale.step(1, by: 1) == 1.05)
    #expect(ReaderScale.step(1.6, by: 1) == 1.6)
    #expect(ReaderScale.step(0.8, by: -1) == 0.8)
}

@Test func automaticThemeFollowsTheMac() {
    #expect(ReadingTheme.automatic.resolved(dark: true) == .night)
    #expect(ReadingTheme.automatic.resolved(dark: false) == .paper)
    #expect(ReadingTheme.sepia.resolved(dark: true) == .sepia)
}

@Test func terminalPaletteRejectsBadColors() {
    var palette = TerminalPalette()
    palette.accent = "verde"
    #expect(palette.cssValues["accent"] == "#63d483")
    #expect(TerminalPalette.valid("#ABCDEF") == "#abcdef")
}

@Test func recentsKeepTheNewestFirstWithoutDuplicates() {
    let old = RecentItem(path: "/a.md", isFolder: false, opened: .distantPast)
    let list = RecentItem.adding(RecentItem(path: "/b", isFolder: true), to: [old])
    let again = RecentItem.adding(RecentItem(path: "/a.md", isFolder: false), to: list)
    #expect(again.map(\.path) == ["/a.md", "/b"])
    #expect(RecentItem.adding(old, to: Array(repeating: old, count: 0), limit: 1).count == 1)
}

@Test func markdownStemAndRelativePath() {
    #expect(MarkdownFiles.stem("Nota.MD") == "Nota")
    #expect(MarkdownFiles.stem("foto.png") == "foto.png")
    let folder = URL(fileURLWithPath: "/tmp/lib")
    #expect(MarkdownFiles.relativePath(of: URL(fileURLWithPath: "/tmp/lib/a/b.md"), in: folder) == "a/b.md")
}
