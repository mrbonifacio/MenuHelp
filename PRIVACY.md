# Privacidade

O MenuHelp foi projetado para funcionar localmente. Ele não possui conta,
analytics, telemetria, anúncios nem envio de conteúdo para servidores.

## Histórico do clipboard

Quando ativado, o MenuHelp observa o clipboard geral do macOS e armazena textos
e imagens em:

```text
~/Library/Application Support/MenuHelp/
```

O padrão é manter até 100 itens por 30 dias. As imagens têm um limite conjunto
de 200 MB. Esses valores podem ser alterados nas Preferências, e todo o
histórico pode ser apagado a qualquer momento.

Itens marcados por aplicativos compatíveis como confidenciais, transitórios ou
gerados automaticamente não são armazenados. Essa proteção depende de o
aplicativo de origem publicar esses marcadores corretamente.

Os dados são gravados como JSON e PNG, sem criptografia própria do MenuHelp. A
pasta usa permissão `0700` e os arquivos usam `0600`, limitando o acesso ao
usuário atual. Para proteção do disco desligado, recomenda-se manter o FileVault
ativado.

## Acessibilidade

A permissão de Acessibilidade é solicitada somente para:

- bloquear eventos do teclado durante o modo de limpeza;
- simular `Command + V` após uma escolha no histórico.

O atalho global `Shift + Command + V` é registrado pela API Carbon. O MenuHelp
não registra, transmite nem mantém um log das teclas pressionadas.

## Controle de brilho

O controle de monitores externos executa `m1ddc` ou `ddcctl` somente nos caminhos
padrão do Homebrew (`/opt/homebrew/bin` e `/usr/local/bin`). Esses programas não
são incluídos no MenuHelp e devem ser instalados separadamente pelo usuário.

## Remoção dos dados

Use **Preferências → Histórico do Clipboard → Apagar**. Para remover todos os
dados e preferências após encerrar o app, também podem ser excluídos a pasta
acima e o domínio de preferências correspondente ao bundle do MenuHelp.
