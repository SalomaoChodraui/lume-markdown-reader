# Publicação do Lume

`tools/release.sh` gera `dist/Lume-<versão>.dmg`: binário universal (Apple
Silicon e Intel) com mínimo macOS 14, assinado com Developer ID e hardened
runtime, notarizado e grampeado. O workflow **Release macOS** roda o mesmo
script no GitHub Actions e publica o DMG numa GitHub Release.

## Segredos do repositório

Os mesmos da versão Tauri, em **Settings > Secrets and variables > Actions**:

| Segredo | Conteúdo |
| --- | --- |
| `APPLE_CERTIFICATE` | `.p12` do Developer ID Application, em Base64 |
| `APPLE_CERTIFICATE_PASSWORD` | senha do `.p12` |
| `APPLE_SIGNING_IDENTITY` | nome completo da identidade, por exemplo `Developer ID Application: Nome (TEAMID)` |
| `APPLE_ID` | Apple ID da notarização |
| `APPLE_PASSWORD` | senha específica de app |
| `APPLE_TEAM_ID` | Team ID de dez caracteres |

## Publicar uma versão

1. Atualize `CFBundleShortVersionString` em `Info.plist.in`.
2. Escreva `docs/release-notes/<versão>.md` e uma linha no `CHANGELOG.md`.
3. Rode os testes: `swift test`, `node tools/test-markdown.cjs`, `tools/selftest.sh`.
4. Abra **Actions > Release macOS > Run workflow**. A release sai como rascunho
   por padrão.
5. Baixe o DMG, instale num usuário limpo, abra e confira. Depois publique o
   rascunho.

## Release local

Com o Developer ID no Keychain e credenciais salvas uma vez com
`xcrun notarytool store-credentials lume`:

```bash
SIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" NOTARY_PROFILE=lume tools/release.sh
```

`--no-notarize` faz só o build universal, a assinatura e o DMG, para conferir
o pacote sem enviar nada à Apple.
