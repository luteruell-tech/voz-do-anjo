# Organizador de HD

Faz o inventário completo de um HD externo, separa os arquivos por tipo e ano e isola o lixo e os duplicados.
**Não apaga nada.** Tudo fica registrado e pode ser desfeito.

## Como usar (Windows)

1. Copie `ORGANIZAR_HD.bat` e `OrganizarHD.ps1` para a **mesma pasta** (a Área de Trabalho, por exemplo).
2. Dê dois cliques em `ORGANIZAR_HD.bat`.
   - Se aparecer "O Windows protegeu o computador", clique em **Mais informações → Executar assim mesmo**.
3. Digite a letra do HD (Enter = `I`).
4. Escolha **1 - INVENTÁRIO** primeiro. O relatório abre no navegador.
5. Confira o relatório. Se estiver tudo certo, rode de novo e escolha **2 - ORGANIZAR** (digite `SIM` para confirmar).
6. Se algo não ficou como você queria, escolha **3 - DESFAZER**.

## Como o HD fica depois

| Pasta | Conteúdo |
|---|---|
| `_ORGANIZADO\Fotos\2019\Viagem\` | Arquivos separados por tipo e por ano, mantendo o nome da pasta de origem |
| `_ORGANIZADO\Programas_e_Projetos\` | Programas, jogos e projetos, movidos **inteiros** para não quebrarem |
| `_LIXO_REVISAR\` | Temporários, Thumbs.db, restos de Mac, downloads incompletos, atalhos, logs e arquivos vazios |
| `_DUPLICADOS\` | Cópias idênticas (conferidas pelo conteúdo, não só pelo nome). O original fica em `_ORGANIZADO` |
| `_RELATORIO_HD\` | Relatório (HTML), planilha para Excel e registro dos movimentos (usado no Desfazer) |

Depois de conferir, você mesmo apaga `_LIXO_REVISAR` e `_DUPLICADOS`.

## Observações

- Tipos reconhecidos: fotos, vídeos, áudios, PDF, textos, planilhas, apresentações, livros, compactados, instaladores, design, e-mails, legendas e fontes. O que não for reconhecido vai para `Outros`.
- O ano usado é a data de modificação do arquivo.
- Pode rodar de novo quantas vezes quiser. Arquivos já organizados não são mexidos, e arquivos novos entram na organização.
- O programa não roda no disco do sistema (`C:`), por segurança.
- Pastas sem permissão de leitura ou com caminhos muito longos aparecem no relatório como falha e ficam onde estão.
