# Publicação do Lume para macOS

O workflow `Release macOS` compila as arquiteturas Intel e Apple Silicon,
combina as duas em um aplicativo universal, assina com Developer ID, envia para
notarização da Apple e publica o DMG em uma GitHub Release.

## Pré-requisitos Apple

- associação ativa ao Apple Developer Program
- certificado `Developer ID Application` com sua chave privada
- senha específica de app para o Apple ID usado na notarização
- Team ID da conta Apple Developer

A conta **Account Holder** precisa emitir o certificado Developer ID. Contas
gratuitas não podem notarizar aplicativos distribuídos fora da App Store.

## Segredos do repositório

Cadastre estes segredos em **Settings → Secrets and variables → Actions**:

| Segredo | Conteúdo |
| --- | --- |
| `APPLE_CERTIFICATE` | arquivo `.p12` exportado e codificado em Base64 |
| `APPLE_CERTIFICATE_PASSWORD` | senha escolhida ao exportar o `.p12` |
| `APPLE_SIGNING_IDENTITY` | nome completo da identidade Developer ID Application |
| `APPLE_ID` | Apple ID usado na notarização |
| `APPLE_PASSWORD` | senha específica de app, não a senha principal |
| `APPLE_TEAM_ID` | Team ID de dez caracteres |

Para codificar o certificado sem quebras de linha no macOS:

```bash
base64 -i DeveloperID.p12 | pbcopy
```

Não registre o certificado, senhas ou chaves no Git.

## Criar a release

1. Atualize a versão em `package.json`, `src-tauri/Cargo.toml` e
   `src-tauri/tauri.conf.json`.
2. Atualize o `CHANGELOG.md` e confirme que os três valores de versão coincidem.
3. Execute os testes locais indicados no README.
4. Abra **Actions → Release macOS → Run workflow**.
5. Baixe o DMG publicado e valide a instalação em um usuário ou Mac limpo.

Referência: [assinatura e notarização para macOS no Tauri](https://v2.tauri.app/distribute/sign/macos/).
