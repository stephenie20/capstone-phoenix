# Capstone Phoenix — TaskApp on Real Kubernetes

**Live URL:** https://stephenie.name.ng  
**API:** https://api.stephenie.name.ng  
**Stack:** React/nginx frontend · Flask/Postgres backend · k3s cluster · Argo CD GitOps  
**Cloud:** AWS (eu-west-1) · 3 nodes (1 control plane + 2 workers)

---

## Quick Start

```bash
# 1. Provision infra
cd infra/terraform && terraform init && terraform apply

# 2. Stand up k3s
cd ../ansible && ansible-playbook site.yml
export KUBECONFIG=../../kubeconfig && kubectl get nodes

# 3. Install platform (ingress, cert-manager, metrics-server, Argo CD)
bash manifests/base/platform/install.sh

# 4. Create secrets out-of-band (never committed to git)
# See docs/RUNBOOK.md § Part 4

# 5. GitOps takes over
kubectl apply -f gitops/application.yaml
kubectl -n argocd get app taskapp -w
```

Full step-by-step: [docs/RUNBOOK.md](docs/RUNBOOK.md)

---

## Repository Structure

```
capstone-phoenix/
├── infra/
│   ├── terraform/          # VPC, security groups, EC2 nodes (modular, remote state)
│   └── ansible/            # roles: hardening, k3s-server, k3s-agent
├── manifests/
│   ├── base/               # Namespace, NetworkPolicy, Postgres, Backend, Frontend
│   └── overlays/production # Pinned image tags, Ingress + TLS, replica patches
├── gitops/
│   └── application.yaml    # Argo CD Application — auto-syncs manifests/overlays/production
└── docs/
    ├── ARCHITECTURE.md     # Topology, request flow, single-server assumptions fixed
    ├── RUNBOOK.md          # Zero → running, day-2 ops, failure recovery
    ├── COST.md             # Itemised cost + halving strategy
    └── EVIDENCE/           # Screenshots proving each requirement
```

---

## Advanced Features Implemented

| Feature | Location | Evidence |
|---|---|---|
| HPA (CPU + memory) | `manifests/base/backend/service-hpa-pdb.yaml` | `docs/EVIDENCE/hpa-scale.png` |
| NetworkPolicy (default-deny) | `manifests/base/namespace/networkpolicy.yaml` | `docs/EVIDENCE/netpol.png` |
| PodDisruptionBudget + graceful shutdown | `**/service-hpa-pdb.yaml`, `**/service-pdb.yaml` | `docs/EVIDENCE/failover.png` |

---

## Grading Checklist

- [x] 3-node cluster (1 control plane + 2 workers), no single-node
- [x] Modular Terraform, remote state, no secrets/state in git
- [x] Least-privilege firewall (6443 not public)
- [x] Ansible idempotent roles, kubeconfig fetched
- [x] Dedicated namespace, ConfigMap/Secret split
- [x] Postgres as StatefulSet with PVC
- [x] Migrations as Job (PreSync hook), not in entrypoint
- [x] 2+ replicas per tier, topologySpreadConstraints
- [x] Liveness + readiness + startup probes on every workload
- [x] resources.requests + limits on every container
- [x] RollingUpdate maxUnavailable: 0
- [x] Ingress + TLS via cert-manager + Let's Encrypt
- [x] Pinned image tags (semver in overlay)
- [x] HPA on backend (CPU + memory)
- [x] NetworkPolicy default-deny + surgical allows
- [x] PodDisruptionBudget + terminationGracePeriodSeconds
- [x] Argo CD owns the cluster (commit → auto-sync demonstrated)
- [x] No plaintext secrets in git history
- [x] securityContext: runAsNonRoot, drop ALL capabilities, seccompProfile
