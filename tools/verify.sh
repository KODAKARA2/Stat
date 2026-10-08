#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
engine="${GODOT:-godot}"
# Never touch the developer's normal saves or settings.
verification_home="$(mktemp -d)"
trap 'rm -rf "$verification_home"' EXIT
export HOME="$verification_home"
export XDG_CACHE_HOME="$verification_home/cache"
mkdir -p "$XDG_CACHE_HOME"
"$engine" --version
"$engine" --headless --editor --path . --import
for scene in run_tests save_regression gameplay_regression; do
  "$engine" --headless --path . "res://tests/$scene.tscn" 2>&1 | tee "$verification_home/$scene.log"
  if grep -Eq 'SCRIPT ERROR|ERROR:|^FAIL ' "$verification_home/$scene.log"; then
    exit 1
  fi
done
if [[ "${1:-}" == "--simulations" ]]; then
  for scene in battle_sim war_sim career_sim duel_sim; do
    "$engine" --headless --path . "res://tests/$scene.tscn"
  done
fi
