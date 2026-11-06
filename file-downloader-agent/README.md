# Agente de download de ficheiros

Agente em Python (Playwright) que faz login numa aplicação web da empresa e
descarrega ficheiros automaticamente para a pasta `downloads/`.

## Segurança

- As credenciais são lidas de variáveis de ambiente (`COMPANY_USERNAME`,
  `COMPANY_PASSWORD`), nunca ficam escritas no código.
- O ficheiro `.env` está no `.gitignore` — nunca o partilhe nem o commite.

## Instalação

```bash
pip install -r requirements.txt
playwright install chromium
# No Linux, se faltar bibliotecas do sistema:
sudo playwright install-deps chromium
```

## Configuração

1. Copie `.env.example` para `.env` e preencha as credenciais:
   ```bash
   cp .env.example .env
   ```
2. Edite `config.json` com os dados reais do software:
   - `base_url`: endereço da aplicação
   - `login`: caminho da página de login e seletores CSS dos campos
     (username, password, botão de submissão) e um texto da URL de sucesso
   - `navigation`: passos intermédios entre o login e os downloads; cada passo
     pode ter `click` (seletor CSS do elemento a clicar), `goto` (caminho
     direto) e `wait_url` (texto que deve aparecer na URL antes de continuar)
   - `downloads`: página com os ficheiros e o seletor CSS dos links de download
   - Para encontrar os seletores, abra a página no Chrome, clique com o botão
     direito no elemento → "Inspecionar" e copie o seletor.

## Execução

```bash
python agent.py
```

Os ficheiros descarregados ficam em `downloads/`.

## Notas

- Se o login usar autenticação de dois fatores (2FA/MFA), este agente não
  consegue automatizar esse passo — nesse caso, considere usar a API oficial
  do software com tokens.
- Execute apenas em software que lhe pertence ou para o qual tem autorização.
