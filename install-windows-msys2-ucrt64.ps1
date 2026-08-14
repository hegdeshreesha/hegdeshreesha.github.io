param(
    [string]$InstallRoot = "$HOME\lumen-gspice",
    [string]$MsysRoot = "C:\msys64",
    [switch]$CheckOnly,
    [switch]$NoInstall
)

$ErrorActionPreference = "Stop"
$InstallerVersion = "2026-08-13.2"

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
    $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("lumen-gspice-msys2-{0}.sh" -f ([guid]::NewGuid().ToString("N")))
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($scriptPath, $Script.Replace("`r`n", "`n"), $utf8NoBom)
        & $Bash $scriptPath
        if ($LASTEXITCODE -ne 0) {
            throw "MSYS2 command failed with exit code $LASTEXITCODE. Script: $scriptPath"
        }
    } catch {
        if (Test-Path -LiteralPath $scriptPath) {
            Write-Host "Temporary MSYS2 script kept for debugging: $scriptPath" -ForegroundColor Yellow
        }
        throw
    }
    if (Test-Path -LiteralPath $scriptPath) {
        Remove-Item -LiteralPath $scriptPath -Force
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
unset PYTHONHOME
unset PYTHONPATH
unset PYTHONPLATLIBDIR
unset PYTHONSTARTUP
unset VIRTUAL_ENV
unset CONDA_PREFIX
unset CONDA_DEFAULT_ENV

INSTALL_ROOT=`$(cygpath -u "`$LUMEN_INSTALL_ROOT_WIN")
mkdir -p "`$INSTALL_ROOT"
LOG_DIR="`$INSTALL_ROOT/logs"
mkdir -p "`$LOG_DIR"
PACMAN_LOG="`$LOG_DIR/msys2-pacman-ucrt64.log"
CLONE_LOG="`$LOG_DIR/gspice-clone-msys2-ucrt64.log"
CONFIG_LOG="`$LOG_DIR/gspice-configure-msys2-ucrt64.log"
BUILD_LOG="`$LOG_DIR/gspice-build-msys2-ucrt64.log"

echo "MSYS2 shell: `$SHELL" | tee "`$PACMAN_LOG"
echo "MSYSTEM: `$MSYSTEM" | tee -a "`$PACMAN_LOG"
echo "PATH: `$PATH" | tee -a "`$PACMAN_LOG"

set +e
pacman -Syu --needed --noconfirm \
  git \
  mingw-w64-ucrt-x86_64-cmake \
  mingw-w64-ucrt-x86_64-ninja \
  mingw-w64-ucrt-x86_64-gcc \
  mingw-w64-ucrt-x86_64-python \
  mingw-w64-ucrt-x86_64-suitesparse 2>&1 | tee -a "`$PACMAN_LOG"
status=`${PIPESTATUS[0]}
set -e
if [ "`$status" -ne 0 ]; then
  echo
  echo "MSYS2 package install/update failed. Last log lines:"
  tail -n 120 "`$PACMAN_LOG" || true
  exit "`$status"
fi

for tool in git cmake ninja g++ python; do
  if ! command -v "`$tool" >/dev/null 2>&1; then
    echo "Required MSYS2 tool not found after package install: `$tool" | tee -a "`$PACMAN_LOG"
    exit 1
  fi
done
set +e
python -c "import encodings, sys; print(sys.executable)" 2>&1 | tee -a "`$PACMAN_LOG"
status=`${PIPESTATUS[0]}
set -e
if [ "`$status" -ne 0 ]; then
  echo "MSYS2 Python is not healthy after clearing inherited Python environment variables." | tee -a "`$PACMAN_LOG"
  exit 1
fi

GSPICE="`$INSTALL_ROOT/GSPICE"
set +e
if [ -d "`$GSPICE/.git" ]; then
  git -C "`$GSPICE" pull --ff-only 2>&1 | tee "`$CLONE_LOG"
else
  git clone https://github.com/hegdeshreesha/GSPICE.git "`$GSPICE" 2>&1 | tee "`$CLONE_LOG"
fi
status=`${PIPESTATUS[0]}
set -e
if [ "`$status" -ne 0 ]; then
  echo
  echo "GSPICE clone/update failed. Last log lines:"
  tail -n 120 "`$CLONE_LOG" || true
  exit "`$status"
fi

set +e
cmake -S "`$GSPICE" -B "`$GSPICE/build-msys2-ucrt64" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DGSPICE_ENABLE_KLU=ON \
  -DGSPICE_REQUIRE_KLU=ON 2>&1 | tee "`$CONFIG_LOG"
status=`${PIPESTATUS[0]}
set -e
if [ "`$status" -ne 0 ]; then
  echo
  echo "GSPICE configure failed. Last log lines:"
  tail -n 80 "`$CONFIG_LOG" || true
  exit "`$status"
fi

set +e
cmake --build "`$GSPICE/build-msys2-ucrt64" --target gspice --parallel 2 --verbose 2>&1 | tee "`$BUILD_LOG"
status=`${PIPESTATUS[0]}
set -e
if [ "`$status" -ne 0 ]; then
  echo
  echo "GSPICE build failed. Last log lines:"
  tail -n 120 "`$BUILD_LOG" || true
  exit "`$status"
fi

if [ ! -x "`$GSPICE/build-msys2-ucrt64/gspice.exe" ]; then
  echo "GSPICE build finished but executable was not found: `$GSPICE/build-msys2-ucrt64/gspice.exe"
  exit 1
fi
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
