#!/usr/bin/env bash
# Simple menu/launcher for the practice labs.
# Usage:
#   ./run.sh              list all labs
#   ./run.sh <NN|name>     show a lab's task and offer to run its setup.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABS_DIR="$ROOT/labs"

list_labs() {
  echo "Available labs:"
  echo
  for d in "$LABS_DIR"/*/; do
    name=$(basename "$d")
    title=$(head -1 "$d/TASK.md" 2>/dev/null || true)
    title=${title#\# }
    printf "  %-32s %s\n" "$name" "$title"
  done
  echo
  echo "Run one with: ./run.sh <folder-name-or-number>"
}

find_lab() {
  local key="$1"
  local match
  match=$(find "$LABS_DIR" -maxdepth 1 -type d -name "${key}*" | head -1)
  if [[ -z "$match" ]]; then
    echo "No lab matches '$key'." >&2
    exit 1
  fi
  echo "$match"
}

if [[ $# -eq 0 ]]; then
  list_labs
  exit 0
fi

LAB_DIR=$(find_lab "$1")
LAB_NAME=$(basename "$LAB_DIR")

echo "=================================================================="
echo " Lab: $LAB_NAME"
echo "=================================================================="
cat "$LAB_DIR/TASK.md"
echo
echo "------------------------------------------------------------------"
read -r -p "Run setup.sh for this lab now? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  bash "$LAB_DIR/setup.sh"
  echo
  echo "Setup complete. When you're done working the task:"
  echo "  bash $LAB_DIR/check.sh"
  echo "  bash $LAB_DIR/cleanup.sh"
else
  echo "Skipped. You can run it later with: bash $LAB_DIR/setup.sh"
fi
