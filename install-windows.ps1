param(
    [string]$InstallRoot = "$HOME\lumen-gspice",
    [switch]$CheckOnly,
    [switch]$NoInstall
)

$ErrorActionPreference = "Stop"

function Test-Command($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Show-Check($Name, $Ok, $Detail = "") {
    $mark = if ($Ok) { "[OK]" } else { "[MISSING]" }
    $color = if ($Ok) { "Green" } else { "Yellow" }
    $suffix = if ($Detail) { " - $Detail" } else { "" }
    Write-Host "$mark $Name$suffix" -ForegroundColor $color
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

function Get-VsInstances {
    $vswhere = Get-Vswhere
    if (-not $vswhere) { return @() }
    $json = & $vswhere -products * -format json -utf8
    if (-not $json) { return @() }
    return @($json | ConvertFrom-Json)
}

function Get-VsCppInstall {
    $vswhere = Get-Vswhere
    if (-not $vswhere) { return $null }
    $json = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json -utf8
    if (-not $json) { return $null }
    return @($json | ConvertFrom-Json | Select-Object -First 1)[0]
}

function Get-AnyVsInstall {
    return @(Get-VsInstances | Select-Object -First 1)[0]
}

function Get-CMakeVsGenerator($VsInfo) {
    $version = [string]($VsInfo.catalog.productLineVersion)
    if (-not $version) { $version = [string]($VsInfo.installationVersion) }
    if ($version -match '^(\d+)') {
        switch ($matches[1]) {
            "18" { return "Visual Studio 18 2026" }
            "17" { return "Visual Studio 17 2022" }
            "16" { return "Visual Studio 16 2019" }
        }
    }
    return "Visual Studio 17 2022"
}

function Test-Python {
    return (Test-Command python) -or (Test-Command py)
}

function Get-PythonCommand {
    if (Test-Command python) { return "python" }
    if (Test-Command py) { return "py" }
    throw "Python was not found on PATH."
}

function Install-VsCppWorkload {
    param([string]$InstallPath)

    $installer = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vs_installer.exe"
    if (-not (Test-Path -LiteralPath $installer)) {
        throw "Visual Studio Installer was not found. Open Visual Studio Installer manually, choose Modify, and add Desktop development with C++."
    }
    if (-not $InstallPath) {
        throw "Visual Studio or Build Tools was detected, but its install path could not be resolved."
    }

    Write-Host "Adding Desktop development with C++ to existing Visual Studio/Build Tools installation..."
    $args = @(
        "modify",
        "--installPath", $InstallPath,
        "--quiet",
        "--wait",
        "--norestart",
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--includeRecommended"
    )
    $proc = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        throw "Visual Studio Installer modify failed with exit code $($proc.ExitCode)."
    }
}

function Clone-Or-Update($Url, $Path) {
    if (Test-Path -LiteralPath (Join-Path $Path ".git")) {
        git -C $Path pull --ff-only
    } elseif (Test-Path -LiteralPath $Path) {
        throw "Target path exists but is not a git checkout: $Path"
    } else {
        git clone $Url $Path
    }
}

function Ensure-Vcpkg($Root) {
    $vcpkg = Join-Path $Root "vcpkg"
    if (-not (Test-Path -LiteralPath $vcpkg)) {
        git clone https://github.com/microsoft/vcpkg.git $vcpkg
    } else {
        git -C $vcpkg pull --ff-only
    }
    $exe = Join-Path $vcpkg "vcpkg.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        & (Join-Path $vcpkg "bootstrap-vcpkg.bat")
    }
    return $vcpkg
}

function Fail-Prereqs($Missing) {
    Write-Host ""
    Write-Host "Missing prerequisites: $($Missing -join ', ')" -ForegroundColor Yellow
    Write-Host "Fix options:"
    Write-Host "  1. Let this script install/modify prerequisites when prompted."
    Write-Host "  2. Open Visual Studio Installer > Modify > Desktop development with C++."
    Write-Host "  3. Use MSYS2 UCRT64 and install-msys2-ucrt64.sh for a Linux-like Windows build."
    throw "Prerequisite check failed."
}

Write-Host "Checking prerequisites..."
$vsAny = Get-AnyVsInstall
$vsCpp = Get-VsCppInstall
$checks = [ordered]@{
    "Git" = Test-Command git
    "CMake" = Test-Command cmake
    "Python 3" = Test-Python
    "Visual Studio / Build Tools" = [bool]$vsAny
    "Desktop development with C++" = [bool]$vsCpp
}

