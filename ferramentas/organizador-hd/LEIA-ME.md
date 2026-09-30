# Organizador de HD — QG LUTERUEL TECH

Faz o inventário do HD inteiro e organiza tudo dentro de `QG LUTERUEL TECH`, nas gavetas definidas em `REGRAS.txt`.

## Como usar (Windows)

1. Coloque **os 3 arquivos na mesma pasta**: `ORGANIZAR_HD.bat`, `OrganizarHD.ps1` e `REGRAS.txt`.
2. Dê dois cliques em `ORGANIZAR_HD.bat` (se o Windows avisar, clique em **Mais informações → Executar assim mesmo**).
3. Digite a letra do HD (Enter = `I`).
4. **1 - INVENTÁRIO**: só lê e mostra como vai ficar. Não mexe em nada.
5. **2 - ORGANIZAR**: move de verdade (digite `SIM`).
6. **3 - DESFAZER**: devolve tudo ao lugar original.
7. **4 - LIMPAR**: apaga de vez a `RECICLAGEM` e as cópias da `DUBLES` (digite `APAGAR`). Antes de apagar cada cópia, confere de novo se o original existe e é idêntico.

## Estrutura

```
QG LUTERUEL TECH
├── IMAGEM                          (png, prints, logos, psd...)
├── DOWNLOADS
│   └── GAVETA DA BAGUNÇA           (não identificados; mantém o caminho original)
├── DOCUMENTOS PESSOAIS
│   └── DOCUMENTOS PF               (RG, CPF, CNH, IR, certidões, certificado digital...)
├── INSTALADORES INTELIGÊNCIA
│   ├── INTELIGÊNCIA LOCAL          (Ollama, LM Studio, modelos .gguf...)
│   ├── INTELIGÊNCIA ONLINE         (ChatGPT, Claude, Gemini, Copilot...)
│   ├── VIRTUAL BOX                 (máquinas virtuais movidas inteiras)
│   ├── KALI LINUX
│   └── OUTROS INSTALADORES         (.exe, .msi, .apk, .iso sem tema)
├── LOJAS ONLINE
│   ├── SHOPEE
│   └── MELI
├── ARQUIVOS PESSOAIS
│   ├── DOCUMENTOS · CERTIFICADOS · RECEITAS
│   ├── FOTOS\ano · VÍDEOS\ano · MÚSICAS E ÁUDIOS
│   └── LIVROS · EMAILS E CONTATOS
├── PROJETOS                        (movidos inteiros)
│   ├── HTML\LOCATUS · ORGANIZAÇÃO PC · TERUGAN
│   ├── APP WEB\VOZ DO ANJO · AMARA · A BELA CONQUISTA
│   └── OUTROS PROJETOS E PROGRAMAS
├── CIBERSEGURANÇA\PROMPTS · RESULTADOS
├── INVESTIGADOR JURÍDICO\PROMPTS · RESULTADOS
├── ADVOCACIA                       (mantém as subpastas: cliente\processo)
├── RECICLAGEM                      (lixo)
└── DUBLES                          (cópias idênticas)
```

## Como cada arquivo é decidido (nesta ordem)

1. **Projeto**: pasta com o nome do projeto é movida inteira.
2. **Assunto**: palavra-chave no nome do arquivo ou das pastas (ex.: "petição" → ADVOCACIA, "shopee" → SHOPEE).
3. **Tipo**: pela extensão (foto, vídeo, documento...).
4. **Resto**: vai para GAVETA DA BAGUNÇA, para você identificar.

A planilha do inventário tem a coluna **Regra**, que mostra por que cada arquivo foi para cada gaveta.

## Duplicados

- Cópia = **mesmo tamanho e mesmo conteúdo** (impressão digital MD5). Pega até cópias com outro nome.
- Fica o de nome original (sem "cópia", "copy" ou "(1)"); em empate, o mais antigo.
- **Mesmo nome, tamanho diferente** = versões diferentes. Não são mexidos; aparecem numa lista à parte.

## Ajustar as regras

Abra `REGRAS.txt` no Bloco de Notas, acrescente palavras na linha da gaveta e salve. Depois rode o INVENTÁRIO de novo para conferir.
