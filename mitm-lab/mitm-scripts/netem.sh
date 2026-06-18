#!/usr/bin/env bash
# netem.sh - apply or clear a wireless-like impairment on the attacker's
# att-v2 interface (section 10 of the workflow doc). One effect at a time.
#
# Usage:  sudo ./netem.sh <effect>
#   sudo ./netem.sh delay        # 100 ms latency
#   sudo ./netem.sh loss         # 20% random loss
#   sudo ./netem.sh jitter       # 50 ms +/- 20 ms (normal)
#   sudo ./netem.sh corrupt      # 50% bit corruption
#   sudo ./netem.sh duplicate    # 20% duplication
#   sudo ./netem.sh reorder      # 25% reorder with 50 ms base delay
#   sudo ./netem.sh rate         # 1 mbit rate limit
#   sudo ./netem.sh corrloss     # 20% correlated (bursty) loss
#   sudo ./netem.sh combined     # weak-link: delay+jitter+loss+corrupt+dup
#   sudo ./netem.sh clear        # remove all shaping
#   sudo ./netem.sh show         # show the current qdisc
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 <effect>" >&2
  exit 1
fi

DEV="att-v2"
NS="attacker"
EFFECT="${1:-}"

clear_qdisc() { ip netns exec "$NS" tc qdisc del dev "$DEV" root 2>/dev/null || true; }

case "$EFFECT" in
  delay)     clear_qdisc; ip netns exec "$NS" tc qdisc add dev "$DEV" root netem delay 100ms ;;
  loss)      clear_qdisc; ip netns exec "$NS" tc qdisc add dev "$DEV" root netem loss 20% ;;
  jitter)    clear_qdisc; ip netns exec "$NS" tc qdisc add dev "$DEV" root netem delay 50ms 20ms distribution normal ;;
  corrupt)   clear_qdisc; ip netns exec "$NS" tc qdisc add dev "$DEV" root netem corrupt 50% ;;
  duplicate) clear_qdisc; ip netns exec "$NS" tc qdisc add dev "$DEV" root netem duplicate 20% ;;
  reorder)   clear_qdisc; ip netns exec "$NS" tc qdisc add dev "$DEV" root netem delay 50ms reorder 25% 50% ;;
  rate)      clear_qdisc; ip netns exec "$NS" tc qdisc add dev "$DEV" root netem rate 1mbit ;;
  corrloss)  clear_qdisc; ip netns exec "$NS" tc qdisc add dev "$DEV" root netem loss 20% 50% ;;
  combined)  clear_qdisc; ip netns exec "$NS" tc qdisc add dev "$DEV" root netem delay 80ms 20ms loss 5% corrupt 1% duplicate 1% ;;
  clear)     clear_qdisc; echo "[+] Shaping removed." ; exit 0 ;;
  show)      ip netns exec "$NS" tc qdisc show dev "$DEV" ; exit 0 ;;
  *)
    echo "Usage: sudo $0 {delay|loss|jitter|corrupt|duplicate|reorder|rate|corrloss|combined|clear|show}" >&2
    exit 1 ;;
esac

echo "[+] Applied '$EFFECT' on $DEV. Current qdisc:"
ip netns exec "$NS" tc qdisc show dev "$DEV"
echo "    Measure from victim1:  sudo ip netns exec victim1 ping -c 20 10.0.2.20"
echo "    Remove when done:      sudo $0 clear"
