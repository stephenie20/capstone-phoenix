# Runbook — Capstone Phoenix

A teammate must be able to follow this document alone and end up with a live, HTTPS,
multi-node, GitOps-managed TaskApp at `https://stephenie.name.ng`.

---

## Prerequisites

```bash
# Tools required on your laptop
terraform --version   # >= 1.6
ansible --version     # >= 2.15
kubectl version       # >= 1.28
argocd version        # >= 2.11 (CLI only — server installed on cluster)

# AWS credentials configured
aws sts get-caller-identity
```

---

## Part 1 — Provision Infrastructure (Terraform)

```bash
cd infra/terraform

# 1a. Create the S3 bucket and DynamoDB table for remote state (one-time)
aws s3 mb s3://your-phoenix-tfstate-bucket --region eu-west-1
aws dynamodb create-table \
  --table-name phoenix-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-1

# 1b. Copy and fill in your variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   ami_id           = "<Ubuntu 22.04 AMI for your region>"
#   ssh_public_key   = "<contents of ~/.ssh/id_ed25519.pub>"
#   allowed_ssh_cidr = "<your public IP>/32"
#   s3_state_bucket  = "your-phoenix-tfstate-bucket"

# 1c. Initialise and apply
terraform init \
  -backend-config="bucket=your-phoenix-tfstate-bucket" \
  -backend-config="key=capstone/phoenix.tfstate" \
  -backend-config="region=eu-west-1" \
  -backend-config="dynamodb_table=phoenix-tf-locks"

terraform plan   # review — expect 8-10 resources
terraform apply  # takes ~2 min

# 1d. Capture outputs
terraform output ansible_inventory > ../ansible/inventory/hosts.ini
terraform output control_plane_public_ip   # note this for DNS

# 1e. Verify SSH access to all nodes
CONTROL=$(terraform output -raw control_plane_public_ip)
ssh ubuntu@$CONTROL "echo OK"
for ip in $(terraform output -json worker_public_ips | jq -r '.[]'); do
  ssh ubuntu@$ip "echo worker $ip OK"
done
```

**DNS step:** Point `stephenie.name.ng` and `api.stephenie.name.ng` A records at one of your worker node public IPs (the one ingress-nginx will run on). Do this now so Let's Encrypt has time to propagate before cert-manager requests a certificate.

---

## Part 2 — Cluster Bring-up (Ansible)

```bash
cd infra/ansible

# 2a. Install required collections
ansible-galaxy collection install -r requirements.yml

# 2b. Verify connectivity
ansible all -m ping

# 2c. Run the full playbook
ansible-playbook site.yml

# Expected output: no failures, changed=0 on a second run (idempotent)

# 2d. Verify cluster from your laptop
export KUBECONFIG=$(pwd)/../../kubeconfig
kubectl get nodes -o wide
# Expected:
#   NAME              STATUS   ROLES                  AGE   VERSION
#   ip-10-0-1-10      Ready    control-plane,master   2m    v1.29.4+k3s1
#   ip-10-0-1-20      Ready    <none>                 1m    v1.29.4+k3s1
#   ip-10-0-1-30      Ready    <none>                 1m    v1.29.4+k3s1
```

---

## Part 3 — Platform Components

```bash
# 3a. Install ingress-nginx, cert-manager, metrics-server, Argo CD
bash manifests/base/platform/install.sh

# 3b. Install Calico for NetworkPolicy enforcement
# (Required because k3s Flannel does not enforce NetworkPolicy)
kubectl apply -f \
  https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml

# Wait for Calico to be ready
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=k8s-app=calico-node \
  --timeout=120s

# 3c. Get the initial Argo CD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# 3d. Log in with the CLI (optional — UI also works)
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
argocd login $ARGOCD_SERVER --username admin --insecure
```

---

## Part 4 — Secrets (out-of-band, never committed)

