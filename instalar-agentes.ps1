<#
  instalar-agentes.ps1
  Instala la configuracion de agentes de Claude Code en el repo justin-pms
  y crea la rama develop.

  Uso (desde la carpeta raiz del repo justin-pms):
    powershell -ExecutionPolicy Bypass -File ..\justin-pms-setup\instalar-agentes.ps1
#>

# Continue: en PowerShell 5.1, "Stop" convierte en error cualquier salida de git/gh por stderr.
$ErrorActionPreference = "Continue"
function Revisar($msg) { if ($LASTEXITCODE -ne 0) { throw $msg } }
$origen = $PSScriptRoot
$repo   = (Get-Location).Path

function Paso($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    OK  $msg" -ForegroundColor Green }
function Aviso($msg){ Write-Host "    !!  $msg" -ForegroundColor Yellow }

# 1. Validaciones
Paso "Validando entorno"
if (-not (Test-Path (Join-Path $repo "pnpm-workspace.yaml"))) {
  throw "Ejecuta este script desde la raiz del repo justin-pms (no encuentro pnpm-workspace.yaml)."
}
foreach ($cmd in @("git","gh","pnpm","claude")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "Falta '$cmd'. Instalalo antes de continuar (gh: winget install -e --id GitHub.cli)."
  }
}
gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI no esta autenticado. Ejecuta: gh auth login" }
if (git status --porcelain) { throw "Tienes cambios sin commit. Haz commit o stash antes de seguir." }
$remoto = git remote get-url origin
if ($remoto -match "TelivityAI") { throw "origin apunta a TelivityAI. Configura origin a tu repo privado primero." }
Ok "Repo: $repo"
Ok "origin: $remoto"

# 2. Rama develop
Paso "Preparando rama develop"
git fetch origin --quiet
git checkout main --quiet; Revisar "No pude cambiar a main"
git pull origin main --quiet; Revisar "No pude actualizar main"
$existeRemota = git ls-remote --heads origin develop
if ($existeRemota) {
  git checkout -B develop origin/develop --quiet; Revisar "No pude cambiar a develop"
  git branch --set-upstream-to=origin/develop develop *> $null
  Ok "develop ya existia, actualizada"
} else {
  git checkout -b develop --quiet; Revisar "No pude crear develop"
  Ok "develop creada desde main"
}

# 3. Copiar configuracion
Paso "Copiando agentes, comandos y documentacion"
$claudeDir = Join-Path $repo ".claude"
New-Item -ItemType Directory -Force -Path (Join-Path $claudeDir "agents")   | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $claudeDir "commands") | Out-Null

$settingsDestino = Join-Path $claudeDir "settings.json"
if (Test-Path $settingsDestino) {
  Copy-Item $settingsDestino "$settingsDestino.haip.bak" -Force
  Aviso "Ya habia .claude/settings.json; respaldo en settings.json.haip.bak. Revisa y combina si hacia falta algo."
}
Copy-Item (Join-Path $origen ".claude\settings.json") $settingsDestino -Force
Copy-Item (Join-Path $origen ".claude\agents\*.md")   (Join-Path $claudeDir "agents")   -Force
Copy-Item (Join-Path $origen ".claude\commands\*.md") (Join-Path $claudeDir "commands") -Force

$docsDestino = Join-Path $repo "docs\project"
New-Item -ItemType Directory -Force -Path $docsDestino | Out-Null
Copy-Item (Join-Path $origen "docs\project\*") $docsDestino -Recurse -Force
Ok "Archivos copiados"

# 4. Importar ORQUESTACION.md desde CLAUDE.md (una sola linea, minimo conflicto con upstream)
Paso "Enlazando docs/project/ORQUESTACION.md en CLAUDE.md"
$claudeMd = Join-Path $repo "CLAUDE.md"
$linea = "@docs/project/ORQUESTACION.md"
if (-not (Select-String -Path $claudeMd -SimpleMatch $linea -Quiet)) {
  Add-Content -Path $claudeMd -Value "`n## Proyecto Justin/Jurassic`n$linea" -Encoding UTF8
  Ok "Linea agregada al final de CLAUDE.md"
} else { Ok "CLAUDE.md ya la tenia" }

# 5. Commit y push de develop
Paso "Commit y push de develop"
git add .claude docs/project CLAUDE.md
git commit -m "chore(agentes): configuracion de subagentes, backlog y flujo develop" --quiet; Revisar "Fallo el commit"
git push -u origin develop --quiet; Revisar "Fallo el push de develop"
Ok "develop publicada"

# 6. Rama por defecto = develop (los PR apuntan ahi por defecto)
Paso "Configurando develop como rama por defecto en GitHub"
gh repo edit --default-branch develop *> $null
if ($LASTEXITCODE -ne 0) { Aviso "No pude cambiar la rama por defecto; hazlo en GitHub > Settings > General." } else {
Ok "Rama por defecto: develop" }

Write-Host "`nListo. Siguiente paso:" -ForegroundColor Green
Write-Host "  1. docker compose up -d postgres redis"
Write-Host "  2. claude"
Write-Host "  3. Dentro de Claude Code: Shift+Tab hasta 'auto mode', luego /siguiente-historia BASE-001"
