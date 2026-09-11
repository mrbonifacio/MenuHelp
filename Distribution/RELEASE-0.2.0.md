MenuHelp 0.2.0 — instalação em um único aplicativo / single-app installation

## Download e instalação

Baixe **MenuHelp-0.2.0-universal.dmg**, abra e arraste MenuHelp para Applications.
Alternativa: descompacte o ZIP e mova o app para Aplicativos.
Requer **macOS 15.7 ou superior**, em Apple Silicon ou Intel.

Esta versão usa assinatura ad-hoc e **não é notarizada pela Apple**. Na primeira
abertura, após tentar abrir o app, use **Ajustes do Sistema → Privacidade e
Segurança → Abrir Mesmo Assim**, se você confia na origem do download.
[Instruções oficiais da Apple](https://support.apple.com/102445).
Não é necessário desativar o Gatekeeper nem instalar ferramentas extras.

## Novidades

- Controle DDC/CI incluído: m1ddc nativo em Apple Silicon e ddcctl nativo em Intel.
- Homebrew, Xcode e Rosetta não são necessários para utilizar o app.
- Português brasileiro e inglês, com seleção nas configurações.
- Iniciar com o Mac e persistência das opções.
- Prevent Sleep mantém o sistema e a tela ativos durante inatividade.
- Menu do ícone com acesso às configurações e encerramento do app.

O brilho depende de suporte DDC/CI no monitor, porta, cabo e dock; não há
garantia de compatibilidade com todos os monitores. Acessibilidade é necessária
para colagem automática e limpeza do teclado. O aplicativo funciona localmente,
sem telemetria. O histórico pode conter dados sensíveis e não tem criptografia
própria: consulte a política de privacidade no repositório.

Validação desta versão: build universal, integridade do DMG, assinaturas ad-hoc,
ausência de bibliotecas externas e leitura de brilho do AOC 27G4 em Apple Silicon
usando somente o helper incluído. A execução em um Mac Intel e a primeira abertura
em outro Mac com Gatekeeper ainda precisam de validação em hardware independente.

## English

Download the universal DMG, open it, and drag MenuHelp to Applications.
Requires macOS 15.7+. Brightness helpers are included for Apple Silicon and Intel;
no Homebrew, Xcode or Rosetta is needed. This build is ad-hoc signed and **not
Apple-notarized**. After the first blocked launch, use **System Settings → Privacy
& Security → Open Anyway** if you trust the download source.
Hardware brightness requires a compatible DDC/CI monitor and connection.

## Fontes, licenças e verificação / Sources, licenses and verification

`SHA256SUMS.txt` contém os hashes dos downloads. Fontes completas do MenuHelp e
dos helpers estão no arquivo **Source code** desta mesma versão. As fontes dos
helpers, licenças e script de build também estão incluídos dentro do próprio app
em `Contents/Resources/ThirdPartySources.zip` e `Contents/Resources/Licenses`.
MenuHelp e m1ddc: MIT. O programa separado ddcctl: GPL-3.0.

Checksums are provided in `SHA256SUMS.txt`. Complete corresponding source is
available in this release's **Source code** archive, including `ThirdParty/` and
`Scripts/`. The app also ships the helper sources, build script and licenses.
