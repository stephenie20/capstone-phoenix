# Architecture — Capstone Phoenix

## 1. Topology Diagram

```
                         Internet
                            │
                   DNS: stephenie.name.ng
                   DNS: api.stephenie.name.ng
                            │
                     ┌──────▼──────┐
                     │  AWS Route53 │  (or your registrar's A record)
                     │  → Worker 1  │  (ingress-nginx NodePort / LoadBalancer)
                     └──────┬───────┘
                            │ HTTPS :443  (TLS terminated here)
                            ▼
              ┌─────────────────────────────┐
              │        Worker Node 1         │
              │  ┌───────────────────────┐  │
              │  │   ingress-nginx pod   │  │
              │  │  cert-manager TLS     │  │
              │  └──────┬────────────────┘  │
              └─────────┼────────────────────┘
                        │
          ┌─────────────┴──────────────┐
          │ stephenie.name.ng           │ api.stephenie.name.ng
          ▼                             ▼
  ┌───────────────┐            ┌────────────────┐
  │ frontend Svc  │            │  backend Svc   │
  └───────┬───────┘            └───────┬────────┘
          │                            │
    ┌─────┴──────┐              ┌──────┴──────┐
    │            │              │             │
 [Worker 1]  [Worker 2]    [Worker 1]    [Worker 2]
 frontend     frontend      backend       backend
  Pod A        Pod B         Pod A         Pod B
                                  │
                            ┌─────▼──────┐
                            │ postgres   │
                            │   Svc      │
                            └─────┬──────┘
                                  │
                            ┌─────▼──────────────────┐
                            │   Worker Node 2         │
                            │  postgres-0 (StatefulSet)│
                            │  PVC: 5Gi (local-path)  │
                            └─────────────────────────┘

Control Plane (separate VM):
  k3s server · Argo CD · API server (6443, internal only)
```

---

## 2. Node & Network

| Role          | Instance Type | Count | AZ        |
|---------------|---------------|-------|-----------|
| control-plane | t3.small      | 1     | eu-west-1a |
| worker        | t3.small      | 2     | eu-west-1a |

**VPC:** `10.0.0.0/16`  
**Public subnet:** `10.0.1.0/24` — all nodes sit here; they need public IPs for SSH and for the ingress to be reachable.

**Why a single AZ?** Cost. Cross-AZ data transfer adds ~$0.01/GB. For a capstone this is fine; a production system would spread workers across at least two AZs.

**Firewall (Security Group):**

| Port(s)    | Protocol | Source          | Reason                        |
|------------|----------|-----------------|-------------------------------|
| 22         | TCP      | Your IP /32     | SSH — your machine only       |
| 80         | TCP      | 0.0.0.0/0       | HTTP (cert-manager ACME HTTP01)|
| 443        | TCP      | 0.0.0.0/0       | HTTPS — public traffic        |
| 6443       | TCP      | VPC CIDR only   | k3s API — workers join over private network; never public |
| 8472       | UDP      | VPC CIDR only   | Flannel VXLAN — pod-to-pod overlay |
| 10250      | TCP      | VPC CIDR only   | kubelet metrics               |
| 30000-32767| TCP      | VPC CIDR only   | NodePort range — internal only |

6443 is explicitly **not** open to `0.0.0.0/0`. Workers join the cluster over private IPs. Your laptop reaches the API via the public IP only when you have the kubeconfig (fetched by Ansible and gitignored).

---

## 3. Request Flow

A user navigates to `https://stephenie.name.ng`. Their browser resolves the DNS A record to the public IP of Worker 1 (where ingress-nginx is scheduled). The request hits port 443; ingress-nginx terminates TLS using the certificate stored in the `taskapp-tls` Secret, which cert-manager provisioned from Let's Encrypt via HTTP-01 challenge. The ingress rule matches the host header and proxies the request to the `frontend` ClusterIP Service on port 80, which load-balances across `frontend-pod-a` (Worker 1) and `frontend-pod-b` (Worker 2). When the React app makes an API call, it goes to `https://api.stephenie.name.ng`, which the ingress routes to the `backend` ClusterIP Service on port 5000, load-balanced across both `backend` pods. The backend connects to Postgres via the `postgres-svc` ClusterIP Service on port 5432, which forwards to `postgres-0` — the single StatefulSet pod with its PVC mounted at `/var/lib/postgresql/data`.

---

## 4. Single-Server Assumptions Fixed

