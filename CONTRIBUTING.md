# Como contribuir

Obrigado por ajudar o MenuHelp.

## Preparação

1. Faça um fork e crie uma branch curta para a mudança.
2. Abra `MenuHelp.xcodeproj` usando a versão de Xcode indicada no README.
3. Compile localmente sem adicionar seu `xcuserdata`, certificados ou Team ID.
4. Mantenha cada pull request focado em um único problema.

## Antes de enviar

Execute:

```bash
xcodebuild \
  -project MenuHelp.xcodeproj \
  -target MenuHelp \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Confirme também que:

- não existem tokens, certificados, dados de clipboard ou caminhos pessoais;
- novas permissões possuem justificativa visível para o usuário;
- mudanças no clipboard respeitam conteúdo confidencial e transitório;
- processos externos usam argumentos separados, nunca comandos montados para shell;
- o README e `PRIVACY.md` continuam descrevendo o comportamento real.

Falhas de segurança devem seguir `SECURITY.md`, não uma issue pública.
