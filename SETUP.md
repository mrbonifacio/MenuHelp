# Configuração de desenvolvimento

## Abrindo o projeto

1. Instale o Xcode indicado no README.
2. Abra `MenuHelp.xcodeproj`.
3. Em **Signing & Capabilities**, selecione seu time apenas se quiser executar
   um build assinado localmente. Não versione Team ID ou certificados.
4. Use o target `MenuHelp` e execute com `Command + R`.

O app usa `LSUIElement` e, portanto, aparece somente na barra de menus.

## Permissões durante o desenvolvimento

O macOS associa Acessibilidade à assinatura e ao caminho do aplicativo. Depois
de trocar assinatura ou localização, pode ser necessário remover e adicionar o
MenuHelp novamente em **Ajustes do Sistema → Privacidade e Segurança →
Acessibilidade**.

Sem Acessibilidade, o restante do app continua funcionando; limpeza do teclado
e colagem automática ficam indisponíveis.

## Checklist manual

- o painel abre ao clicar em toda a área do ícone da barra de menus;
- o monitoramento exibe CPU, RAM e disco do Mac;
- o toggle do clipboard pausa e retoma novas capturas;
- textos e imagens reaparecem depois de reiniciar o app;
- itens confidenciais/transitórios não entram no histórico;
- apagar o histórico remove o JSON e os PNGs registrados;
- `Shift + Command + V` abre a janela, permite navegar e confirmar;
- limpeza do teclado termina automaticamente após 30 segundos;
- Prevent Sleep ativa e desativa sem deixar uma assertion pendente;
- brilho mostra somente monitores externos que respondem ao DDC/CI.

## Build de Release

O target Release usa Hardened Runtime e mantém App Sandbox desativado. O
sandbox não é usado porque o app precisa de event tap global e executa os
backends DDC/CI instalados pelo Homebrew.

Para uma distribuição pública, use Xcode **Product → Archive → Distribute App →
Developer ID** e envie para notarização. Certificados, senhas e perfis nunca
devem ser adicionados ao repositório.
