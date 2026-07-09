# Cost Analysis — Capstone Phoenix

## Monthly Cost Breakdown (AWS eu-west-1, on-demand pricing)

| Resource | Spec | Qty | Unit cost | Monthly total |
|---|---|---|---|---|
| EC2 t3.small (control plane) | 2 vCPU, 2 GB RAM | 1 | $0.0208/hr | **$15.22** |
| EC2 t3.small (worker nodes) | 2 vCPU, 2 GB RAM | 2 | $0.0208/hr | **$30.44** |
| EBS gp3 root volumes | 20 GB each | 3 | $0.08/GB/month | **$4.80** |
| EBS gp3 Postgres PVC | 5 GB | 1 | $0.08/GB/month | **$0.40** |
| Data transfer out | ~5 GB/month (estimated) | — | $0.09/GB | **$0.45** |
| S3 (Terraform state) | < 1 MB | — | $0.023/GB | **< $0.01** |
| DynamoDB (state lock) | On-demand, < 1K ops | — | Pay-per-request | **< $0.01** |
| Route 53 hosted zone | — | 1 | $0.50/month | **$0.50** |

**Total: ~$51.82/month**

> Prices based on AWS eu-west-1 on-demand rates as of 2024.
> Actual bill will vary slightly with data transfer and EBS I/O.

---

## How to Cut it in Half (~$26/month)

**1. Use Spot Instances for worker nodes (~$18 saving)**

t3.small Spot in eu-west-1 averages ~$0.006/hr vs $0.0208/hr on-demand — a 71% saving. Workers are stateless (the StatefulSet PVC pins Postgres to a node, but if that worker is reclaimed, k3s reschedules it back once a new Spot instance is available). Use a mixed instance policy with a Spot interruption handler (e.g. `aws-node-termination-handler`) so pods drain gracefully before AWS reclaims the instance. The control plane stays on-demand for stability.

**2. Downsize to t3.micro for the control plane (~$7 saving)**

The control plane only runs k3s API server, Argo CD, and etcd. With 2 workers handling all app workloads, a t3.micro (1 GB RAM, $0.0104/hr) is sufficient for the control plane. Argo CD is the most memory-hungry component there; it runs comfortably in ~300 MB.

**3. Switch to a cheaper region (~$3 saving)**

eu-west-1 (Ireland) is mid-range. eu-central-1 (Frankfurt) and us-east-1 (Virginia) have slightly lower EC2 and data transfer prices for comparable instance types. Minor saving but free to implement.

**Revised estimate with all three changes:**

| Resource | Change | New monthly |
|---|---|---|
| Control plane t3.micro on-demand | Downsize | $7.59 |
| 2× worker t3.small Spot | Spot pricing | $8.76 |
| EBS volumes (unchanged) | — | $5.20 |
| Data transfer + misc | — | $0.96 |
| **Total** | | **~$22.51** |

That's a **56% reduction** from the baseline, achieved without changing the architecture or reducing the node count.

---

## Further reductions (if this were a real production system)

- **Reserved Instances (1-year):** ~40% saving on compute vs on-demand for steady-state workloads.
- **Managed RDS instead of self-hosted Postgres:** Adds ~$15/month (db.t3.micro) but removes the operational burden of backups, failover, and patching. Break-even depends on your ops time cost.
- **Reduce Postgres PVC size:** 5 GB is generous for a TaskApp. 1 GB would cost $0.08/month instead of $0.40 — negligible but worth noting.
- **Scale to zero off-hours:** If this is a demo/dev cluster, an EventBridge schedule that stops all EC2 instances overnight (8pm–8am) cuts the ~16 hours of compute per day, saving ~65% on EC2 costs during those hours.
