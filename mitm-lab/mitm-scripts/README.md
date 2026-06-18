# Wireless-Like Network MitM Simulation and Defense Mechanisms

A controlled, fully isolated lab that demonstrates how an on-path attacker affects
communication between two hosts, using **Linux network namespaces**, **veth pairs**,
and **`tc netem`** traffic shaping — plus the defenses that mitigate it.

> **Scope and ethics.** Everything runs inside a private, non-routable segment with
> no internet egress, on a machine you own or are authorized to test. The attacker is
> placed on-path by the topology itself (a routed gateway between two subnets), not by
> spoofing real systems. The goal is to study and measure network behavior.

## Topology

```
victim1 (10.0.1.10) --veth-- attacker (10.0.1.50 / 10.0.2.50) --veth-- victim2 (10.0.2.20)
```

The two victims are on **different subnets**, so all victim-to-victim traffic must cross
the attacker. A reply arriving with `ttl=63` (one less than 64) confirms the attacker
forwarded it.

## Scripts

| Script | What it does |
| --- | --- |
| `install-tools.sh` | Installs iproute2, tcpdump, wireshark, iperf3, iptables, etc. |
| `setup.sh` | Builds the whole lab (namespaces, veths, IPs, forwarding, routes). |
| `verify.sh` | Baseline checks: forwarding on, route via attacker, ping with ttl=63. |
| `netem.sh` | Applies/clears one wireless impairment at a time on `att-v2`. |
| `capture.sh` | Saves attacker traffic to `pcaps/<label>.pcap` for the appendix. |
| `defense.sh` | Static-ARP (gateway pinning) and firewall `FORWARD DROP` controls. |
| `teardown.sh` | Removes the lab (namespaces and their veths). |

All scripts must be run with `sudo`. The lab is wiped on reboot — just re-run `setup.sh`.

## Quick start

```bash
sudo ./install-tools.sh        # once
sudo ./setup.sh                # build the lab
sudo ./verify.sh               # confirm it is on-path (expect ttl=63)
```

## Running the experiments

Apply one impairment at a time, measure from a victim, then clear it:

```bash
sudo ./netem.sh delay                              # apply 100 ms delay
sudo ip netns exec victim1 ping -c 20 10.0.2.20    # measure RTT
sudo ./netem.sh clear                              # remove it
```

Available effects: `delay loss jitter corrupt duplicate reorder rate corrloss combined`.
Use `sudo ./netem.sh show` to see what is currently applied.

### Throughput (iperf3)

```bash
# Terminal B - server on victim2 (leave running)
sudo ip netns exec victim2 iperf3 -s

# Terminal C - client on victim1
sudo ip netns exec victim1 iperf3 -c 10.0.2.20 -t 10 --repeating-payload   # TCP
sudo ip netns exec victim1 iperf3 -c 10.0.2.20 -u -b 100M -t 10 --repeating-payload   # UDP
sudo ip netns exec victim1 iperf3 -c 10.0.2.20 -t 10 -P 10 --repeating-payload        # heavy load
```

> The `--repeating-payload` flag avoids an iperf3 `/dev/urandom` error seen on some
> kernels. If iperf3 reports a bus error, check that `/tmp` is not full (`df -h /tmp`).

### Capturing evidence

`tcpdump` only sees packets that pass while it runs, so use two terminals:

```bash
# Terminal A
sudo ./capture.sh baseline-ping icmp
# Terminal B
sudo ip netns exec victim1 ping -c 10 10.0.2.20
```

Stop the capture with Ctrl+C, then open it (do **not** run Wireshark as root):

```bash
wireshark pcaps/baseline-ping.pcap
```

In Wireshark, expand the IP header to show **TTL = 63** on a forwarded reply, and use
**Statistics → Conversations → IPv4** for per-flow counts.

## Defenses

```bash
sudo ./defense.sh static-arp      # pin the gateway (attacker) MAC on both victims
sudo ./defense.sh firewall-on     # block forwarding, allow only ICMP
sudo ./defense.sh firewall-test   # ICMP passes, TCP times out (the demonstration)
sudo ./defense.sh firewall-off    # restore forwarding
sudo ./defense.sh show            # show neighbor tables + firewall rules
```

> In this routed topology the static-ARP entry demonstrates gateway pinning, but the
> attacker is the legitimate gateway, so traffic still routes through it. The firewall
> control is the one that actually blocks the relayed traffic.

## Teardown

```bash
sudo ./teardown.sh
```

## Repository layout

```
.
├── README.md
├── install-tools.sh
├── setup.sh
├── verify.sh
├── netem.sh
├── capture.sh
├── defense.sh
├── teardown.sh
└── pcaps/        # captured evidence (created by capture.sh)
```
