param(
    [string]$InstallRoot = "$HOME\lumen-gspice",
    [string]$MsysRoot = "C:\msys64",
    [switch]$CheckOnly,
    [switch]$NoInstall
)

$ErrorActionPreference = "Stop"
$InstallerVersion = "2026-08-12.2"

function Test-Command($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Show-Check($Name, $Ok, $Detail = "") {
    $mark = if ($Ok) { "[OK]" } else { "[MISSING]" }
    $color = if ($Ok) { "Green" } else { "Yellow" }
    $suffix = if ($Detail) { " - $Detail" } else { "" }
    Write-Host "$mark $Name$suffix" -ForegroundColor $color
}

function Install-Winget($Id) {
    winget install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements
}

function Get-PythonCommand {
    if (Test-Command python) { return "python" }
    if (Test-Command py) { return "py" }
    return ""
}

function Get-MsysBash {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($MsysRoot, "C:\msys64")) {
        if ($root -and -not $roots.Contains($root)) { $roots.Add($root) }
    }
    if ($env:LOCALAPPDATA) {
        $root = Join-Path $env:LOCALAPPDATA "Programs\MSYS2"
        if (-not $roots.Contains($root)) { $roots.Add($root) }
    }
    if ($env:ProgramFiles) {
        $root = Join-Path $env:ProgramFiles "MSYS2"
        if (-not $roots.Contains($root)) { $roots.Add($root) }
    }

    foreach ($root in $roots) {
        $bash = Join-Path $root "usr\bin\bash.exe"
        $pacman = Join-Path $root "usr\bin\pacman.exe"
        $ucrt = Join-Path $root "ucrt64\bin"
        if (
            (Test-Path -LiteralPath $bash) -and
            (Test-Path -LiteralPath $pacman) -and
            (Test-Path -LiteralPath $ucrt)
        ) {
            $script:MsysRoot = $root
            return $bash
        }
    }
    return ""
}

function Invoke-Msys {
    param(
        [string]$Bash,
        [string]$Script
    )
    $resolved = (Resolve-Path -LiteralPath $Bash).Path
    if ($resolved -match "\\Windows\\System32\\" -or $resolved -match "\\WindowsApps\\" -or $resolved -match "\\wsl") {
        throw "Refusing to use WSL bash: $resolved. Install MSYS2 UCRT64 or pass -MsysRoot C:\msys64."
    }
    Write-Host "Using MSYS2 bash: $resolved"
    & $Bash -lc $Script
    if ($LASTEXITCODE -ne 0) {
        throw "MSYS2 command failed with exit code $LASTEXITCODE."
    }
}

Write-Host "Lumen/GSPICE MSYS2 UCRT64 installer $InstallerVersion"
Write-Host "Checking lightweight Windows prerequisites..."
$bash = Get-MsysBash
$python = Get-PythonCommand
$checks = [ordered]@{
    "winget" = Test-Command winget
    "MSYS2" = [bool]$bash
    "Git for Windows" = Test-Command git
    "Windows Python 3" = [bool]$python
}

Show-Check "winget" $checks["winget"]
Show-Check "MSYS2" $checks["MSYS2"] $bash
Show-Check "Git for Windows" $checks["Git for Windows"]
Show-Check "Windows Python 3" $checks["Windows Python 3"] $python

$missing = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($CheckOnly) {
    if ($missing.Count) {
        throw "Missing prerequisites: $($missing -join ', ')"
    }
    Write-Host "All prerequisites are present."
    exit 0
}

if ($missing.Count) {
    if ($NoInstall) {
        throw "Missing prerequisites: $($missing -join ', ')"
    }
    if (-not $checks["winget"]) {
        throw "winget is required for one-command installation of MSYS2/Python."
    }
    if (-not $checks["MSYS2"]) { Install-Winget "MSYS2.MSYS2" }
    if (-not $checks["Git for Windows"]) { Install-Winget "Git.Git" }
    if (-not $checks["Windows Python 3"]) { Install-Winget "Python.Python.3.12" }
}