```bash
# 4a. Postgres secret
kubectl create secret generic postgres-secret \
  --namespace taskapp \
  --from-literal=POSTGRES_USER=taskapp \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 32)" \
  --from-literal=DATABASE_URL="postgresql://taskapp:$(kubectl get secret postgres-secret \
    -n taskapp -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)@postgres-svc:5432/taskapp"

# Simpler — set password once then reuse:
PGPASS=$(openssl rand -base64 32)
kubectl create secret generic postgres-secret \
  --namespace taskapp \
  --from-literal=POSTGRES_USER=taskapp \
  --from-literal=POSTGRES_PASSWORD="$PGPASS" \
  --from-literal=DATABASE_URL="postgresql://taskapp:${PGPASS}@postgres-svc:5432/taskapp"

# 4b. Backend Flask secret key
kubectl create secret generic backend-secret \
  --namespace taskapp \
  --from-literal=SECRET_KEY="$(openssl rand -hex 32)"
```

---

## Part 5 — GitOps Takes Over

```bash
# 5a. Edit gitops/application.yaml — set your fork's repoURL
# Then apply the Argo CD Application
kubectl apply -f gitops/application.yaml

# 5b. Watch Argo sync the app
kubectl -n argocd get app taskapp -w
# Wait for: Status: Synced  Health: Healthy

# 5c. Verify all pods are running and spread across nodes
kubectl get pods -n taskapp -o wide

# 5d. Verify the cert was issued
kubectl get certificate -n taskapp
kubectl describe certificate taskapp-tls -n taskapp
# Look for: Status: True, Reason: Ready

# 5e. Smoke test
curl -vI https://stephenie.name.ng
curl -vI https://api.stephenie.name.ng/api/health
```

---

## Day-2 Operations

### Deploy a new image version
```bash
# Edit the image tag in the overlay (prefer this over kubectl — Argo owns state)
vim manifests/overlays/production/kustomization.yaml
# Change:  newTag: "v1.0.0"  →  newTag: "v1.1.0"

git add manifests/overlays/production/kustomization.yaml
git commit -m "chore: bump backend to v1.1.0"
git push

# Argo CD auto-syncs within 3 minutes (default poll interval)
# Watch it happen:
kubectl -n argocd get app taskapp -w
```

### Scale a tier manually (temporary — git is the source of truth)
```bash
# Prefer a git commit so Argo doesn't revert your change.
# For a temporary emergency scale:
kubectl scale deployment backend --replicas=4 -n taskapp
# Note: Argo selfHeal will revert this to whatever is in git on next sync.
# To make it permanent, update the kustomization patch and commit.
```

### Roll back a bad deploy
```bash
# Option A — git revert (recommended, keeps history clean)
git revert HEAD
git push
# Argo syncs the previous image tag automatically.

# Option B — Argo CD UI rollback
argocd app rollback taskapp

# Option C — direct kubectl (emergency only, Argo will revert)
kubectl rollout undo deployment/backend -n taskapp
kubectl rollout status deployment/backend -n taskapp
```

### Run a new migration safely
```bash
# 1. Merge the migration file into the repo alongside the new image tag.
# 2. The Argo PreSync hook fires the migrate Job before app pods update.
# 3. If the migration fails, PreSync fails and the app pods are NOT updated.

# To re-run a migration manually (e.g. after fixing a bug):
kubectl delete job taskapp-migrate -n taskapp
kubectl apply -f manifests/base/backend/migrate-job.yaml
kubectl logs -n taskapp job/taskapp-migrate -f
```

### Rotate a secret
```bash
# Delete and recreate — Argo ignoreDifferences keeps it safe
kubectl delete secret postgres-secret -n taskapp
kubectl create secret generic postgres-secret \
  --namespace taskapp \
  --from-literal=POSTGRES_USER=taskapp \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 32)" \
  --from-literal=DATABASE_URL="postgresql://taskapp:<new-password>@postgres-svc:5432/taskapp"

# Rolling restart to pick up the new env vars
kubectl rollout restart deployment/backend -n taskapp
kubectl rollout status deployment/backend -n taskapp
```

