#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${1:-$HOME/lumen-gspice}"

has() { command -v "$1" >/dev/null 2>&1; }

show_check() {
  if [ "$2" = "1" ]; then
    printf '[OK] %s\n' "$1"
  else
    printf '[MISSING] %s\n' "$1"
  fi
}

ask_yes() {
  printf '%s [y/N] ' "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
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

echo "Checking prerequisites..."
missing=()

if xcode-select -p >/dev/null 2>&1; then show_check "Xcode Command Line Tools" 1; else show_check "Xcode Command Line Tools" 0; missing+=("xcode"); fi
if has git; then show_check "Git" 1; else show_check "Git" 0; missing+=("git"); fi
if has cmake; then show_check "CMake" 1; else show_check "CMake" 0; missing+=("cmake"); fi
if has python3; then show_check "Python 3" 1; else show_check "Python 3" 0; missing+=("python3"); fi

if [ "${#missing[@]}" -gt 0 ]; then
  if ask_yes "Install missing prerequisites now?"; then
    if printf '%s\n' "${missing[@]}" | grep -qx xcode; then
      xcode-select --install || true
      echo "Finish the Xcode installer, then rerun this script."
    fi
    if ! has brew; then
      echo "Homebrew is not installed. Install Homebrew from https://brew.sh, then rerun this script."
      exit 1
    fi
    brew install git cmake python
    echo "Prerequisites installed. Rerun this script."
    exit 0
  fi
  echo "Missing prerequisites: ${missing[*]}" >&2
  exit 1
fi

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
echo "GSPICE executable:"
echo "  $GSPICE/build/gspice"
echo "Lumen installed in: $LUMEN"
echo "Start Lumen with:"
echo "  cd \"$LUMEN\""
echo "  . .venv/bin/activate"
echo "  export QT_QPA_PLATFORM=cocoa"
echo "  python -m lumen"
