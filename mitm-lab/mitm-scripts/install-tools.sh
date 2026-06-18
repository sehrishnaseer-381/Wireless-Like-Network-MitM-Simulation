#!/usr/bin/env bash
# install-tools.sh - install the tools used by the lab (section 4 of the doc).
# Run as root:  sudo ./install-tools.sh
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

apt update
apt install -y iproute2 iputils-ping net-tools tcpdump wireshark iperf3 iptables bridge-utils
echo "[+] Tools installed."
