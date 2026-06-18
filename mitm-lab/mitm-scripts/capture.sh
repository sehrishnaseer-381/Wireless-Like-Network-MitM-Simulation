#!/usr/bin/env bash
# capture.sh - capture attacker traffic to pcaps/<label>.pcap for the appendix
# (section 7.5 of the workflow doc). Press Ctrl+C to stop.
#
# Usage:  sudo ./capture.sh <label> [tcpdump-filter]
#   sudo ./capture.sh baseline-ping  icmp
#   sudo ./capture.sh baseline-iperf 'tcp port 5201'
#   sudo ./capture.sh delay-100ms    icmp
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 <label> [tcpdump-filter]" >&2
  exit 1
fi

LABEL="${1:?usage: $0 <label> [tcpdump-filter]}"
FILTER="${2:-icmp}"
mkdir -p pcaps

echo "[*] Capturing on att-v1 -> pcaps/${LABEL}.pcap   (Ctrl+C to stop)"
ip netns exec attacker tcpdump -i att-v1 -w "pcaps/${LABEL}.pcap" $FILTER

chown "${SUDO_USER:-$USER}" "pcaps/${LABEL}.pcap" 2>/dev/null || true
echo "[+] Saved pcaps/${LABEL}.pcap  (open with: wireshark pcaps/${LABEL}.pcap)"
