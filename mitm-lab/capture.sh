#!/usr/bin/env bash
# capture.sh — capture attacker traffic to evidence/<label>.pcap for the report appendix.
# Run as root, in its own terminal; press Ctrl+C to stop, then generate traffic
# from another terminal first if you want it captured.
#
# usage: sudo ./capture.sh <label> [tcpdump-filter]
#   sudo ./capture.sh baseline-ping  icmp
#   sudo ./capture.sh baseline-iperf 'tcp port 5201'
#   sudo ./capture.sh delay-100ms    icmp
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

LABEL="${1:?usage: $0 <label> [tcpdump-filter]}"
FILTER="${2:-icmp}"
mkdir -p evidence

echo "[*] Capturing on att-v1 -> evidence/${LABEL}.pcap   (Ctrl+C to stop)"
ip netns exec attacker tcpdump -i att-v1 -w "evidence/${LABEL}.pcap" $FILTER

# After stopping, make the file readable by your user for Wireshark:
chown "${SUDO_USER:-$USER}" "evidence/${LABEL}.pcap" 2>/dev/null || true
echo "[+] Saved evidence/${LABEL}.pcap"
