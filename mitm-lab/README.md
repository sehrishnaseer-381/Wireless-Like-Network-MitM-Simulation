# Wireless-Like Network MitM Simulation and Defense Mechanisms

A controlled, fully isolated university lab that demonstrates how an on-path
attacker affects communication between two hosts, using **Linux network
namespaces**, **veth pairs**, and **`tc netem`** traffic shaping — plus the
defenses that mitigate it. An optional **NS-3** chapter adds reproducible
simulation graphs and parameter sweeps.

> **Scope and ethics.** Everything runs inside a private, non-routable segment
> with no internet egress, on a machine you own or are authorized to test. The
> attacker is placed on-path by the topology itself (a routed gateway between two
> subnets), not by spoofing real systems. The goal is to study and measure
> network behavior, not to attack anything.

## Topology

```
victim1 (10.0.1.10) --veth-- attacker (10.0.1.50 / 10.0.2.50) --veth-- victim2 (10.0.2.20)
```

The two victims sit on **different subnets**, so all victim-to-victim traffic
must cross the attacker. A reply arriving with `ttl=63` (one less than 64)
confirms the attacker forwarded it.

## Prerequisites

Ubuntu host (24.04 / 26.04) with namespace + veth support, and:

```bash
sudo apt update
sudo apt install -y iproute2 iputils-ping net-tools tcpdump wireshark iperf3 iptables
```

## Quick start

```bash
sudo ./setup.sh                                   # build the lab
sudo ip netns exec victim1 ping -c 3 10.0.2.20    # verify (expect ttl=63)
sudo ./teardown.sh                                # remove the lab
```

The lab is wiped on reboot — just re-run `setup.sh`.

## Capturing evidence

`tcpdump` only sees packets that pass **while it runs**, so use two terminals:

```bash
# Terminal A — start the capture (helper writes to evidence/<label>.pcap)
sudo ./capture.sh baseline-ping icmp

# Terminal B — generate traffic
sudo ip netns exec victim1 ping -c 10 10.0.2.20
```

Stop the capture with Ctrl+C, then open it (do **not** run Wireshark as root):

```bash
wireshark evidence/baseline-ping.pcap
```

In Wireshark, expand the IP header to show **TTL = 63** on forwarded replies,
and use **Statistics → Conversations → IPv4** for per-flow counts.

## Experiment conditions

Run each condition, record RTT / throughput / loss / jitter, and save a labeled
pcap (see `docs/workflow.md` §10–§13 for exact commands):

1. Baseline (no shaping)
2. Attacker present, no shaping
3. Delay (`netem delay 100ms`)
4. Packet loss (`netem loss 20%`)
5. Jitter (`netem delay 50ms 20ms distribution normal`)
6. Defenses (static neighbor entries, `FORWARD DROP` firewall)

## Repository layout

```
.
├── README.md            # this file
├── setup.sh             # build the lab (idempotent)
├── teardown.sh          # remove the lab
├── capture.sh           # capture attacker traffic to evidence/<label>.pcap
├── docs/
│   └── workflow.md       # full lab blueprint, commands, report structure
├── evidence/            # curated pcaps + screenshots for the report (committed)
├── captures/            # working captures (gitignored — can be large)
├── results/             # CSV tables and graphs
└── ns3/                 # NS-3 simulation code (optional chapter)
```

## License / academic note

For coursework / research use in an isolated lab only.
