# Distribuir MenuHelp

## Pacote gratuito

Em um Mac com Xcode 26+, execute na raiz do checkout:

```sh
bash Scripts/package-release.sh 0.2.0
```

Isso gera em `dist/0.2.0/` um DMG com o app e atalho para Aplicativos, ZIP
alternativo, INSTALL.txt em dois idiomas e SHA256SUMS.txt. A saída não sobrescreve
pacotes existentes. Mova os arquivos anteriores para outro local antes de refazer
a mesma versão. O diretório temporário de compilação é removido automaticamente.

O MenuHelp é universal; seus helpers são nativos arm64 (m1ddc) e x86_64 (ddcctl).
Todos usam apenas bibliotecas do macOS. A fase de build do Xcode inclui os
helpers mesmo ao executar Command + R. Não requer Homebrew ou downloads no build.
Para inspecionar um pacote extraído, use:

```sh
bash Scripts/verify-bundle.sh /caminho/para/MenuHelp.app
```

Essa verificação cobre arquiteturas, assinaturas, bibliotecas externas,
localizações e fontes/licenças. Não substitui o teste do brilho em hardware
compatível, nem comprova notarização. Teste Intel e Apple Silicon, abertura
após download, preferências, clipboard e permissões antes de anunciar suporte.

## Publicar no GitHub

Atualize a versão/build em `MenuHelp.xcodeproj/project.pbxproj`, revise as notas
de release e compile. O commit publicado deve corresponder às fontes compiladas,
incluindo `ThirdParty/` e os scripts. Não versione a pasta `dist/`.

Exemplo para a versão 0.2.0, depois de commit/push do código:

```sh
git tag -a v0.2.0 -m 'MenuHelp 0.2.0'
git push origin v0.2.0
gh release create v0.2.0 \
  dist/0.2.0/MenuHelp-0.2.0-universal.dmg \
  dist/0.2.0/MenuHelp-0.2.0-universal.zip \
  dist/0.2.0/SHA256SUMS.txt dist/0.2.0/INSTALL.txt \
  --repo mrbonifacio/MenuHelp --verify-tag \
  --title 'MenuHelp 0.2.0' --notes-file Distribution/RELEASE-0.2.0.md
```

O GitHub fornece os arquivos Source code referentes à tag. Eles incluem as
fontes completas dos helpers distribuídos. Além disso, cada app carrega
`Contents/Resources/ThirdPartySources.zip` e `Licenses/`.
Em **Actions → Package release → Run workflow**, é possível gerar os pacotes
sem publicá-los automaticamente. Use o commit/tag correto ao executar o workflow.

## Assinatura e notarização opcionais

Por padrão, a assinatura é ad-hoc (`-`). Ela permite verificar integridade, mas
não comprova identidade e não evita autorização manual no Gatekeeper.
O certificado Apple Development não substitui Developer ID para esse objetivo.

Com Developer ID Application disponível e um perfil já configurado no Keychain
via `xcrun notarytool store-credentials`, execute:

```sh
MENUHELP_SIGN_IDENTITY='Developer ID Application: NOME (TEAMID)' \
MENUHELP_NOTARY_PROFILE='MenuHelp-notary' \
bash Scripts/package-release.sh 0.2.0
```

O script assina primeiro os helpers, depois o app, submete à Apple, anexa e
valida o ticket e só então gera os pacotes. Também notariza e valida o DMG.
Qualquer falha interrompe o processo. Não publique artefatos parciais.
Se notarizar uma versão futura, atualize INSTALL.txt e notas de release para
descrever a assinatura real. Nunca adicione certificados ou credenciais ao Git.

## Primeira abertura

O usuário instala apenas o MenuHelp. Builds sem notarização podem exigir
**Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim** depois da
primeira tentativa. Não use instruções para desativar Gatekeeper globalmente.
Referências: [Apple Support](https://support.apple.com/102445) e
[Developer ID](https://developer.apple.com/developer-id/).