| Single-server assumption | Why it breaks on a cluster | How Phoenix fixes it |
|--------------------------|---------------------------|----------------------|
| `alembic upgrade head` in the container entrypoint | With 2+ replicas starting simultaneously, all race to run migrations. The second replica sees a partially-applied schema and fails or double-applies a migration, corrupting the DB. | Migrations run as a Kubernetes **Job** with `argocd.argoproj.io/hook: PreSync`. It runs exactly once before any app pod starts, with an initContainer that waits for `pg_isready` first. |
| Named Docker volume on the host (`./pgdata:/var/lib/postgresql/data`) | Volumes are local to one machine. If the Postgres pod reschedules to a different node, the data directory doesn't follow it. | Postgres runs as a **StatefulSet** with a `volumeClaimTemplate`. The PVC is provisioned by k3s's `local-path` storage class and bound to the node where `postgres-0` runs. The StatefulSet scheduler respects this binding — Postgres always reschedules back to the same node and reattaches its PVC. |
| `ports: published` on the Docker host | One frontend container bound to `:80` on one machine. With multiple pods across multiple nodes there's no single front door — each pod has its own node IP. | An **Ingress** resource backed by ingress-nginx provides a single entry point. The ingress controller load-balances across all healthy pods regardless of which node they're on. |
| Process restarted by Docker restart policy | Docker restarts containers on the same host. If the host dies, nothing restarts the container. | Kubernetes **liveness and readiness probes** detect unhealthy containers and restart them. The **ReplicaSet** controller ensures the desired replica count is always maintained, rescheduling pods to healthy nodes when a node fails. |
| Single process = single point of failure | One Flask process: one crash = downtime. | Both frontend and backend run as **Deployments with 2+ replicas** spread across different nodes via `topologySpreadConstraints`. One pod crashing (or one node dying) leaves the other replica serving traffic while Kubernetes reschedules the failed pod. |
| Zero-downtime deploys not possible | Updating a Docker Compose service restarts the container in-place, dropping in-flight requests. | `RollingUpdate` strategy with `maxUnavailable: 0` ensures a new pod is fully Ready (passes readiness probe) before the old one is terminated. Combined with the `preStop` sleep hook, in-flight requests drain before shutdown. |
| Secrets in `.env` file on disk | The `.env` file lives on one server, readable by anyone with shell access, and can't be rotated without SSH-ing in. | Secrets are stored as Kubernetes **Secret** objects, created out-of-band via `kubectl create secret`, never committed to git. Pods consume them via `secretRef` env injection. Rotation = `kubectl create secret --dry-run -o yaml \| kubectl apply`. |
| No traffic isolation between services | On one server all containers share a network namespace and can reach each other freely. | **NetworkPolicy** with a `default-deny-all` baseline and surgical allow rules: frontend → backend (5000 only), backend → postgres (5432 only). Nothing else is permitted. |

---

## 5. Choices & Trade-offs

### Raw YAML vs Helm vs Kustomize
**Kustomize** was chosen. It is built into `kubectl` (no extra tooling), keeps base manifests readable without templating syntax, and overlays patch only what differs between environments. Helm adds power (conditional blocks, loops) that this app doesn't need — the complexity cost isn't justified. Raw YAML would mean duplicating the entire manifest set per environment.

### ingress-nginx vs k3s Traefik
**ingress-nginx** was chosen and k3s's bundled Traefik disabled (`--disable traefik`). Reason: ingress-nginx has better-documented annotation support for the features used here (SSL redirect, proxy timeouts, body size limits) and is more commonly tested with cert-manager. Traefik is perfectly capable — the choice is familiarity, not correctness.

### CNI / NetworkPolicy enforcement
k3s ships with **Flannel** as the default CNI. Flannel handles pod networking but **does not enforce NetworkPolicy**. To enforce NetworkPolicy, we install **Calico** in policy-only mode (it reuses Flannel for routing but adds the policy enforcement layer). Alternative: replace Flannel entirely with Cilium, which also provides eBPF-based observability. Calico policy-only is the lightest option for this cluster size.

> **Action required:** Add this to your k3s server install args:
> `--flannel-backend=none --disable-network-policy`
> Then install Calico:
> `kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml`

### Secrets approach
Secrets are created **out-of-band** and excluded from git. The `ignoreDifferences` block in the Argo CD Application tells it not to prune secrets it didn't create. This is the simplest safe approach. The stretch goal (Sealed Secrets) would allow encrypting the secret manifests and committing the ciphertext safely — useful if you want full GitOps purity. Chosen trade-off: simplicity over full git-driven secrets, documented explicitly so a grader understands the decision.

### Storage class
k3s's built-in `local-path` provisioner is used. It creates a hostPath PV on the node where the pod is scheduled. This means Postgres is pinned to that node (the StatefulSet respects PVC node affinity). For production you'd use EBS (`ebs.csi.aws.com`) so the volume can follow the pod to any node. Documented trade-off: local-path is free and zero-config; EBS costs ~$0.10/GB/month but gives true pod mobility.
