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

install_missing() {
  if has apt-get; then
    sudo apt-get update
    sudo apt-get install -y git cmake python3 python3-venv build-essential
  elif has dnf; then
    sudo dnf install -y git cmake python3 gcc gcc-c++ make
  elif has pacman; then
    sudo pacman -Sy --needed git cmake python base-devel
  else
    echo "No supported package manager found. Install Git, CMake, Python 3, venv, and a C++ compiler manually." >&2
    exit 1
  fi
}

echo "Checking prerequisites..."
missing=()

if has git; then show_check "Git" 1; else show_check "Git" 0; missing+=("git"); fi
if has cmake; then show_check "CMake" 1; else show_check "CMake" 0; missing+=("cmake"); fi
if has python3; then show_check "Python 3" 1; else show_check "Python 3" 0; missing+=("python3"); fi
if python3 -m venv --help >/dev/null 2>&1; then show_check "Python venv" 1; else show_check "Python venv" 0; missing+=("python3-venv"); fi
if has c++ || has g++; then show_check "C++ compiler" 1; else show_check "C++ compiler" 0; missing+=("compiler"); fi

if [ "${#missing[@]}" -gt 0 ]; then
  if ask_yes "Install missing prerequisites now?"; then
    install_missing
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
echo "  export QT_QPA_PLATFORM=xcb"
echo "  python -m lumen"