Show-Check "Git" $checks["Git"]
Show-Check "CMake" $checks["CMake"]
Show-Check "Python 3" $checks["Python 3"] ($(if (Test-Command python) { "python" } elseif (Test-Command py) { "py launcher" } else { "" }))
Show-Check "Visual Studio / Build Tools" $checks["Visual Studio / Build Tools"] ($(if ($vsAny) { $vsAny.installationPath } else { "" }))
Show-Check "Desktop development with C++" $checks["Desktop development with C++"] ($(if ($vsCpp) { $vsCpp.installationPath } else { "" }))

$missing = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($CheckOnly) {
    if ($missing.Count) { Fail-Prereqs $missing }
    Write-Host "All prerequisites are present."
    exit 0
}

if ($missing.Count) {
    if ($NoInstall) { Fail-Prereqs $missing }
    if (-not (Test-Command winget)) {
        Write-Host "winget was not found, so automatic prerequisite install is unavailable." -ForegroundColor Yellow
        Fail-Prereqs $missing
    }
    if (Ask-Yes "Install or modify missing prerequisites now?") {
        if (-not $checks["Git"]) { Install-Winget "Git.Git" }
        if (-not $checks["CMake"]) { Install-Winget "Kitware.CMake" }
        if (-not $checks["Python 3"]) { Install-Winget "Python.Python.3.12" }
        if (-not $checks["Visual Studio / Build Tools"]) {
            winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --silent --accept-source-agreements --accept-package-agreements --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --norestart"
        } elseif (-not $checks["Desktop development with C++"]) {
            Install-VsCppWorkload $vsAny.installationPath
        }
        Write-Host "Prerequisites installed or modified. Open a new PowerShell window and rerun this script."
        exit 0
    }
    Fail-Prereqs $missing
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

$gspice = Join-Path $InstallRoot "GSPICE"
$lumen = Join-Path $InstallRoot "Lumen_Circuit_Studio"

Clone-Or-Update "https://github.com/hegdeshreesha/GSPICE.git" $gspice
Clone-Or-Update "https://github.com/hegdeshreesha/Lumen_Circuit_Studio.git" $lumen

$vsCpp = Get-VsCppInstall
if (-not $vsCpp) {
    throw "Desktop development with C++ was present at preflight but is no longer detected. Open a new PowerShell window and rerun."
}
$vcpkgRoot = Ensure-Vcpkg $InstallRoot
$env:VCPKG_ROOT = $vcpkgRoot
$gspiceBuild = Join-Path $gspice "build-vcpkg"
$toolchain = Join-Path $vcpkgRoot "scripts\buildsystems\vcpkg.cmake"
$generator = Get-CMakeVsGenerator $vsCpp
$gspiceExe = Join-Path $gspiceBuild "Release\gspice.exe"
$cmakeHelp = cmake --help | Out-String
if ($cmakeHelp -notmatch [regex]::Escape($generator)) {
    throw "Installed CMake does not support generator '$generator'. Update CMake, open a new PowerShell window, and rerun this script."
}

$cmakeArgs = @(
    "-S", $gspice,
    "-B", $gspiceBuild,
    "-G", $generator,
    "-A", "x64",
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
    "-DVCPKG_TARGET_TRIPLET=x64-windows",
    "-DVCPKG_MANIFEST_MODE=ON",
    "-DGSPICE_ENABLE_KLU=ON",
    "-DGSPICE_REQUIRE_KLU=ON"
)
Write-Host "Configuring GSPICE with $generator..."
cmake @cmakeArgs
cmake --build $gspiceBuild --config Release
if (-not (Test-Path -LiteralPath $gspiceExe)) {
    throw "GSPICE build finished but executable was not found: $gspiceExe"
}

Push-Location $lumen
try {
    .\scripts\bootstrap_dev.ps1
    $python = Join-Path $lumen ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $python)) { throw "Lumen venv Python was not created: $python" }
    & $python scripts\verify_environment.py
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "GSPICE built in: $gspice"
Write-Host "GSPICE executable:"
Write-Host "  $gspiceExe"
Write-Host "GSPICE capabilities:"
& $gspiceExe --capabilities
Write-Host "Lumen installed in: $lumen"
Write-Host "Start Lumen with:"
Write-Host "  cd $lumen"
Write-Host '  $env:QT_QPA_PLATFORM = "windows"'
Write-Host "  .\.venv\Scripts\pythonw.exe -m lumen"
