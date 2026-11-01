# Lume

Markdown, para ler. Um leitor local e calmo para macOS 14 ou superior, em SwiftUI.
Binário universal para Apple Silicon e Intel.

- abre arquivos `.md`, `.markdown` e `.mdown`, avulsos ou em pastas
- links wiki `[[Nota]]`, `[[Nota|apelido]]`, `[[Nota#Seção]]` e links relativos
- sumário e propriedades do front matter no inspetor
- busca no documento (⌘F) e em todos os arquivos (⌥⌘F)
- edição rápida com números de linha, Desfazer e Salvar
- seis temas de leitura; o Automático segue o modo claro ou escuro do Mac
- funciona offline e não envia nada a servidor algum

## Desenvolvimento

```bash
./build.sh --open                                              # compila e instala em ~/Applications
swift test --scratch-path ~/Library/Developer/Lume/test-build  # testes do LumeKit
node tools/test-markdown.cjs                                   # testes do renderizador
tools/selftest.sh                                              # autoteste dentro do app
tools/snap.sh                                                  # prints claro e escuro em /tmp/Lume-shots
```

Publicação: `docs/RELEASING.md`.

Licença MIT. Bibliotecas de terceiros: `THIRD_PARTY_NOTICES.md`.
