param(
    [string]$InstallRoot = "$HOME\lumen-gspice"
)

$ErrorActionPreference = "Stop"

function Test-Command($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Show-Check($Name, $Ok) {
    $mark = if ($Ok) { "[OK]" } else { "[MISSING]" }
    $color = if ($Ok) { "Green" } else { "Yellow" }
    Write-Host "$mark $Name" -ForegroundColor $color
}

function Ask-Yes($Prompt) {
    $answer = Read-Host "$Prompt [y/N]"
    return $answer -match '^(y|yes)$'
}

function Install-Winget($Id) {
    winget install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements
}

function Get-Vswhere {
    $path = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $path) { return $path }
    return ""
}

function Get-VsInstall {
    $vswhere = Get-Vswhere
    if (-not $vswhere) { return "" }
    $install = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    return ($install | Select-Object -First 1)
}

function Test-CppBuildTools {
    if ((Test-Command cl) -and (Test-Command nmake)) { return $true }
    return [bool](Get-VsInstall)
}

function Clone-Or-Update($Url, $Path) {
    if (Test-Path -LiteralPath $Path) {
        git -C $Path pull --ff-only
    } else {
        git clone $Url $Path
    }
}

Write-Host "Checking prerequisites..."
$checks = [ordered]@{
    "Git" = Test-Command git
    "CMake" = Test-Command cmake
    "Python 3" = Test-Command python
    "C++ build tools" = Test-CppBuildTools
}

$checks.GetEnumerator() | ForEach-Object { Show-Check $_.Key $_.Value }
$missing = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })

if ($missing.Count) {
    if (-not (Test-Command winget)) {
        throw "Missing prerequisites: $($missing -join ', '). Install them manually, then rerun this script. winget was not found."
    }
    if (Ask-Yes "Install missing prerequisites with winget?") {
        if (-not $checks["Git"]) { Install-Winget "Git.Git" }
        if (-not $checks["CMake"]) { Install-Winget "Kitware.CMake" }
        if (-not $checks["Python 3"]) { Install-Winget "Python.Python.3.12" }
        if (-not $checks["C++ build tools"]) {
            winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --silent --accept-source-agreements --accept-package-agreements --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
        }
        Write-Host "Prerequisites installed. Open a new PowerShell window and rerun this script."
        exit 0
    }
    throw "Missing prerequisites: $($missing -join ', ')."
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

$gspice = Join-Path $InstallRoot "GSPICE"
$lumen = Join-Path $InstallRoot "Lumen_Circuit_Studio"
$gspiceBuild = ""

Clone-Or-Update "https://github.com/hegdeshreesha/GSPICE.git" $gspice
Clone-Or-Update "https://github.com/hegdeshreesha/Lumen_Circuit_Studio.git" $lumen

$vsInstall = Get-VsInstall
if ($vsInstall) {
    $gspiceBuild = Join-Path $gspice "build-vs2022"
    $cmakeArgs = @("-S", $gspice, "-B", $gspiceBuild, "-G", "Visual Studio 17 2022", "-A", "x64")
    $gspiceExe = Join-Path $gspiceBuild "Release\gspice.exe"
} elseif ((Test-Command cl) -and (Test-Command nmake)) {
    $gspiceBuild = Join-Path $gspice "build-nmake"
    $cmakeArgs = @("-S", $gspice, "-B", $gspiceBuild, "-G", "NMake Makefiles")
    $gspiceExe = Join-Path $gspiceBuild "gspice.exe"
} else {
    throw "No usable C++ build environment found. Install Visual Studio Build Tools with the C++ workload, open a new PowerShell window, and rerun this script."
}
cmake @cmakeArgs
cmake --build $gspiceBuild --config Release

Push-Location $lumen
.\scripts\bootstrap_dev.ps1
.\.venv\Scripts\python.exe scripts\verify_environment.py
Pop-Location

Write-Host ""
Write-Host "GSPICE built in: $gspice"
Write-Host "GSPICE executable:"
Write-Host "  $gspiceExe"
Write-Host "Lumen installed in: $lumen"
Write-Host "Start Lumen with:"
Write-Host "  cd $lumen"
Write-Host '  $env:QT_QPA_PLATFORM = "windows"'
Write-Host "  .\.venv\Scripts\pythonw.exe -m lumen"
