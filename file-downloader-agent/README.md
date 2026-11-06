# Agente de download automático — MIM@UF (MicroStrategy)

Agente que faz login no **MIM@UF** (`https://mimuf-alentejo.min-saude.pt/MicroStrategy/asp`),
procura e executa 3 relatórios com os filtros de **2026** e exporta cada um para
**Excel com formatação**, guardando os ficheiros em `downloads/`.

Relatórios: `P02.01.R01`, `P02.01.R03`, `P02.01.R05`

> Guia ilustrado passo a passo: [MANUAL.md](MANUAL.md) (com diagramas do fluxo)

## Início rápido (sem instalar nada — PowerShell)

Ideal para máquinas de empresa sem permissões de administrador:

1. Transfira o projeto: [PR #1](https://github.com/rmalbuquerque/mimufxray/pull/1) → **Code** → **Download ZIP** → extraia
2. Na pasta `file-downloader-agent`, copie `.env.example` para `.env` e preencha:
   ```
   COMPANY_USERNAME=o.teu.utilizador
   COMPANY_PASSWORD=a.tua.palavra.passe
   ```
3. Abra o PowerShell na pasta (barra de endereço → `powershell` → Enter) e corra:
   ```powershell
   powershell -ExecutionPolicy Bypass -File agent.ps1
   ```
4. Os 3 ficheiros Excel aparecem em `downloads/`

Em caso de erro: `powershell -ExecutionPolicy Bypass -File agent.ps1 -Debug` e envie a mensagem de erro + pasta `debug/`.

## Com Python (se puder instalar)

```bash
pip install -r requirements.txt
playwright install chromium
# Linux: sudo playwright install-deps chromium
cp .env.example .env        # preencher credenciais
python agent.py
```

## Ficheiros

| Ficheiro | Descrição |
|----------|-----------|
| `agent.py` | Agente principal (Python + Playwright) |
| `agent.ps1` | Mesma lógica em PowerShell puro (sem instalação) |
| `config.json` | Todo o fluxo configurável: URL, login, navegação, relatórios, exportação |
| `.env.example` | Modelo para as credenciais |
| `MANUAL.md` + `docs/*.svg` | Manual ilustrado com os fluxogramas |

## Como funciona o fluxo

Login → abrir projeto "Hierarquia dos Locais 2015" → por cada relatório:
pesquisar → abrir → selecionar 2026 → "Executar Relatório" (×2) → aguardar
"Relatório em execução" terminar → Exportar → Excel com formatação →
"Exportar" → ficheiro em `downloads/` → Home → relatório seguinte.

Toda a lógica está em `config.json` (seletores, relatórios, passos de
exportação); os scripts não precisam de alterações para ajustes simples.

## Segurança

- As credenciais (`COMPANY_USERNAME`, `COMPANY_PASSWORD`) vêm apenas do `.env`
  local — nunca ficam no código nem no git (`.gitignore` protege o `.env`)
- O agente corre localmente e só contacta o servidor do MIM@UF
- Use apenas com a sua conta e relatórios a que tem acesso

## Limitações

- Se o login usar 2FA/MFA, a automação não consegue esse passo — nesse caso
  use a API oficial do software com tokens
