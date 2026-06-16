# Wireless-Like Network MitM Simulation and Defense Mechanisms using Linux Network Namespaces

_A complete university lab blueprint for a controlled, isolated demonstration of interception, delay, packet loss, and defenses using Linux network namespaces, veth pairs, and traffic shaping. This version is designed for Ubuntu 26.04 on a 16 GB RAM host and for a report, viva, and implementation appendix._

> **Scope and ethics.** This project is for a closed lab on machines you own or are explicitly authorized to test. Keep every interface inside a private, non-routable segment with no internet egress. The goal is to study network behavior, not to attack real systems. Where the report mentions ARP-based MitM, treat it as a controlled concept demonstration: the attacker is placed on-path by the topology itself, not by stealthy spoofing against external systems.

## 1. Project Goal

Build a reproducible lab that shows how an on-path attacker affects communication between two Ubuntu virtual machines.

You will demonstrate:

- network interception visibility
- delay and jitter injection
- packet loss and throughput degradation
- ARP table behavior in a safe, controlled topology
- defense mechanisms such as static neighbor entries, firewall rules, and authentication checks
- simulation and measurement results suitable for a research paper and viva

## 2. Recommended Architecture

### Working model

Use one attacker namespace as the routing point between two victim namespaces. This is the part that fixes the capture problem: traffic must cross the attacker because the victims are on different subnets.

```text
Victim1  <----->  Attacker / Gateway / MITM Node  <----->  Victim2
10.0.0.10              10.0.0.50                        10.0.0.20
```

### Why this works

A Linux bridge acts like a switch. A third host attached to the same bridge does not automatically see victim-to-victim unicast traffic. For the attacker to capture traffic reliably, it must either:

- be in the forwarding path as a router/gateway, or
- use explicit mirroring/monitoring, or
- be the endpoint selected by ARP/gateway resolution inside the lab topology

For a university project, the cleanest and safest approach is to make the attacker the routing hop and then inject delay/loss on the attacker interfaces.

### Wireless-like simulation

Model wireless behavior with:

- `tc netem` for latency, jitter, and loss
- optional packet capture with `tcpdump` and Wireshark
- optional NS-3 reimplementation for simulation graphs and parameter sweeps

If your supervisor specifically wants a bridge in the writeup, describe it as a shared medium abstraction only. The actual capture demo should still use routed namespaces, because that is the reliable way to place the attacker on-path.

## 3. Host Requirements

This is suitable for Ubuntu 26.04 with 16 GB RAM.

Suggested allocation:

- 2 to 4 CPU cores
- 16 GB RAM
- 30 GB disk free
- Linux kernel with namespace and bridge support

If you use VirtualBox or VMware, keep the lab network isolated using host-only or internal networking only.

## 4. Install Tools

```bash
sudo apt update
sudo apt install -y iproute2 iputils-ping net-tools tcpdump wireshark iperf3 iptables bridge-utils
```

Recommended additions:

```bash
sudo apt install -y ethtool nftables python3 python3-pip graphviz gnuplot
```

For NS-3 work later, also install build tools:

```bash
sudo apt install -y git g++ python3-dev cmake ninja-build pkg-config ccache sqlite3 libsqlite3-dev libxml2 libxml2-dev libgsl-dev gsl-bin
```

## 5. Working Namespace Lab

### 5.1 Clean start

```bash
sudo ip netns del victim1 2>/dev/null || true
sudo ip netns del victim2 2>/dev/null || true
sudo ip netns del attacker 2>/dev/null || true
sudo ip link del br0 2>/dev/null || true
```

### 5.2 Create namespaces

```bash
sudo ip netns add victim1
sudo ip netns add victim2
sudo ip netns add attacker
```

### 5.3 Create links

Use two separate links so the attacker is actually on-path.

```bash
sudo ip link add v1-att type veth peer name att-v1
sudo ip link add att-v2 type veth peer name v2-att
```

### 5.4 Move interfaces into namespaces

```bash
sudo ip link set v1-att netns victim1
sudo ip link set att-v1 netns attacker
sudo ip link set att-v2 netns attacker
sudo ip link set v2-att netns victim2
```

The resulting topology is a routed chain:

