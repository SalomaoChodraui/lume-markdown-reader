# Lume: plano de design

Leitor de Markdown local para macOS 14 ou superior, em SwiftUI. Liquid Glass
aparece sozinho no macOS 26. Sucessor nativo da versão
Tauri 1.2.1 (`~/Documents/05_Empresas/MD Viewer`).

## Arquétipo

Janela única com barra lateral (`NavigationSplitView`) e inspetor
(`.inspector`). A barra lateral lista os arquivos da pasta aberta, o centro
mostra o documento e o inspetor mostra o sumário e o front matter.

O documento é renderizado num `WKWebView` (marked + DOMPurify, em
`Resources/Web`). Toda a interface ao redor é SwiftUI nativa.

## Arquitetura da informação

- Barra lateral: a árvore de pastas e arquivos, com triângulos de abertura
  (⌥-clique abre tudo). Com busca ativa, vira lista de resultados com trecho.
- Sem nada aberto: a barra lateral mostra os recentes.
- Inspetor: Sumário (títulos h1 a h3, acompanha a rolagem) e Propriedades.

## Mapa de comandos

| Menu | Comando | Atalho |
| --- | --- | --- |
| Arquivo | Abrir… (arquivo ou pasta) | ⌘O |
| Arquivo | Abrir Recente ▸, Limpar Menu | |
| Arquivo | Salvar / Salvar Como… | ⌘S / ⇧⌘S |
| Arquivo | Mostrar no Finder | |
| Arquivo | Copiar Caminho | ⌥⌘C |
| Arquivo | Imprimir… | ⌘P |
| Editar | Buscar ▸ Buscar… / Seguinte / Anterior | ⌘F / ⌘G / ⇧⌘G |
| Editar | Buscar ▸ Buscar nos Arquivos | ⌥⌘F |
| Visualizar | Mostrar/Ocultar Barra Lateral | ⌃⌘S |
| Visualizar | Mostrar/Ocultar Sumário | ⌃⌘I |
| Visualizar | Editar Markdown / Voltar à Leitura | ⇧⌘E |
| Visualizar | Mostrar/Ocultar Números de Linha | ⌥⌘L |
| Visualizar | Tamanho Real / Aumentar / Diminuir Texto | ⌘0 / ⌘+ / ⌘- |
| Visualizar | Largura da Leitura ▸, Tema ▸ | |
| Ir | Voltar / Avançar | ⌘[ / ⌘] |
| Ajuda | Guia do Lume, Atalhos de Teclado | |
| Dock | Abrir… | |

⌘E fica livre porque no Mac significa "Usar Seleção para Buscar".

## Estados vazios

- Nada aberto: `ContentUnavailableView` com Abrir… e Ver o Guia do Lume.
- Busca sem resultado: `ContentUnavailableView.search`.
- Documento sem títulos: texto curto no inspetor.

## Sensação

Calma. O documento é o protagonista; nada pisca, nada abre sozinho. A janela
abre sem foco, no último documento lido e no mesmo ponto da rolagem.

## Decisões

- Temas de leitura são da página, como no Livros: a interface segue o modo do
  Mac e o tema "Automático" (padrão) usa Papel no claro e Noite no escuro.
- Alterações não salvas: ponto no botão de fechar, ponto na linha da barra
  lateral, e a pergunta Salvar / Não Salvar / Cancelar ao fechar, sair ou
  abrir outra coisa.
- Erros aparecem em folha (sheet) na janela, nunca em aviso que some.
- A janela tem mínimo de 900 pt: abaixo disso as três colunas não cabem e o
  AppKit entra em loop de layout. Abaixo de 460 pt de documento, o sumário
  recolhe sozinho e volta quando há espaço.
