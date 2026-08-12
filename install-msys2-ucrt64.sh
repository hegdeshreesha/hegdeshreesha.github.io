#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${1:-$HOME/lumen-gspice}"

if [ "${MSYSTEM:-}" != "UCRT64" ]; then
  echo "Run this from the MSYS2 UCRT64 shell, not PowerShell/CMD/MSYS." >&2
  echo "Install MSYS2 from https://www.msys2.org, open 'MSYS2 UCRT64', then rerun this script." >&2
  exit 2
fi

pacman -Syu --needed --noconfirm \
  git \
  mingw-w64-ucrt-x86_64-cmake \
  mingw-w64-ucrt-x86_64-ninja \
  mingw-w64-ucrt-x86_64-gcc \
  mingw-w64-ucrt-x86_64-suitesparse \
  mingw-w64-ucrt-x86_64-python \
  mingw-w64-ucrt-x86_64-python-pip

mkdir -p "$INSTALL_ROOT"
GSPICE="$INSTALL_ROOT/GSPICE"

if [ -d "$GSPICE/.git" ]; then
  git -C "$GSPICE" pull --ff-only
else
  git clone https://github.com/hegdeshreesha/GSPICE.git "$GSPICE"
fi

cmake -S "$GSPICE" -B "$GSPICE/build-msys2-ucrt64" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DGSPICE_ENABLE_KLU=ON \
  -DGSPICE_REQUIRE_KLU=ON
cmake --build "$GSPICE/build-msys2-ucrt64" --parallel 2

echo
echo "GSPICE built in: $GSPICE"
echo "GSPICE executable:"
echo "  $GSPICE/build-msys2-ucrt64/gspice.exe"
echo "GSPICE capabilities:"
"$GSPICE/build-msys2-ucrt64/gspice.exe" --capabilities || true
echo
echo "For Windows Lumen, add the MSYS2 UCRT64 bin folder to PATH before launch:"
echo "  C:\\msys64\\ucrt64\\bin"
