#!/usr/bin/env bash
# defense.sh - the two defensive controls (section 12 of the workflow doc).
#
# Usage:  sudo ./defense.sh <command>
#   sudo ./defense.sh static-arp    # pin the gateway (attacker) MAC on both victims
#   sudo ./defense.sh firewall-on   # FORWARD DROP, allow only ICMP
#   sudo ./defense.sh firewall-test # show ICMP passes but TCP is blocked
#   sudo ./defense.sh firewall-off  # restore forwarding
#   sudo ./defense.sh show          # show neighbor tables + firewall rules
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 <command>" >&2
  exit 1
fi

CMD="${1:-}"

case "$CMD" in
  static-arp)
    # In this routed lab the meaningful static entry pins the GATEWAY (attacker)
    # MAC on each victim - that is the address each victim actually resolves.
    ATT_V1_MAC=$(ip netns exec attacker cat /sys/class/net/att-v1/address)
    ATT_V2_MAC=$(ip netns exec attacker cat /sys/class/net/att-v2/address)
    echo "[*] Attacker att-v1 MAC: $ATT_V1_MAC"
    echo "[*] Attacker att-v2 MAC: $ATT_V2_MAC"
    ip netns exec victim1 ip neigh replace 10.0.1.50 lladdr "$ATT_V1_MAC" nud permanent dev v1-att
    ip netns exec victim2 ip neigh replace 10.0.2.50 lladdr "$ATT_V2_MAC" nud permanent dev v2-att
    echo "[+] Permanent gateway entries installed. Verify:"
    ip netns exec victim1 ip neigh
    ip netns exec victim2 ip neigh
    ;;
  firewall-on)
    ip netns exec attacker iptables -P FORWARD DROP
    ip netns exec attacker iptables -A FORWARD -p icmp -j ACCEPT
    echo "[+] FORWARD policy = DROP, ICMP allowed. TCP/UDP relay is now blocked."
    ;;
  firewall-test)
    echo "=== ICMP should SUCCEED (allowed exception) ==="
    ip netns exec victim1 ping -c 3 10.0.2.20 || true
    echo
    echo "=== TCP should TIME OUT (blocked by FORWARD DROP) ==="
    ip netns exec victim2 iperf3 -s -D 2>/dev/null || true
    sleep 1
    ip netns exec victim1 iperf3 -c 10.0.2.20 -t 5 --repeating-payload || true
    ip netns exec victim2 pkill iperf3 2>/dev/null || true
    ;;
  firewall-off)
    ip netns exec attacker iptables -F
    ip netns exec attacker iptables -P FORWARD ACCEPT
    echo "[+] Forwarding restored (FORWARD policy = ACCEPT, rules flushed)."
    ;;
  show)
    echo "=== Victim1 neighbors ===" ; ip netns exec victim1 ip neigh
    echo "=== Victim2 neighbors ===" ; ip netns exec victim2 ip neigh
    echo "=== Attacker FORWARD rules ===" ; ip netns exec attacker iptables -L FORWARD -n -v
    ;;
  *)
    echo "Usage: sudo $0 {static-arp|firewall-on|firewall-test|firewall-off|show}" >&2
    exit 1 ;;
esac
