# Cilium and eBPF in AKS: A Practical Guide

## Why this document

This guide introduces **Cilium** and **eBPF** for teams that are new to both, with an AKS focus. It also explains how they compare with `kube-proxy` and how to use **Cilium CLI** and **Hubble** to troubleshoot network issues.

---

## What is Cilium in AKS?

**Cilium** is a Kubernetes networking and security data plane that uses eBPF in the Linux kernel.

In AKS, Cilium is available as part of Azure networking options (for example, Azure CNI powered by Cilium). In practical terms, Cilium can:

- Connect pods and services
- Enforce network policies
- Replace or reduce dependence on `kube-proxy` behavior for service load-balancing
- Provide deep network visibility through Hubble

Think of Cilium as a modern networking engine for Kubernetes that moves more packet processing into efficient kernel-level programs.

---

## What is eBPF?

**eBPF (extended Berkeley Packet Filter)** is a Linux kernel technology that lets you run sandboxed programs inside the kernel safely.

For Kubernetes networking, this means:

- Decisions can be made closer to packet processing
- Fewer context switches between kernel and user space
- Less dependence on large iptables rule chains
- Better observability with low overhead

In short, eBPF enables faster and more flexible networking and visibility.

---

## How eBPF improves performance

Compared with traditional iptables-based paths, eBPF-based data paths can improve performance by:

- **Lower latency**: packet handling happens earlier in the kernel path
- **Higher throughput**: reduced rule traversal and more direct forwarding logic
- **Better scalability**: avoids very large iptables chains as services/endpoints grow
- **Lower CPU overhead**: more efficient packet classification and forwarding

Actual gains depend on workload, node size, policy complexity, and traffic patterns, but eBPF generally scales better in large, dynamic clusters.

---

## Cilium/eBPF vs kube-proxy (high-level comparison)

| Area | kube-proxy (iptables/IPVS mode) | Cilium with eBPF |
|---|---|---|
| Service load-balancing | Managed by kube-proxy rules | Handled in eBPF data path |
| Rule scale behavior | Can become heavy with many services/endpoints | More efficient lookup paths |
| Latency | Good, but can increase with rule complexity | Typically lower and more consistent |
| CPU overhead | Higher in large rule sets | Usually lower for large-scale traffic |
| Observability | Requires multiple tools/log sources | Integrated flow visibility with Hubble |
| Network policy | Usually separate components | Native Cilium policy + observability |

`kube-proxy` is stable and widely used; Cilium is often chosen when you want stronger performance, security policy control, and packet-level visibility.

---

## Troubleshooting with Cilium CLI in AKS

> Prerequisite: install `cilium` CLI and have `kubectl` context pointed to your AKS cluster.

### 1. Check overall Cilium health

```bash
cilium status
```

Use this first to confirm:
- Cilium agents are healthy
- Operator is healthy
- Cluster networking state is ready

### 2. Run connectivity checks

```bash
cilium connectivity test
```

This runs end-to-end checks across pods/services and quickly identifies DNS, policy, and service-routing issues.

### 3. Inspect Cilium-managed endpoints

```bash
cilium endpoint list
```

Useful for confirming endpoint identity, policy state, and whether endpoints are ready.

### 4. Check policy status

```bash
cilium policy get
```

Use this to verify the expected policies are loaded and to spot mismatches between intended and active rules.

### 5. Collect troubleshooting bundle

```bash
cilium sysdump
```

Generates diagnostics (logs, state, config) for deep analysis and escalation.

---

## Troubleshooting with Hubble in AKS

Hubble provides flow-level observability for Cilium traffic.

### 1. Check Hubble status

```bash
cilium hubble status
```

### 2. Enable Hubble port-forward (if needed)

```bash
cilium hubble port-forward
```

### 3. Observe live flows

```bash
hubble observe
```

This shows source, destination, protocol, verdict (FORWARDED/DROPPED), and policy context.

### 4. Filter dropped traffic

```bash
hubble observe --verdict DROPPED
```

Best first step when an app reports timeout/refused behavior.

### 5. Filter by namespace or workload

```bash
hubble observe --namespace <namespace>
hubble observe --from-pod <namespace>/<pod-name>
hubble observe --to-pod <namespace>/<pod-name>
```

Helps isolate failures to a specific service path.

### 6. Inspect DNS-related traffic

```bash
hubble observe --protocol DNS
```

Very useful when applications fail due to name resolution issues.

---

## Recommended AKS troubleshooting workflow

1. **Check platform health**: `kubectl get nodes`, `kubectl get pods -A`
2. **Check Cilium health**: `cilium status`
3. **Run connectivity baseline**: `cilium connectivity test`
4. **Inspect live/dropped flows**: `hubble observe` and `hubble observe --verdict DROPPED`
5. **Correlate with policy**: `cilium policy get` and endpoint state
6. **Capture diagnostics**: `cilium sysdump` for escalations

---

## Key takeaways

- Cilium in AKS uses eBPF to modernize Kubernetes networking and policy enforcement.
- eBPF improves efficiency by processing traffic in-kernel with less overhead.
- Compared with kube-proxy-centric models, Cilium typically offers better scale characteristics and deeper observability.
- Cilium CLI + Hubble provide a practical toolkit for fast network troubleshooting in AKS.

---

## References

- AKS networking with Azure CNI and Cilium: https://learn.microsoft.com/azure/aks/azure-cni-powered-by-cilium
- Cilium documentation: https://docs.cilium.io/
- Cilium CLI: https://docs.cilium.io/en/stable/cheatsheet/
- Hubble observability: https://docs.cilium.io/en/stable/observability/hubble/
- eBPF overview: https://ebpf.io/what-is-ebpf/
