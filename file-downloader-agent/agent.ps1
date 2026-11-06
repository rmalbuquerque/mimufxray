# Agente de download para o MIM@UF (MicroStrategy) - versao PowerShell, sem instalacao.
# Uso:  powershell -ExecutionPolicy Bypass -File agent.ps1 [-Debug]
# As credenciais leem-se do ficheiro .env (COMPANY_USERNAME / COMPANY_PASSWORD).

param([switch]$Debug)
$ErrorActionPreference = 'Stop'

$cfg = Get-Content "$PSScriptRoot\config.json" -Raw | ConvertFrom-Json

if (Test-Path "$PSScriptRoot\.env") {
    Get-Content "$PSScriptRoot\.env" | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $k, $v = $line.Split('=', 2)
            [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process')
        }
    }
}

$user = [Environment]::GetEnvironmentVariable('COMPANY_USERNAME', 'Process')
$pass = [Environment]::GetEnvironmentVariable('COMPANY_PASSWORD', 'Process')
if (-not $user -or -not $pass) {
    throw "Defina COMPANY_USERNAME e COMPANY_PASSWORD no ficheiro .env (copie .env.example)."
}

$base = $cfg.base_url.TrimEnd('/')
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$script:html = ''
$script:lastUri = ''

if ($Debug -and -not (Test-Path "$PSScriptRoot\debug")) { New-Item -ItemType Directory "$PSScriptRoot\debug" | Out-Null }

function Save-Debug([string]$name) {
    if ($Debug) { $script:html | Out-File "$PSScriptRoot\debug\$name.html" -Encoding utf8 }
}

function Get-Attr([string]$tag, [string]$name) {
    if ($tag -match "$name\s*=\s`"([^`]*)`"") { return $matches[1] }
    if ($tag -match "$name\s*=\s*'([^']*)'") { return $matches[1] }
    return $null
}

function Get-HiddenFields([string]$pageHtml) {
    $fields = @{}
    foreach ($m in [regex]::Matches($pageHtml, '(?i)<input[^>]*type=["'']?hidden["'']?[^>]*>')) {
        $n = Get-Attr $m.Value 'name'
        if ($n) { $fields[$n] = [System.Net.WebUtility]::HtmlDecode((Get-Attr $m.Value 'value')) }
    }
    return $fields
}

function Invoke-Get([string]$url) {
    $r = Invoke-WebRequest -Uri $url -WebSession $session -UseBasicParsing
    $script:html = $r.Content
    $script:lastUri = $r.BaseResponse.ResponseUri.AbsoluteUri
    return $r
}

function Invoke-Post([string]$url, [hashtable]$fields) {
    $r = Invoke-WebRequest -Uri $url -WebSession $session -UseBasicParsing -Method Post -Body $fields
    $script:html = $r.Content
    $script:lastUri = $r.BaseResponse.ResponseUri.AbsoluteUri
    return $r
}

function Submit-CurrentPage([hashtable]$fields, [string]$debugName) {
    $body = Get-HiddenFields $script:html
    foreach ($k in $fields.Keys) { $body[$k] = $fields[$k] }
    Save-Debug $debugName
    return Invoke-Post $script:lastUri $body
}

function Resolve-Name([string]$selector) {
    if ($selector.StartsWith('#')) { return $selector.Substring(1) }
    if ($selector -match "name='([^']+)'") { return $matches[1] }
    return $selector
}

function Extract-HrefPattern([string]$selector) {
    if ($selector -match "href\*='([^']+)'") { return $matches[1] }
    return $null
}

function Find-Link([string]$pattern, [string]$text) {
    foreach ($m in [regex]::Matches($script:html, '(?is)<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>')) {
        $href = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
        $inner = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value) -replace '<[^>]+>', ''
        if ($pattern -and $href -notlike "*$pattern*") { continue }
        if ($text -and $inner -notlike "*$text*") { continue }
        if ($href -match '^https?://') { return $href }
        return $script:lastUri -replace '/[^/]*$', '/' + $href.TrimStart('/')
    }
    return $null
}

function Click-Link([string]$pattern, [string]$text, [string]$debugName) {
    $url = Find-Link $pattern $text
    if (-not $url) { throw "Link nao encontrado (pattern=$pattern text=$text). Veja debug." }
    Write-Host "A abrir: $url"
    Save-Debug $debugName
    return Invoke-Get $url
}

function Select-ByTitle([string]$title, [string]$debugName) {
    Save-Debug $debugName
    $url = Find-Link $null $title
    if ($url) { Write-Host "A selecionar '$title' via link"; return Invoke-Get $url }
    throw "Nao encontrei link para o elemento title='$title'. Envie a pasta debug."
}

function Wait-ReportDone([int]$timeoutSec) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        if ($script:html -notmatch 'Relat.+rio em execu') { Write-Host 'Relatorio concluido.'; return }
        Start-Sleep -Seconds 10
        Invoke-Get $script:lastUri | Out-Null
    }
    throw "O relatorio nao terminou em ${timeoutSec}s."
}

