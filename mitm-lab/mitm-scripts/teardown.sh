#!/usr/bin/env bash
# teardown.sh - remove the lab. Deleting a namespace also removes its veths.
# Run as root:  sudo ./teardown.sh
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

ip netns del victim1  2>/dev/null || true
ip netns del victim2  2>/dev/null || true
ip netns del attacker 2>/dev/null || true
echo "[+] Lab removed."
