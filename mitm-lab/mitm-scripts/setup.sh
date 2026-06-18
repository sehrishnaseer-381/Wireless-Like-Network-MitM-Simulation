#!/usr/bin/env bash
# setup.sh - build the isolated MitM lab:  victim1 <-> attacker <-> victim2
# Sections 5, 6, 7.1 of the workflow doc, in one script.
# Run as root:  sudo ./setup.sh
#
# Topology (routed chain, attacker on-path between two subnets):
#   victim1 (10.0.1.10) --veth-- attacker (10.0.1.50 / 10.0.2.50) --veth-- victim2 (10.0.2.20)
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

echo "[*] Cleaning any previous lab state..."
ip netns del victim1  2>/dev/null || true
ip netns del victim2  2>/dev/null || true
ip netns del attacker 2>/dev/null || true

echo "[*] Creating namespaces..."
ip netns add victim1
ip netns add victim2
ip netns add attacker

echo "[*] Creating veth links..."
ip link add v1-att type veth peer name att-v1
ip link add att-v2 type veth peer name v2-att

echo "[*] Moving interfaces into namespaces..."
ip link set v1-att netns victim1
ip link set att-v1 netns attacker
ip link set att-v2 netns attacker
ip link set v2-att netns victim2

echo "[*] Configuring Victim1 (10.0.1.10)..."
ip netns exec victim1 ip addr add 10.0.1.10/24 dev v1-att
ip netns exec victim1 ip link set v1-att up
ip netns exec victim1 ip link set lo up

echo "[*] Configuring Victim2 (10.0.2.20)..."
ip netns exec victim2 ip addr add 10.0.2.20/24 dev v2-att
ip netns exec victim2 ip link set v2-att up
ip netns exec victim2 ip link set lo up

echo "[*] Configuring Attacker (10.0.1.50 / 10.0.2.50)..."
ip netns exec attacker ip addr add 10.0.1.50/24 dev att-v1
ip netns exec attacker ip addr add 10.0.2.50/24 dev att-v2
ip netns exec attacker ip link set att-v1 up
ip netns exec attacker ip link set att-v2 up
ip netns exec attacker ip link set lo up

# IMPORTANT: ip_forward is per-namespace. It MUST be set inside the attacker
# namespace, not on the host. A host-level sysctl does nothing here.
echo "[*] Enabling forwarding inside the attacker namespace..."
ip netns exec attacker sysctl -w net.ipv4.ip_forward=1

echo "[*] Adding victim routes through the attacker..."
ip netns exec victim1 ip route add 10.0.2.0/24 via 10.0.1.50
ip netns exec victim2 ip route add 10.0.1.0/24 via 10.0.2.50

echo "[+] Lab is up."
echo "    Verify:  sudo ip netns exec victim1 ping -c 3 10.0.2.20"
echo "    Replies with ttl=63 confirm the attacker forwarded the packet."