Write-Host '== Login =='
Invoke-Get "$base$($cfg.login.path)"
Submit-CurrentPage @{
    (Resolve-Name $cfg.login.username_selector) = $user
    (Resolve-Name $cfg.login.password_selector) = $pass
    (Resolve-Name $cfg.login.submit_selector)   = 'Login'
} '01-login' | Out-Null
Write-Host "Login enviado. URL: $script:lastUri"

Write-Host '== Navegacao inicial =='
foreach ($step in $cfg.navigation) {
    if ($step.click) {
        $p = Extract-HrefPattern $step.click
        Click-Link $p $null '02-nav' | Out-Null
    }
}

$outDir = Join-Path $PSScriptRoot $cfg.downloads.output_dir
New-Item -ItemType Directory $outDir -Force | Out-Null

foreach ($name in $cfg.reports.names) {
    Write-Host "== Relatorio $name =="
    Submit-CurrentPage @{ (Resolve-Name $cfg.reports.search_input) = $name } "03-search-$name" | Out-Null
    Click-Link $null $name "04-resultado-$name" | Out-Null

    $ov = $cfg.reports.overrides.$name
    $steps = if ($ov -and $ov.prompt_steps) { $ov.prompt_steps } else { $cfg.reports.prompt_steps }
    foreach ($st in $steps) {
        if ($st.click -match "title='([^']+)'") { Select-ByTitle $matches[1] "05-prompt-$name" | Out-Null }
        elseif ($st.click -match 'text-is\(''([^'']+)''\)') {
            Click-Link $null $matches[1] "05-prompt-$name" | Out-Null
        }
    }

    1..(1 + [int]$cfg.reports.rerun_clicks) | ForEach-Object {
        Submit-CurrentPage @{} "06-executar-$name-$_" | Out-Null
        Write-Host "Executar Relatorio enviado ($_)."
        Wait-ReportDone ($cfg.reports.report_wait_timeout_ms / 1000)
    }

    Write-Host "== Exportar $name =="
    foreach ($st in $cfg.export_steps) {
        $sel = $st.click
        if ($st.download) {
            $body = Get-HiddenFields $script:html
            $body[(Resolve-Name $sel)] = 'Exportar'
            Save-Debug "07-export-$name"
            $r = Invoke-WebRequest -Uri $script:lastUri -WebSession $session -UseBasicParsing -Method Post -Body $body -OutFile (Join-Path $outDir "$name.xlsx")
            Write-Host "Guardado: $name.xlsx"
        } else {
            if ($sel -match "value='([^']+)'") {
                Submit-CurrentPage @{ (Resolve-Name $sel) = $matches[1] } "07-export-$name" | Out-Null
            } else {
                Click-Link (Extract-HrefPattern $sel) $null "07-export-$name" | Out-Null
            }
        }
    }

    if ($cfg.reports.return_click) {
        Click-Link (Extract-HrefPattern $cfg.reports.return_click) 'Home' '08-home' | Out-Null
    }
}

Write-Host 'Concluido. Ficheiros em:' $outDir
