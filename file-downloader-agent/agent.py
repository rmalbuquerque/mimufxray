"""Agente de download: faz login no MIM@UF (MicroStrategy), procura e executa
uma lista de relatórios e descarrega os ficheiros exportados.

As credenciais são lidas de variáveis de ambiente (COMPANY_USERNAME e
COMPANY_PASSWORD), definidas no ficheiro .env ou no ambiente do sistema.
Nunca são escritas em código.
"""

import json
import os
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

BASE_DIR = Path(__file__).resolve().parent


def load_env(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(
            f"Variável de ambiente {name} em falta. "
            "Defina-a no ficheiro .env (copie .env.example) ou no ambiente."
        )
    return value


def login(page, base_url: str, login_cfg: dict, username: str, password: str) -> None:
    page.goto(base_url + login_cfg["path"], timeout=login_cfg.get("timeout_ms", 15000))
    page.fill(login_cfg["username_selector"], username)
    page.fill(login_cfg["password_selector"], password)
    page.click(login_cfg["submit_selector"])
    page.wait_for_url(
        f"**{login_cfg['success_url_contains']}**",
        timeout=login_cfg.get("timeout_ms", 15000),
    )
    print(f"Login efetuado com sucesso. URL atual: {page.url}")


def run_navigation(page, base_url: str, steps: list) -> None:
    for i, step in enumerate(steps, 1):
        if "goto" in step:
            page.goto(base_url + step["goto"], timeout=step.get("timeout_ms", 30000))
        if "click" in step:
            page.click(step["click"], timeout=step.get("timeout_ms", 30000))
            print(f"Navegação passo {i}: clique em {step['click']}")
        if "wait_url" in step:
            page.wait_for_url(f"**{step['wait_url']}**", timeout=step.get("timeout_ms", 30000))


def run_report(page, rep_cfg: dict, name: str) -> None:
    timeout = rep_cfg.get("timeout_ms", 40000)
    search = rep_cfg["search_input"]
    page.fill(search, name)
    if rep_cfg.get("search_submit"):
        page.click(rep_cfg["search_submit"], timeout=timeout)
    else:
        page.press(search, "Enter")
    result = rep_cfg["result_link"].format(name=name)
    page.wait_for_selector(result, timeout=timeout)
    page.click(result)
    print(f"Relatório '{name}': encontrado e aberto.")

    page.wait_for_selector(rep_cfg["run_selector"], timeout=timeout)
    override = rep_cfg.get("overrides", {}).get(name, {})
    steps = override.get("prompt_steps", rep_cfg.get("prompt_steps", []))
    for step in steps:
        page.locator(step["click"]).first.click(timeout=timeout)
    page.click(rep_cfg["run_selector"], timeout=timeout)
    print(f"Relatório '{name}': filtros 2026 aplicados e execução lançada.")
    page.wait_for_load_state("networkidle", timeout=timeout)
    for _ in range(rep_cfg.get("rerun_clicks", 0)):
        page.wait_for_selector(rep_cfg["run_selector"], timeout=timeout)
        page.click(rep_cfg["run_selector"], timeout=timeout)
        print(f"Relatório '{name}': Executar Relatório clicado novamente.")
        page.wait_for_load_state("networkidle", timeout=timeout)
    wait_for_report(page, rep_cfg)


def wait_for_report(page, rep_cfg: dict) -> None:
    timeout = rep_cfg.get("report_wait_timeout_ms", 600000)
    page.wait_for_selector(rep_cfg["run_selector"], state="hidden", timeout=timeout)
    print("Relatório concluído.")


def run_export_steps(page, steps: list, output_dir: Path, timeout: int) -> list:
    saved = []
    for i, step in enumerate(steps, 1):
        if step.get("download"):
            with page.expect_download(timeout=timeout) as dl_info:
                page.click(step["click"], timeout=timeout)
            download = dl_info.value
            target = output_dir / download.suggested_filename
            download.save_as(target)
            saved.append(str(target))
            print(f"Export passo {i}: guardado em {target.name}")
        else:
            page.click(step["click"], timeout=timeout)
            print(f"Export passo {i}: clique em {step['click']}")
        if "wait_url" in step:
            page.wait_for_url(f"**{step['wait_url']}**", timeout=timeout)
    return saved


def main() -> None:
    load_env(BASE_DIR / ".env")
    config = json.loads((BASE_DIR / "config.json").read_text(encoding="utf-8"))

    username = require_env("COMPANY_USERNAME")
    password = require_env("COMPANY_PASSWORD")
    base_url = config["base_url"].rstrip("/")

    output_dir = BASE_DIR / config["downloads"]["output_dir"]
    output_dir.mkdir(parents=True, exist_ok=True)
    dl_timeout = config["downloads"].get("timeout_ms", 60000)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=config["browser"].get("headless", True))
        context = browser.new_context(accept_downloads=True)
        page = context.new_page()
        try:
            login(page, base_url, config["login"], username, password)
            run_navigation(page, base_url, config.get("navigation", []))
            all_saved = []
            for name in config["reports"]["names"]:
                run_report(page, config["reports"], name)
                all_saved += run_export_steps(
                    page, config.get("export_steps", []), output_dir, dl_timeout
                )
                if config["reports"].get("return_click"):
                    page.locator(config["reports"]["return_click"]).first.click(timeout=dl_timeout)
                else:
                    page.go_back()
                page.wait_for_load_state("networkidle", timeout=dl_timeout)
            print(f"Concluído: {len(all_saved)} ficheiro(s) descarregados.")
        finally:
            browser.close()


if __name__ == "__main__":
    sys.exit(main())
