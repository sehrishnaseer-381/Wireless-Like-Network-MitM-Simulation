#!/usr/bin/env bash
# verify.sh - baseline verification (section 7 of the workflow doc).
# Confirms the attacker is on-path before you start measuring.
# Run as root:  sudo ./verify.sh
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

echo "=== 1. Forwarding enabled inside attacker (must be = 1) ==="
ip netns exec attacker sysctl net.ipv4.ip_forward

echo
echo "=== 2. Victim1 routes to Victim2 via the attacker (must show via 10.0.1.50) ==="
ip netns exec victim1 ip route get 10.0.2.20

echo
echo "=== 3. Ping test (replies with ttl=63 confirm one forwarding hop) ==="
ip netns exec victim1 ping -c 5 10.0.2.20

echo
echo "[+] If all three look right, the lab is on-path and ready."
echo "    For throughput, run the iperf3 server and client manually:"
echo "      Terminal B:  sudo ip netns exec victim2 iperf3 -s"
echo "      Terminal C:  sudo ip netns exec victim1 iperf3 -c 10.0.2.20 -t 10 --repeating-payload"
