# MenuHelp

Utilitário open source de menu bar para macOS. O MenuHelp reúne monitoramento
do sistema, histórico local do clipboard, limpeza do teclado, prevenção de
repouso e controle DDC/CI de monitores externos.

> O projeto está em fase inicial (`0.1.0`). Antes de instalar uma versão
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
- brilho de monitores externos com `m1ddc` ou `ddcctl`.

## Requisitos

- macOS 15.7 ou superior;
- Xcode 26 ou superior para compilar;
- `m1ddc` em Apple Silicon ou `ddcctl` em Intel para brilho externo;
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

Apple Silicon:

```bash
brew install m1ddc
```

Mac Intel:

```bash
brew install ddcctl
```

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

O código pode ser compilado gratuitamente. Um `.app` destinado ao público deve
ser assinado com Developer ID, usar Hardened Runtime e ser notarizado pela
Apple. O projeto habilita Hardened Runtime na configuração Release, mas não
contém certificados nem credenciais de notarização.

Releases oficiais devem incluir o arquivo assinado/notarizado e seu checksum
SHA-256. Não é necessário publicar o app na Mac App Store.

## Contribuição e segurança

Leia [CONTRIBUTING.md](CONTRIBUTING.md) antes de abrir um pull request. Não
publique vulnerabilidades em issues; use o processo descrito em
[SECURITY.md](SECURITY.md).

## Licença

Distribuído sob a licença [MIT](LICENSE).
