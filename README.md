# MenuHelp

Utilitário open source de menu bar para macOS. O MenuHelp reúne monitoramento
do sistema, histórico local do clipboard, limpeza do teclado, prevenção de
repouso e controle DDC/CI de monitores externos.

> O projeto está em fase inicial (`0.2.0`). Antes de instalar uma versão
> distribuída por terceiros, confira a assinatura e a origem do arquivo.

## Funcionalidades

- medidores ativáveis de CPU, RAM e armazenamento;
- histórico de textos e imagens em uma janela separada;
- atalho global `Shift + Command + V`, com navegação por `↑`/`↓` e `Enter`;
- retenção configurável de 50, 100, 250 ou 500 itens;
- exclusão automática em 7, 30 ou 90 dias, ou sem prazo;
- limite conjunto de 200 MB para imagens;
- bloqueio temporário do teclado por 30 segundos;
- Prevent Sleep;
- brilho de monitores externos com `m1ddc` ou `ddcctl` já incluídos;
- português brasileiro e inglês, com idioma selecionável;
- início automático com o Mac e preferências persistentes.

## Download e instalação

[**Baixar MenuHelp para Mac — versão mais recente**](https://github.com/mrbonifacio/MenuHelp/releases/latest)

Baixe o arquivo `MenuHelp-0.2.0-universal.dmg`, abra e arraste **MenuHelp** para
**Applications / Aplicativos**. Abra o app por essa pasta; o ícone aparece na
barra de menus. O ZIP é uma alternativa ao DMG.

O pacote contém tudo que o app precisa: **não instale Homebrew, Xcode, m1ddc,
ddcctl ou Rosetta** para utilizá-lo. Requer macOS 15.7 ou superior.

A versão gratuita é assinada ad-hoc, sem Developer ID ou notarização da Apple.
Se o macOS impedir a primeira abertura, depois de tentar abrir o app, use
**Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**, se você
confia na origem do download. Siga as [instruções da Apple](https://support.apple.com/102445).
Não é necessário desativar o Gatekeeper. Macs gerenciados podem restringir essa
autorização. Para atualizar, encerre o app e substitua-o em Aplicativos.

English: download the universal DMG, drag MenuHelp into Applications and open it.
This free build is not notarized; after a blocked first launch use **System
Settings → Privacy & Security → Open Anyway**, if you trust the source.
No extra software is required. See [installation instructions](Distribution/INSTALL.txt).

## Requisitos

- macOS 15.7 ou superior;
- Xcode 26 ou superior para compilar;
- monitor externo e conexão compatíveis com DDC/CI para brilho externo;
- permissão de Acessibilidade para limpeza do teclado e colagem automática.

## Como compilar

1. Clone o repositório.
2. Abra `MenuHelp.xcodeproj` no Xcode.
3. Selecione seu Mac como destino.
4. Compile e execute com `Command + R`.

Também é possível verificar o build sem assinatura:

```bash
xcodebuild \
  -project MenuHelp.xcodeproj \
  -target MenuHelp \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Brilho externo

Os executáveis nativos são compilados automaticamente pelo Xcode a partir de
fontes fixadas em [ThirdParty](ThirdParty/README.md): `m1ddc` para Apple Silicon e
`ddcctl` para Intel. O app executa somente os helpers dentro de seu próprio pacote.

O monitor precisa oferecer DDC/CI e essa opção deve estar habilitada em seu
menu. Alguns docks, cabos e adaptadores não encaminham comandos DDC/CI.

## Privacidade e permissões

O MenuHelp não faz chamadas de rede e não possui telemetria. O histórico fica
somente em `~/Library/Application Support/MenuHelp/`, com acesso restrito ao
usuário atual. Ele pode ser pausado no painel e apagado nas Preferências ou na
janela do histórico.

O conteúdo é salvo como JSON e PNG, sem criptografia própria. Itens marcados
como confidenciais ou transitórios por aplicativos compatíveis são ignorados.
Consulte [PRIVACY.md](PRIVACY.md) para os detalhes e limitações.

Acessibilidade é usada para bloquear o teclado durante a limpeza e simular
`Command + V` após a seleção de um item. O app não mantém log das teclas.

## Distribuição

Gere gratuitamente o DMG, ZIP e checksums com:

```bash
bash Scripts/package-release.sh 0.2.0
```

Os arquivos ficam em `dist/0.2.0/`. O script compila Intel + Apple Silicon,
inclui os dois helpers e suas fontes/licenças, assina ad-hoc e verifica o pacote.
A assinatura ad-hoc não identifica o desenvolvedor perante o Gatekeeper.
O workflow **Package release** também gera esses arquivos como artifacts.

O script suporta Developer ID e notarização opcionais quando houver certificado
e credenciais. Consulte [RELEASING.md](RELEASING.md). A distribuição é pelo GitHub
Releases, sem necessidade de Mac App Store.

## Contribuição e segurança

Leia [CONTRIBUTING.md](CONTRIBUTING.md) antes de abrir um pull request. Não
publique vulnerabilidades em issues; use o processo descrito em
[SECURITY.md](SECURITY.md).

## Licença

O código do MenuHelp está sob [MIT](LICENSE). Os componentes distribuídos junto
mantêm suas próprias licenças: m1ddc (MIT) e o executável separado ddcctl (GPL-3.0).
Fontes completas, instruções de compilação e avisos estão em
[ThirdParty](ThirdParty/README.md) e dentro do app.
