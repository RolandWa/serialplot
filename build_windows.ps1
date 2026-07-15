# build_windows.ps1 — Build serialplot on Windows using MSYS2 UCRT64
# Run from the repo root:  .\build_windows.ps1
# Optional: pass -Install to also run cmake --install

param(
    [switch]$Install,
    [string]$BuildDir = "build-windows"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$MSYS2  = "C:\msys64"
$PACMAN = "$MSYS2\usr\bin\pacman.exe"
$BASH   = "$MSYS2\usr\bin\bash.exe"
$UCRT64 = "$MSYS2\ucrt64"

if (-not (Test-Path $MSYS2)) {
    Write-Error "MSYS2 not found at $MSYS2. Install from https://www.msys2.org/"
}

# Convert a Windows path to an MSYS2 unix path  (C:\foo\bar -> /c/foo/bar)
function ToUnix([string]$p) {
    $p = $p -replace '\\', '/'
    if ($p -match '^([A-Za-z]):(.*)') {
        $p = '/' + $Matches[1].ToLower() + $Matches[2]
    }
    return $p
}

# ---------------------------------------------------------------------------
# 1. Install required packages into the UCRT64 environment
# ---------------------------------------------------------------------------
Write-Host "`n=== Installing build dependencies via pacman ===" -ForegroundColor Cyan

$packages = @(
    "mingw-w64-ucrt-x86_64-gcc",
    "mingw-w64-ucrt-x86_64-cmake",
    "mingw-w64-ucrt-x86_64-ninja",
    "mingw-w64-ucrt-x86_64-qt6-base",
    "mingw-w64-ucrt-x86_64-qt6-serialport",
    "mingw-w64-ucrt-x86_64-qt6-svg",
    "mingw-w64-ucrt-x86_64-qt6-tools",
    "mingw-w64-ucrt-x86_64-make",
    "mingw-w64-ucrt-x86_64-qwt-qt6"
)

& $PACMAN -S --needed --noconfirm @packages
if ($LASTEXITCODE -ne 0) { Write-Error "pacman failed" }

# ---------------------------------------------------------------------------
# 2. Configure + Build via a temp bash script (avoids PowerShell $ expansion)
# ---------------------------------------------------------------------------
$repoDir  = $PSScriptRoot
$buildDir = Join-Path $repoDir $BuildDir

$repoUnix  = ToUnix $repoDir
$buildUnix = ToUnix $buildDir

$tmpScript = "$env:TEMP\serialplot_build.sh"

$bashScript = @'
#!/usr/bin/env bash
set -e
export PATH="/ucrt64/bin:$PATH"

REPO_DIR="__REPO__"
BUILD_DIR="__BUILD__"

echo "=== CMake configure ==="
cmake -S "$REPO_DIR" \
      -B "$BUILD_DIR" \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_QWT=false \
      -DCMAKE_MODULE_PATH="$REPO_DIR/cmake/windows" \
      -DQWT_INCLUDE_DIR="C:/msys64/ucrt64/include/qwt-qt6" \
      -DQWT_LIBRARY="C:/msys64/ucrt64/bin/qwt-qt6.dll"

echo "=== Building ==="
cmake --build "$BUILD_DIR" --parallel
'@

$bashScript = $bashScript -replace '__REPO__', $repoUnix -replace '__BUILD__', $buildUnix

[System.IO.File]::WriteAllText($tmpScript, $bashScript, [System.Text.Encoding]::UTF8)

Write-Host "`n=== Configuring and building (build dir: $buildDir) ===" -ForegroundColor Cyan
& $BASH --login $tmpScript
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed" }

# ---------------------------------------------------------------------------
# 3. Optional install (collects Qt DLLs via windeployqt)
# ---------------------------------------------------------------------------
if ($Install) {
    $installDir  = Join-Path $buildDir "install"
    $installUnix = ToUnix $installDir

    $tmpInstall = "$env:TEMP\serialplot_install.sh"

    $installScript = @'
#!/usr/bin/env bash
set -e
export PATH="/ucrt64/bin:$PATH"
cmake --install "__BUILD__" --prefix "__INSTALL__"
'@
    $installScript = $installScript -replace '__BUILD__', $buildUnix -replace '__INSTALL__', $installUnix
    [System.IO.File]::WriteAllText($tmpInstall, $installScript, [System.Text.Encoding]::UTF8)

    Write-Host "`n=== Installing to $installDir ===" -ForegroundColor Cyan
    & $BASH --login $tmpInstall
    if ($LASTEXITCODE -ne 0) { Write-Error "Install failed" }

    # Copy Qwt and MinGW/MSYS2 runtime DLLs not handled by windeployqt
    Write-Host "`n=== Copying runtime DLLs ===" -ForegroundColor Cyan
    $installBin = Join-Path $installDir "bin"
    $objdump    = "$UCRT64\bin\objdump.exe"
    $systemDlls = '^(KERNEL32|USER32|GDI32|SHELL32|ADVAPI32|ole32|OLEAUT32|NTDLL|WS2_32|api-ms-win|UCRTBASE|msvc|D3D|OPENGL|dwmapi|UxTheme|DWRITE|WindowsCodecs|SETUPAPI|CFGMGR32|bcrypt|IMM32|SHLWAPI|WTSAPI32|RPCRT4|NETAPI32|MPR|SHCORE|DNSAPI|dxgi|WINHTTP|VERSION|AUTHZ|comdlg32|CRYPT32|IPHLPAPI|USERENV|WINMM|Secur32|ncrypt)'

    $present = (Get-ChildItem $installBin -Filter "*.dll" -Recurse | Select-Object -ExpandProperty Name)

    $toCopy = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-ChildItem $installBin -Filter "*.dll" -Recurse | ForEach-Object {
        & $objdump -p $_.FullName 2>$null |
            Select-String "DLL Name" |
            ForEach-Object {
                $dll = ($_ -replace '.*DLL Name:\s*','').Trim()
                if ($dll -notmatch $systemDlls -and $present -notcontains $dll) {
                    $null = $toCopy.Add($dll)
                }
            }
    }
    # Always ensure Qwt and its Qt dependencies are included
    # (qwt-qt6.dll isn't in install yet when we scan, so add its deps explicitly)
    $null = $toCopy.Add("qwt-qt6.dll")
    $null = $toCopy.Add("Qt6OpenGL.dll")
    $null = $toCopy.Add("Qt6OpenGLWidgets.dll")
    $null = $toCopy.Add("libicudt76.dll")
    $null = $toCopy.Add("libbrotlicommon.dll")
    $null = $toCopy.Add("libbrotlidec.dll")
    $null = $toCopy.Add("libbrotlienc.dll")
    $null = $toCopy.Add("libharfbuzz-0.dll")
    $null = $toCopy.Add("libharfbuzz-gobject-0.dll")
    $null = $toCopy.Add("libharfbuzz-subset-0.dll")
    $null = $toCopy.Add("libbz2-1.dll")
    $null = $toCopy.Add("libglib-2.0-0.dll")
    $null = $toCopy.Add("libgraphite2.dll")
    $null = $toCopy.Add("libintl-8.dll")
    $null = $toCopy.Add("libpcre2-8-0.dll")
    $null = $toCopy.Add("libiconv-2.dll")

    foreach ($dll in $toCopy) {
        $src = Join-Path "$UCRT64\bin" $dll
        if (Test-Path $src) {
            Copy-Item $src $installBin -Force
            Write-Host "  Copied: $dll" -ForegroundColor Green
        }
    }

    Write-Host "`nInstalled to: $installDir" -ForegroundColor Green
    Write-Host "Run:  $installDir\bin\serialplot.exe"
}

Write-Host "`n=== Build complete ===" -ForegroundColor Green
Write-Host "Executable: $buildDir\serialplot.exe"
