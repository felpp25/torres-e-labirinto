# Checagem de tipos do projeto inteiro com o luau-lsp (CLI), igual ao que o editor mostra.
# Uso (na raiz do projeto):  ./scripts/analyze.ps1
# Saída 0 = sem erros. As definições da API do Roblox são baixadas uma vez para .luau-lsp/ (fora do git).

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$defsDir = Join-Path $root ".luau-lsp"
$defsFile = Join-Path $defsDir "globalTypes.PluginSecurity.d.luau"
$defsUrl = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.PluginSecurity.d.luau"

if (-not (Test-Path $defsFile)) {
	New-Item -ItemType Directory -Force $defsDir | Out-Null
	Write-Host "Baixando definições da API do Roblox..."
	Invoke-WebRequest $defsUrl -OutFile $defsFile -UseBasicParsing
}

rojo sourcemap default.project.json -o sourcemap.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json "--definitions=@roblox=$defsFile" src
exit $LASTEXITCODE
