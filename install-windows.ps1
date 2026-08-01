param(
    [string]$InstallRoot = "$HOME\lumen-gspice"
)

$ErrorActionPreference = "Stop"

function Require-Command($Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found on PATH."
    }
}

function Clone-Or-Update($Url, $Path) {
    if (Test-Path -LiteralPath $Path) {
        git -C $Path pull --ff-only
    } else {
        git clone $Url $Path
    }
}

Require-Command git
Require-Command cmake
Require-Command python

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

$gspice = Join-Path $InstallRoot "GSPICE"
$lumen = Join-Path $InstallRoot "Lumen_Circuit_Studio"

Clone-Or-Update "https://github.com/hegdeshreesha/GSPICE.git" $gspice
Clone-Or-Update "https://github.com/hegdeshreesha/Lumen_Circuit_Studio.git" $lumen

cmake -S $gspice -B (Join-Path $gspice "build")
cmake --build (Join-Path $gspice "build") --config Release

Push-Location $lumen
.\scripts\bootstrap_dev.ps1
.\.venv\Scripts\python.exe scripts\verify_environment.py
Pop-Location

Write-Host ""
Write-Host "GSPICE built in: $gspice"
Write-Host "GSPICE executable:"
Write-Host "  $(Join-Path $gspice 'build\Release\gspice.exe')"
Write-Host "Lumen installed in: $lumen"
Write-Host "Start Lumen with:"
Write-Host "  cd $lumen"
Write-Host '  $env:QT_QPA_PLATFORM = "windows"'
Write-Host "  .\.venv\Scripts\pythonw.exe -m lumen"
