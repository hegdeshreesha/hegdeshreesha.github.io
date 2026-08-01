#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${1:-$HOME/lumen-gspice}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$1 was not found on PATH." >&2
    exit 1
  }
}

clone_or_update() {
  local url="$1"
  local path="$2"
  if [ -d "$path/.git" ]; then
    git -C "$path" pull --ff-only
  else
    git clone "$url" "$path"
  fi
}

need git
need cmake
need python3

mkdir -p "$INSTALL_ROOT"

GSPICE="$INSTALL_ROOT/GSPICE"
LUMEN="$INSTALL_ROOT/Lumen_Circuit_Studio"

clone_or_update "https://github.com/hegdeshreesha/GSPICE.git" "$GSPICE"
clone_or_update "https://github.com/hegdeshreesha/Lumen_Circuit_Studio.git" "$LUMEN"

cmake -S "$GSPICE" -B "$GSPICE/build"
cmake --build "$GSPICE/build" --config Release

cd "$LUMEN"
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python scripts/verify_environment.py

echo
echo "GSPICE built in: $GSPICE"
echo "Lumen installed in: $LUMEN"
echo "Start Lumen with:"
echo "  cd \"$LUMEN\""
echo "  . .venv/bin/activate"
echo "  export QT_QPA_PLATFORM=cocoa"
echo "  python -m lumen"
