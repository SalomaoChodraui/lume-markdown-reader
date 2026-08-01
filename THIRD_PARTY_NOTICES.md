# Avisos de terceiros

O Lume é distribuído sob a licença MIT, mas incorpora ou utiliza projetos de
terceiros que permanecem sob suas próprias licenças.

## Dependências incluídas no aplicativo

| Projeto | Uso | Licença declarada |
| --- | --- | --- |
| Tauri e plugins oficiais | Aplicativo nativo e diálogos do sistema | MIT ou Apache-2.0 |
| React e React DOM | Interface | MIT |
| DOMPurify | Sanitização do HTML renderizado | Apache-2.0 ou MPL-2.0 |
| Marked | Conversão de Markdown | MIT |
| Lucide | Ícones da interface | ISC |
| Drizzle ORM | Infraestrutura compartilhada do projeto web | Apache-2.0 |

Para o DOMPurify, o Lume opta pelos termos da licença Apache-2.0.

## Fontes

- **Geist** e **Geist Mono**, por Vercel — SIL Open Font License 1.1.
- **Lora**, por Cyreal — SIL Open Font License 1.1.

As fontes são empacotadas apenas na compilação web. O aplicativo desktop usa
as famílias disponíveis no sistema e seus fallbacks quando necessário.

## Ferramentas e dependências de compilação

O desenvolvimento usa Next.js, Vite, vinext, Tailwind CSS, TypeScript,
Cloudflare Wrangler e ferramentas do ecossistema Rust/Tauri. As dependências
diretas usam licenças permissivas (MIT, Apache-2.0, ISC, BSD ou MPL-2.0).

O `package-lock.json` também referencia binários opcionais do `libvips`, sob
LGPL-3.0-or-later, usados pelo Sharp durante compilações web. Eles não são
incorporados ao bundle desktop do Lume.

As versões exatas e a árvore transitiva auditada estão registradas em
`package-lock.json` e `src-tauri/Cargo.lock`. Os textos de licença de cada
pacote também acompanham seus respectivos pacotes-fonte nos registros npm e
crates.io.

Este arquivo é informativo e não altera os termos das licenças originais.