```text
Victim1 namespace -- veth -- Attacker namespace -- veth -- Victim2 namespace
```

That is the cleanest version for capture, delay, loss, and report evidence.

## 6. IP Configuration

### 6.1 Victim1

```bash
sudo ip netns exec victim1 ip addr add 10.0.1.10/24 dev v1-att
sudo ip netns exec victim1 ip link set v1-att up
sudo ip netns exec victim1 ip link set lo up
```

### 6.2 Victim2

```bash
sudo ip netns exec victim2 ip addr add 10.0.2.20/24 dev v2-att
sudo ip netns exec victim2 ip link set v2-att up
sudo ip netns exec victim2 ip link set lo up
```

### 6.3 Attacker

```bash
sudo ip netns exec attacker ip addr add 10.0.1.50/24 dev att-v1
sudo ip netns exec attacker ip addr add 10.0.2.50/24 dev att-v2
sudo ip netns exec attacker ip link set att-v1 up
sudo ip netns exec attacker ip link set att-v2 up
sudo ip netns exec attacker ip link set lo up
```

### 6.4 Enable forwarding

Forwarding (`ip_forward`) is a **per-namespace** setting. It must be enabled *inside the attacker namespace*, not on the host. Setting it on the host has no effect on the attacker's forwarding behavior.

```bash
sudo ip netns exec attacker sysctl -w net.ipv4.ip_forward=1
```

Verify it is actually on (this must print `= 1`):

```bash
sudo ip netns exec attacker sysctl net.ipv4.ip_forward
```

If this is `0`, the attacker receives packets on `att-v1` but will not forward them to `att-v2`, so Victim1 gets no reply.

Optional forwarding safety for bridge traffic:

```bash
sudo sysctl -w net.bridge.bridge-nf-call-iptables=0
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0
```

## 7. Baseline Verification

### 7.1 Check routing

Set Victim1's route toward Victim2 through the attacker.

```bash
sudo ip netns exec victim1 ip route add 10.0.2.0/24 via 10.0.1.50
sudo ip netns exec victim2 ip route add 10.0.1.0/24 via 10.0.2.50
```

### 7.2 Ping test

```bash
sudo ip netns exec victim1 ping -c 5 10.0.2.20
```

### 7.3 Throughput test

On Victim2:

```bash
sudo ip netns exec victim2 iperf3 -s
```

On Victim1:

```bash
sudo ip netns exec victim1 iperf3 -c 10.0.2.20 -t 10
```

### 7.4 Capture traffic on the attacker

`tcpdump` blocks the terminal while it captures, and it only sees packets that pass **while it is running**. So you need **two terminals at once**: start the capture first, then generate traffic from the other terminal.

**Terminal A** (start first, leave running):

```bash
sudo ip netns exec attacker tcpdump -i att-v1 -nn icmp
```

**Terminal B** (run while A is still capturing):

```bash
sudo ip netns exec victim1 ping -c 5 10.0.2.20
```

Notes that make the output readable:

- Capture on a **single interface** (`-i att-v1`) rather than `-i any`. With `-i any` every forwarded packet appears **twice** — once `In` on `att-v1` and once `Out` on `att-v2`. That In/Out pair is useful as on-path *evidence*, but it doubles the line count.
- For ICMP, output is one line per packet and easy to read. For `iperf3`, the flow is a flood (hundreds of thousands of packets), so do not print it to the terminal — capture to a file instead (see 7.5).
- Add `-c 20` to auto-stop after 20 packets, or filter handshakes only with `'tcp port 5201 and tcp[tcpflags] & (tcp-syn|tcp-fin) != 0'`.

If the routing is correct, the attacker sees the packets because it is forwarding them. A reply arriving with `ttl=63` (one less than the usual 64) confirms the packet crossed exactly one router — the attacker.

### 7.5 View the traffic in Wireshark

There are two approaches. Saving to a file is the most reliable and gives you a submittable artifact for the appendix.

**Method 1 — save to a file, then open (recommended for the report).**

Capture on the attacker, write to a file:

```bash
sudo ip netns exec attacker tcpdump -i att-v1 -w ~/icmp-capture.pcap icmp
```

Generate traffic from another terminal, then stop the capture with Ctrl+C and open it:

```bash
sudo chown $USER ~/icmp-capture.pcap   # file is root-owned; fix before opening
wireshark ~/icmp-capture.pcap
```

Do not run `wireshark` itself with `sudo` — running the GUI as root is discouraged and may refuse to launch. Fix the file owner instead. For `iperf3` runs, capture with a filter so the file stays manageable:

```bash
sudo ip netns exec attacker tcpdump -i att-v1 -w ~/iperf-baseline.pcap 'tcp port 5201'
```

**Method 2 — live capture inside the namespace.**

Launch Wireshark inside the attacker namespace so `att-v1` and `att-v2` appear in its interface list:

```bash
sudo ip netns exec attacker wireshark
```

If this throws a display or D-Bus error, preserve the GUI environment:

```bash
sudo ip netns exec attacker env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY wireshark
```

Useful display filters:

- `icmp` for ping traffic
- `tcp.port == 5201` for `iperf3`
- `arp` for address-resolution traffic
- `ip.addr == 10.0.1.10 && ip.addr == 10.0.2.20` for victim-to-victim flows
- `tcp.flags.syn == 1` for connection setups only (skips the data flood)

Useful views:

- Packet List pane: who sent the packet and when
- Packet Details pane: expand the IP header to show **TTL = 63** on forwarded replies — this is your visual on-path evidence
- Packet Bytes pane: raw payload
- **Statistics → Conversations → IPv4**: per-flow packet/byte counts, useful for the results tables

For reliability in a lab report, saved `.pcap` files are easier to repeat and easier to submit as evidence.

## 8. Why Your Original Setup Did Not Capture Traffic

The bridge-only model was the problem. A bridge forwards frames to the correct port, so a third host will not automatically see victim-to-victim unicast traffic.

To fix this, the attacker must be on the forwarding path. The two correct ways are:

1. attacker as a routed gateway between two subnets
2. attacker as a deliberate mirror/monitor point in a simulation

For your lab, use option 1 for the Linux namespace project and option 2 only in the NS-3 simulation section.

## 9. Safe ARP-Based MITM Concept

For the report, describe ARP-based MitM as a conceptual on-path positioning method.

What to show safely:

- `ip neigh` output before traffic
- `ip neigh` output after traffic starts
- attacker forwarding path in the topology
- tcpdump evidence on attacker interfaces
- no real-world spoofing outside the isolated lab

Example observation commands:

```bash
sudo ip netns exec victim1 ip neigh
sudo ip netns exec victim2 ip neigh
sudo ip netns exec attacker ip neigh
```

## 10. Wireless Effects With tc netem

Apply latency, jitter, and loss to simulate wireless conditions.

### 10.1 Delay

```bash
sudo ip netns exec attacker tc qdisc add dev att-v2 root netem delay 100ms
```

### 10.2 Loss

```bash
sudo ip netns exec attacker tc qdisc add dev att-v2 root netem loss 20%
```

### 10.3 Jitter

```bash
sudo ip netns exec attacker tc qdisc add dev att-v2 root netem delay 50ms 20ms distribution normal
```

### 10.4 Remove shaping

```bash
sudo ip netns exec attacker tc qdisc del dev att-v2 root
```

You can apply netem separately to the attacker interfaces to simulate asymmetry and weak wireless links.

## 11. Attack Effects To Measure

Record results under these conditions:

- baseline
- attacker present but no shaping
- attacker with delay
- attacker with packet loss
- attacker with jitter
- attacker with application load increase
- attacker with different protocol choice

Measure:

- RTT
- throughput
- packet loss percentage
- jitter
- packet capture evidence

## 12. Defense Mechanisms

Use defensive controls in a controlled way.

### 12.1 Static neighbor entries

```bash
sudo ip netns exec victim1 ip neigh replace 10.0.2.20 lladdr <correct-mac> nud permanent dev v1-att
sudo ip netns exec victim2 ip neigh replace 10.0.1.10 lladdr <correct-mac> nud permanent dev v2-att
```

### 12.2 Firewall restrictions

```bash
sudo ip netns exec attacker iptables -P FORWARD DROP
sudo ip netns exec attacker iptables -A FORWARD -p icmp -j ACCEPT
```

Restore defaults:

```bash
sudo ip netns exec attacker iptables -F
sudo ip netns exec attacker iptables -P FORWARD ACCEPT
```

### 12.3 Authentication matrix

For the report, compare:

- no authentication
- static neighbor control
- application-layer authentication
- encrypted transport
- pinned or verified certificates

## 13. Parameter Matrix For The Report

Use this as your experiment table.

| Parameter                | Values to test                                                      |
| ------------------------ | ------------------------------------------------------------------- |
| Network topology         | routed namespaces, bridge-assisted wireless-like LAN, NS-3 topology |
| Protocols                | ICMP, TCP, UDP, HTTP-like traffic                                   |
| Attacker placement       | gateway on-path, bridge monitor, NS-3 relay                         |
| Traffic volume           | low, medium, high                                                   |
| Bandwidth                | 10 Mbps, 50 Mbps, 100 Mbps                                          |
| Session duration         | 30 s, 60 s, 120 s                                                   |
| Packet modification rate | 0%, 5%, 10%, 25%                                                    |
| Latency                  | 0 ms, 20 ms, 50 ms, 100 ms                                          |
| Packet loss rate         | 0%, 1%, 5%, 20%                                                     |
| Authentication matrix    | none, static ARP, TLS, pinned TLS, mutual TLS                       |

## 14. NS-3 Simulation Version

Use NS-3 for the reproducible, measurable simulation chapter in the paper.

### 14.1 Suggested model

- victim1, attacker, victim2 nodes
- point-to-point or Wi-Fi style links
- FlowMonitor for throughput and delay
- PacketSink and OnOffApplication or BulkSendApplication
- RateErrorModel for loss
- netem-style delay in the model or channel delay settings

### 14.2 Metrics

- throughput
- delay
- jitter
- loss
- flow-level packet counts
- capture coverage at the attacker node

### 14.3 Reportable comparison

- wired-like vs wireless-like
- TCP vs UDP
- baseline vs attack
- attack vs defense

## 15. What To Record

### Tables

- latency table
- throughput table
- loss table
- authentication comparison table
- protocol comparison table

### Screenshots

- namespace creation
- bridge and route output
- ping output
- iperf3 output
- tcpdump output
- `ip neigh` output
- Wireshark capture

### Files

- command transcript
- results CSV
- pcap files
- graphs in PNG or PDF
- final report DOCX

## 16. Suggested Report Structure

1. Title page
2. Abstract
3. Introduction
4. Background and related work
5. Threat model and ethics
6. Methodology
7. Experimental setup
8. Results
9. Discussion and defenses
10. Conclusion
11. References
12. Appendix with commands and screenshots

## 17. Deliverables You Need To Submit

- Word file of the research paper
- similarity report from the library or approved tool
- AI-generated-content report from the library or approved tool
- implementation link or repository link

## 18. Viva Answering Points

Use these short answers in the viva.

Q: What did you implement?

A: A wireless-like isolated LAN using Linux namespaces, veth links, bridge-based medium simulation, traffic shaping, and an on-path attacker gateway.

Q: Did you do real hacking?

A: No. The system is isolated and used only for controlled simulation and measurement.

Q: Why can the attacker capture traffic now?

A: Because the attacker is placed in the forwarding path between the two victim subnets, not just attached as a passive bridge member.

Q: What is the main contribution?

A: A measurable MITM-style lab that compares baseline and attacked conditions, plus defenses and protocol effects.

## 19. Common Fixes

If the attacker still sees no packets:

- verify `ip_forward=1`
- verify the routes point through the attacker
- verify Victim1 and Victim2 are in different subnets
- verify `tcpdump` is running on the attacker namespace, not the host namespace
- verify the correct interface name in each namespace
- verify the bridge is not acting as the only forwarding path
- verify no NAT or external route is bypassing the lab path

If you want the bridge-only model to observe all traffic, use explicit mirroring or a simulator. A plain bridge does not make a third host see unicast by default.

## 20. Final Recommendation

For your final submission, use two parts:

- Linux namespaces project for the live lab demonstration
- NS-3 project for the simulation, parameter sweep, and plots

That combination gives you:

- a working attacker capture demo
- a clear wireless-like behavior model
- measurable effects for the paper
- strong viva answers
- defensible, safe, isolated-lab methodology