$bash = Get-MsysBash
if (-not $bash) {
    throw "MSYS2 UCRT64 was not found. If MSYS2 was just installed, open a new PowerShell window and rerun this script. Do not run it from WSL."
}
Write-Host "MSYS2 root: $MsysRoot"
$python = Get-PythonCommand
if (-not $python) {
    throw "Windows Python was not found after install. Open a new PowerShell window and rerun this script."
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

$env:LUMEN_INSTALL_ROOT_WIN = (Resolve-Path -LiteralPath $InstallRoot).Path
$msysScript = @"
set -euo pipefail
export MSYSTEM=UCRT64
export CHERE_INVOKING=1
export PATH=/ucrt64/bin:/usr/bin:`$PATH

pacman -Syuu --needed --noconfirm || true
pacman -Syuu --needed --noconfirm
pacman -S --needed --noconfirm \
  git \
  mingw-w64-ucrt-x86_64-cmake \
  mingw-w64-ucrt-x86_64-ninja \
  mingw-w64-ucrt-x86_64-gcc \
  mingw-w64-ucrt-x86_64-suitesparse

INSTALL_ROOT=`$(cygpath -u "`$LUMEN_INSTALL_ROOT_WIN")
mkdir -p "`$INSTALL_ROOT"
GSPICE="`$INSTALL_ROOT/GSPICE"
if [ -d "`$GSPICE/.git" ]; then
  git -C "`$GSPICE" pull --ff-only
else
  git clone https://github.com/hegdeshreesha/GSPICE.git "`$GSPICE"
fi

cmake -S "`$GSPICE" -B "`$GSPICE/build-msys2-ucrt64" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DGSPICE_ENABLE_KLU=ON \
  -DGSPICE_REQUIRE_KLU=ON
cmake --build "`$GSPICE/build-msys2-ucrt64" --parallel 2
"@

Write-Host "Installing MSYS2 UCRT64 packages and building GSPICE..."
Invoke-Msys -Bash $bash -Script $msysScript

$lumen = Join-Path $InstallRoot "Lumen_Circuit_Studio"
if (Test-Path -LiteralPath (Join-Path $lumen ".git")) {
    git -C $lumen pull --ff-only
} elseif (Test-Path -LiteralPath $lumen) {
    throw "Target path exists but is not a git checkout: $lumen"
} else {
    if (-not (Test-Command git)) {
        throw "Git was installed but is not visible in this PowerShell session. Open a new PowerShell window and rerun this script."
    }
    git clone https://github.com/hegdeshreesha/Lumen_Circuit_Studio.git $lumen
}

Push-Location $lumen
try {
    .\scripts\bootstrap_dev.ps1 -PythonExe $python
} finally {
    Pop-Location
}

$gspiceExe = Join-Path $InstallRoot "GSPICE\build-msys2-ucrt64\gspice.exe"
$ucrtBin = Join-Path $MsysRoot "ucrt64\bin"
$config = [ordered]@{
    version = 1
    active_simulator = "GSPICE"
    simulators = [ordered]@{
        GSPICE = [ordered]@{
            active_executable = $gspiceExe
            active_source = "msys2-ucrt64"
            prefer_klu = $true
            runtime_path = $ucrtBin
        }
    }
}
$configPath = Join-Path $lumen ".lumen_simulators.json"
$config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8

Write-Host ""
Write-Host "GSPICE executable:"
Write-Host "  $gspiceExe"
Write-Host "GSPICE capabilities:"
$env:PATH = "$ucrtBin;$env:PATH"
& $gspiceExe --capabilities
Write-Host ""
Write-Host "Lumen installed in: $lumen"
Write-Host "Start Lumen with:"
Write-Host "  cd $lumen"
Write-Host '  $env:PATH = "C:\msys64\ucrt64\bin;$env:PATH"'
Write-Host '  $env:QT_QPA_PLATFORM = "windows"'
Write-Host "  .\.venv\Scripts\pythonw.exe -m lumen"