---

## Failure Recovery

### A worker node dies or is drained

**What happens automatically:**
Kubernetes detects the node is unreachable (after ~40s). The node is marked `NotReady`. The pod eviction controller terminates pods on that node after a further grace period (~5 min by default, or immediately on drain). Pods are rescheduled to the remaining healthy worker. Because we have 2 replicas per tier and `minAvailable: 1` PodDisruptionBudgets, traffic continues uninterrupted via the surviving replica.

**Live demo command (drain a worker):**
```bash
# Find a worker node name
kubectl get nodes

# Drain it (simulates maintenance / node failure)
kubectl drain <worker-node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30

# Watch pods reschedule
kubectl get pods -n taskapp -o wide -w

# App should remain up throughout — verify with:
hey -z 60s -c 10 https://stephenie.name.ng   # should show 0 non-2xx

# Restore the node after demo
kubectl uncordon <worker-node-name>
```

**Expected recovery time:** 60–90 seconds from node failure to rescheduled pod passing readiness probe.

**If Postgres pod is on the drained node:**
The StatefulSet will reschedule `postgres-0` back to the same node (because the PVC's local-path is pinned to that node). The PVC re-attaches automatically. Data is intact. Recovery takes ~30s once the node is uncordoned.

---

### A backend Pod crashloops

```bash
# Diagnose
kubectl get pods -n taskapp
kubectl describe pod <crashlooping-pod> -n taskapp   # check Events section
kubectl logs <crashlooping-pod> -n taskapp --previous  # logs from the dead container

# Common causes:
# - DATABASE_URL wrong → check secret: kubectl get secret postgres-secret -n taskapp -o yaml
# - OOM killed → check limits, increase memory in deployment.yaml
# - Bad code → roll back (see rollback section above)

# Force a restart
kubectl rollout restart deployment/backend -n taskapp
```

---

### A bad migration (schema corrupted)

```bash
# 1. Immediately scale backend to 0 to stop writes
kubectl scale deployment backend --replicas=0 -n taskapp

# 2. Exec into a temporary postgres client pod
kubectl run pg-rescue --image=postgres:16.3 --rm -it \
  --env="PGPASSWORD=$(kubectl get secret postgres-secret -n taskapp \
    -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)" \
  -- psql -h postgres-svc -U taskapp -d taskapp

# 3. Inside psql — inspect alembic version table
SELECT * FROM alembic_version;
-- Roll back to previous revision manually if needed:
-- DELETE FROM alembic_version;
-- INSERT INTO alembic_version VALUES ('<previous-revision-id>');

# 4. Fix the migration file, commit, push
# 5. Scale backend back up — Argo PreSync will re-run migration
kubectl scale deployment backend --replicas=2 -n taskapp
```

---

### Postgres Pod rescheduled — prove data persists

```bash
# Write a test record
kubectl exec -n taskapp postgres-0 -- \
  psql -U taskapp -d taskapp -c \
  "INSERT INTO tasks (title, done) VALUES ('persistence-test', false);"

# Delete the pod (StatefulSet will recreate it)
kubectl delete pod postgres-0 -n taskapp

# Wait for it to restart (~15s)
kubectl get pod postgres-0 -n taskapp -w

# Verify data survived
kubectl exec -n taskapp postgres-0 -- \
  psql -U taskapp -d taskapp -c \
  "SELECT * FROM tasks WHERE title='persistence-test';"
# Expected: 1 row returned
```

---

### Tear down everything

```bash
# Remove the Argo app first (deletes all app resources)
kubectl delete -f gitops/application.yaml
kubectl delete namespace taskapp

# Destroy infrastructure
cd infra/terraform
terraform destroy
# Confirm: yes
# Verify: aws ec2 describe-instances --filters "Name=tag:Project,Values=phoenix" \
#   --query 'Reservations[].Instances[].State.Name'
# Expected: [] (empty)
```
