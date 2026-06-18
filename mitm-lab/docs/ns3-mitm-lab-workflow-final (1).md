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

Forwarding must be enabled **inside the attacker namespace**, not on the host. The `ip_forward` setting is per-namespace, so a plain host-level `sysctl` does nothing for the attacker and the victim will get no replies.

```bash
sudo ip netns exec attacker sysctl -w net.ipv4.ip_forward=1
```

Verify it is actually on:

```bash
sudo ip netns exec attacker sysctl net.ipv4.ip_forward
```

It must print `net.ipv4.ip_forward = 1`. If it prints `0`, the attacker receives packets on `att-v1` but will not forward them to `att-v2`, so victim-to-victim communication fails.

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

`tcpdump` only captures packets that pass **while it is actively running**, and it blocks the terminal it runs in. So the capture and the traffic generator must run **at the same time, in two separate terminals**. Start the capture first, then generate traffic.

**Terminal A** — start the capture and leave it running:

```bash
sudo ip netns exec attacker tcpdump -i att-v1 -nn icmp
```

**Terminal B** — generate traffic while Terminal A is still listening:

```bash
sudo ip netns exec victim1 ping -c 5 10.0.2.20
```

### 7.4.1 Quick diagnostics if the attacker sees nothing

If no traffic shows up at the attacker, check the path in this order:

Confirm victim1 actually routes through the attacker:

```bash
sudo ip netns exec victim1 ip route get 10.0.2.20
```

This should report `via 10.0.1.50 dev v1-att`. If it shows a different next-hop or no `via`, the traffic is bypassing the attacker (often a leftover host route or stale bridge).

Confirm packets are reaching and crossing the attacker by watching interface counters during a continuous ping:

```bash
sudo ip netns exec attacker tcpdump -i any -nn icmp
```

### 7.5 View the traffic in Wireshark

There are two approaches: save a `.pcap` file and open it (most reliable, best for the report), or live-capture directly inside the namespace.

#### Method 1 — Save to a file, then open (recommended)

Capture to a file from the attacker namespace:

```bash
sudo ip netns exec attacker tcpdump -i att-v1 -w ~/icmp-capture.pcap icmp
```

Generate traffic in another terminal, then stop the capture with Ctrl+C and open it:

```bash
wireshark ~/icmp-capture.pcap
```

Two things to watch out for:

- The `.pcap` is owned by root because tcpdump ran under sudo. If Wireshark reports a permission error, fix ownership first: `sudo chown $USER ~/icmp-capture.pcap`
- Do **not** launch the Wireshark GUI with sudo — running the GUI as root is discouraged and may refuse to start. Fix the file owner instead.

For an iperf3 throughput capture, write to a clearly named file per condition:

```bash
sudo ip netns exec attacker tcpdump -i att-v1 -w ~/iperf-baseline.pcap 'tcp port 5201'
```

Writing binary to a file is much faster than printing, so you get almost no kernel drops even during an iperf3 flood. This also gives you a clean, repeatable artifact to submit as evidence for each test condition.

#### Method 2 — Live capture directly in Wireshark

Launch Wireshark itself inside the attacker namespace so packets stream in live:

```bash
sudo ip netns exec attacker wireshark
```

Select `att-v1` from the interface list to start capturing, then generate traffic in another terminal. If this throws a D-Bus or display error (common when sudo changes the environment), preserve your display variables:

Method 1 is more reliable for screenshots; Method 2 is nicer for a live viva demo if it cooperates.

Useful display filters:

- `icmp` for ping traffic
- `tcp.port == 5201` for `iperf3`
- `arp` for address-resolution traffic
- `ip.addr == 10.0.1.10 && ip.addr == 10.0.2.20` for victim-to-victim flows
- `tcp.flags.syn == 1` for connection setups only (skips the data flood)
- `tcp` or `udp` for protocol-specific inspection

Useful views:

- Packet List pane: who sent the packet and when
- Packet Details pane: headers, flags, TTL, sequence numbers
- Packet Bytes pane: raw payload

