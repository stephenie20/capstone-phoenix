# Evidence Capture Guide

Capture each screenshot/log below and drop it in this folder.
Named exactly as shown — graders look for these filenames.

---

## nodes-ready.png
**What:** `kubectl get nodes` showing 3x Ready across control-plane and both workers.
```bash
kubectl get nodes -o wide
```
Expected:
```
NAME           STATUS   ROLES                  VERSION
ip-10-0-1-10   Ready    control-plane,master   v1.29.4+k3s1
ip-10-0-1-20   Ready    <none>                 v1.29.4+k3s1
ip-10-0-1-30   Ready    <none>                 v1.29.4+k3s1
```

---

## pods-spread.png
**What:** Pods distributed across both worker nodes (-o wide shows NODE column).
```bash
kubectl get pods -n taskapp -o wide
```
Expected: frontend-xxx and backend-xxx pods on **different** nodes.

---

## tls-valid.png
**What:** Valid Let's Encrypt certificate — not self-signed, not expired.
```bash
curl -vI https://stephenie.name.ng 2>&1 | grep -A5 "SSL certificate"
# OR visit https://www.ssllabs.com/ssltest/analyze.html?d=stephenie.name.ng
```
Expected: issuer = Let's Encrypt, no certificate errors.

---

## pvc-persist.log
**What:** Data survives a Postgres pod deletion and reschedule.
```bash
# Write a row
kubectl exec -n taskapp postgres-0 -- \
  psql -U taskapp -d taskapp -c \
  "INSERT INTO tasks (title, done) VALUES ('survive-this', false);"

# Kill the pod
kubectl delete pod postgres-0 -n taskapp

# Wait for it to restart
kubectl get pod postgres-0 -n taskapp -w

# Read the row back
kubectl exec -n taskapp postgres-0 -- \
  psql -U taskapp -d taskapp -c \
  "SELECT * FROM tasks WHERE title='survive-this';"
```
Save full terminal output as pvc-persist.log.

---

## zero-downtime.log
**What:** Unbroken stream of HTTP 200s during a rolling deployment.

Terminal 1 — start load:
```bash
# Install hey: go install github.com/rakyll/hey@latest
hey -z 120s -c 5 https://stephenie.name.ng > zero-downtime.log &
```

Terminal 2 — trigger a rolling update:
```bash
# Bump image tag in overlay, commit, push — or patch directly:
kubectl set image deployment/backend \
  backend=ghcr.io/ts-a-devops/taskapp-backend:v1.0.1 -n taskapp
kubectl rollout status deployment/backend -n taskapp
```

Wait for `hey` to finish. Open zero-downtime.log — `Status code distribution` must show only `[200]`.

---

## hpa-scale.png
**What:** HPA scaling the backend from 2 → 3+ replicas under load.

Terminal 1 — run load:
```bash
hey -z 180s -c 50 https://api.stephenie.name.ng/api/health
```

Terminal 2 — watch HPA:
```bash
watch -n 5 kubectl get hpa -n taskapp
# Also watch pods:
kubectl get pods -n taskapp -w
```
Screenshot when REPLICAS column shows > 2.

---

## argocd-synced.png
**What:** Argo CD showing the taskapp Application as Synced + Healthy.
```bash
argocd app get taskapp
# OR screenshot the Argo CD web UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit https://localhost:8080
```
Expected: `Sync Status: Synced`, `Health Status: Healthy`

---

## failover.png
**What:** App stays up after draining a worker node.

```bash
# Terminal 1 — continuous health check
watch -n 2 curl -so /dev/null -w "%{http_code}" https://stephenie.name.ng

# Terminal 2 — drain a worker
kubectl drain <worker-node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data

# Screenshot showing:
# 1. kubectl get nodes — drained node shows SchedulingDisabled
# 2. kubectl get pods -o wide — pods rescheduled to remaining node
# 3. curl still returning 200 throughout
```