#### What to point at in the report

Two things in Wireshark visually prove the attacker is on-path:

1. Click a forwarded reply, expand the **IP header** in the details pane, and show **TTL = 63** — decremented once by the attacker. This is the clearest single-screenshot proof of on-path forwarding.
2. **Statistics → Conversations → IPv4 tab** shows the victim1↔victim2 flow with per-condition byte and packet counts, which feeds directly into the results tables in section 15.

If you want live capture instead of a saved file, run Wireshark with the namespace interface as in Method 2. For reliability in a lab report, saved `.pcap` files are easier to repeat and easier to submit as evidence.

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

### 10.4 Corruption

```bash

sudo ip netns exec attacker tc qdisc add dev att-v2 root netem corrupt 50%

```
### 10.5 Duplication

```bash

sudo ip netns exec attacker tc qdisc add dev att-v2 root netem duplicate 20%

```
### 10.6 Reordering
Real wireless/multipath links sometimes deliver packets in the wrong order. This delays a fraction while letting others pass, so they arrive reordered:

```bash

sudo ip netns exec attacker tc qdisc add dev att-v2 root netem delay 50ms reorder 25% 50%

```
### 10.7 Rate limiting
Directly matches the "Bandwidth: 10/50/100 Mbps" row in your §13 parameter matrix:

```bash

sudo ip netns exec attacker tc qdisc add dev att-v2 root netem rate 1mbit

```
### 10.8 Correlated loss
Plain loss 20% drops packets independently. Real wireless loss comes in bursts. The second number correlates each drop with the previous one, which is more realistic:

```bash

sudo ip netns exec attacker tc qdisc add dev att-v2 root netem loss 20% 50%

```
### 10.9 Combining effects in one command
To model a genuinely weak wireless link, stack several in a single netem line (you can't run multiple adds — that's the "Exclusivity flag" error you just hit):

```bash

sudo ip netns exec attacker tc qdisc add dev att-v2 root netem delay 80ms 20ms loss 5% corrupt 1% duplicate 1%

```

### 10.10 Remove shaping
After each applied effect remove it to add another effect:

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

### Attacker with application load increase:

# light load — 1 stream (this is your normal baseline)
```bash
sudo ip netns exec victim1 iperf3 -c 10.0.2.20 -t 10 --repeating-payload
```
# heavy load — 10 streams
```bash
sudo ip netns exec victim1 iperf3 -c 10.0.2.20 -t 10 -P 10 --repeating-payload
```

### Different protocol choice — TCP vs UDP under the same condition:

# TCP
```bash
sudo ip netns exec victim1 iperf3 -c 10.0.2.20 -t 10 --repeating-payload
```
# UDP (also gives you jitter + loss directly)
```bash
sudo ip netns exec victim1 iperf3 -c 10.0.2.20 -u -b 100M -t 10 --repeating-payload
```


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


## 14. Deliverables You Need To Submit

- Word file of the research paper
- similarity report from the library or approved tool
- AI-generated-content report from the library or approved tool
- implementation link or repository link

## 15. Common Fixes

If the attacker still sees no packets:

- verify `ip_forward=1` **inside the attacker namespace**: `sudo ip netns exec attacker sysctl net.ipv4.ip_forward` (a host-level setting does not count)
- verify victim1 routes through the attacker: `sudo ip netns exec victim1 ip route get 10.0.2.20` should show `via 10.0.1.50`
- verify the routes point through the attacker
- verify Victim1 and Victim2 are in different subnets
- verify `tcpdump` is running on the attacker namespace, not the host namespace
- verify the capture and the traffic generator are running at the same time in two separate terminals (tcpdump only sees live traffic)
- verify you are capturing on a single interface (`-i att-v1`) for readable output
- verify the correct interface name in each namespace
- verify the bridge is not acting as the only forwarding path
- verify no NAT or external route is bypassing the lab path

If you want the bridge-only model to observe all traffic, use explicit mirroring or a simulator. A plain bridge does not make a third host see unicast by default.

