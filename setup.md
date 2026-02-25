Perfect. Below is your **complete, corrected, production-ready documentation** including:

* Full clean setup
* All ports (local + VM public)
* Firewall configuration
* Port-forward mapping table
* Restart scenarios
* Debug checklist
* Common failure fixes
* KIND-specific notes
* Grafana access
* Gateway explanation

You can save this as `RUNBOOK.md`.

---

# 🚆 Train-Ticket Deployment Runbook

### (KIND + Monitoring + Tracing on GCP VM)

---

# 🖥️ Environment

| Component        | Value                            |
| ---------------- | -------------------------------- |
| VM               | 32GB RAM, 8 CPU                  |
| Cloud            | Google Cloud VM                  |
| Kubernetes       | KIND (single control-plane node) |
| Helm             | v3                               |
| Namespace        | `train-ticket`                   |
| Monitoring       | Prometheus + Grafana             |
| Tracing          | SkyWalking                       |
| Service Registry | Nacos                            |
| Messaging        | RabbitMQ                         |

---

# ⚠️ Important Architecture Note

You are running:

```
Laptop → Public VM IP → VM → Docker (KIND node) → Kubernetes
```

Because KIND runs Kubernetes inside Docker:

* NodePort does NOT behave like normal Kubernetes
* You MUST use `kubectl port-forward`
* And bind with `--address 0.0.0.0`

---

# ✅ PART 1 — Complete Clean Reset

If something breaks:

## 1️⃣ Delete namespace

```bash
kubectl delete ns train-ticket
```

## 2️⃣ Delete entire KIND cluster (recommended)

```bash
kind delete cluster --name train-ticket
```

This removes:

* All pods
* PVCs
* Services
* Helm releases
* CPU allocations
* Everything

This solved your earlier CPU scheduling issue.

---

# ✅ PART 2 — Fresh Setup From Scratch

## Step 1 — Create KIND Cluster

```bash
kind create cluster --name train-ticket
```

Verify:

```bash
kubectl get nodes
```

You should see:

```
train-ticket-control-plane   Ready
```

---

## Step 2 — Create Namespace

```bash
kubectl create ns train-ticket
kubectl config set-context --current --namespace=train-ticket
```

Verify:

```bash
kubectl get pods
```

Should return:

```
No resources found
```

---

## Step 3 — Verify Prerequisites

### kubectl

```bash
kubectl version --client
```

### helm

```bash
helm version
```

### Node resources

```bash
kubectl describe node | grep -A5 Allocatable
```

Ensure:

* CPU ≥ 8
* Memory ≥ 32Gi

---

## Step 4 — Deploy Train-Ticket

From repo root:

```bash
bash hack/deploy/deploy.sh train-ticket "--with-monitoring --with-tracing"
```

This installs:

* Nacos (3 replicas)
* MySQL clusters
* RabbitMQ
* 40+ microservices
* Elasticsearch
* SkyWalking
* SkyWalking UI
* Prometheus
* Grafana

Wait:

```bash
kubectl get pods -w
```

Proceed only when everything shows:

```
1/1 Running
```

---

# 🌐 PART 3 — Exposing Services to Your Laptop

Because you're using KIND, NodePort will NOT directly work.

You must use:

```
kubectl port-forward --address 0.0.0.0
```

---

# 🔥 GCP Firewall Rule Setup

Go to:

**VPC Network → Firewall → Create Rule**

Recommended rule:

| Field       | Value                     |
| ----------- | ------------------------- |
| Targets     | All instances in network  |
| Source IPv4 | YOUR_LAPTOP_IP/32         |
| Protocols   | tcp:8080,30005,30467,3000 |

⚠️ Avoid `0.0.0.0/0` in production.

---

# 🔁 Port Forward Commands (VM)

You MUST use `--address 0.0.0.0`

---

## 🚆 Train Ticket UI

```bash
kubectl -n train-ticket port-forward svc/ts-ui-dashboard 8080:8080 --address 0.0.0.0
```

Access:

```
http://<VM_PUBLIC_IP>:8080
```

Example:

```
http://34.58.202.238:8080
```

---

## 🔍 SkyWalking UI

```bash
kubectl -n train-ticket port-forward svc/skywalking-ui 30005:8080 --address 0.0.0.0
```

Access:

```
http://<VM_PUBLIC_IP>:30005
```

---

## 🌐 Gateway

```bash
kubectl -n train-ticket port-forward svc/ts-gateway-service 30467:18888 --address 0.0.0.0
```

Health check:

```
http://<VM_PUBLIC_IP>:30467/actuator/health
```

Root `/` may return 404 (normal).

---

## 📊 Grafana (Monitoring)

Your service:

```
grafana   NodePort   3000:31000
```

Do NOT use NodePort.

Use port-forward:

```bash
kubectl -n kube-system port-forward svc/grafana 3000:3000 --address 0.0.0.0
```

Access:

```
http://<VM_PUBLIC_IP>:3000
```

Default login:

```
Username: admin
Password: admin
```

---

# 📌 Complete Port Mapping Table

| Component  | Service Port | Local VM Port | Laptop URL |
| ---------- | ------------ | ------------- | ---------- |
| UI         | 8080         | 8080          | :8080      |
| SkyWalking | 8080         | 30005         | :30005     |
| Gateway    | 18888        | 30467         | :30467     |
| Grafana    | 3000         | 3000          | :3000      |

---

# 🧠 Common Problems & Fixes

---

## ❌ 1. Port works in VM but not laptop

Check:

```bash
sudo ss -tulnp | grep PORT
```

Must show:

```
0.0.0.0:PORT
```

If shows:

```
127.0.0.1
```

Restart with `--address 0.0.0.0`

---

## ❌ 2. Port-forward stops after closing terminal

Port-forward is temporary.

Run in background:

```bash
nohup kubectl -n train-ticket port-forward svc/ts-ui-dashboard 8080:8080 --address 0.0.0.0 &
```

---

## ❌ 3. Elasticsearch / SkyWalking Pending (CPU error)

Check:

```bash
kubectl describe pod elasticsearch-xxxx
```

If error:

```
Insufficient cpu
```

Fix:

```bash
kind delete cluster --name train-ticket
kind create cluster --name train-ticket
```

---

## ❌ 4. After VM Restart

### Scenario A — KIND still exists

```bash
kind get clusters
kubectl get pods -n train-ticket
```

If running → just redo port-forwards.

---

### Scenario B — Connection refused

```bash
kubectl get nodes
```

If error:

```
connection refused
```

Recreate cluster:

```bash
kind create cluster --name train-ticket
kubectl create ns train-ticket
kubectl config set-context --current --namespace=train-ticket
bash hack/deploy/deploy.sh train-ticket
```

---

# 🧹 Complete Stop Commands

Stop app only:

```bash
kubectl delete ns train-ticket
```

Stop everything:

```bash
kind delete cluster --name train-ticket
```

---

# 📊 Final Health Checklist

Run:

```bash
kubectl get pods -n train-ticket
```

All should be:

```
1/1 Running
```

Test locally (VM):

```bash
curl -I http://localhost:8080
curl -I http://localhost:30005
curl http://localhost:30467/actuator/health
curl -I http://localhost:3000
```

All should respond.

---

# 🎯 Final System Architecture

Inside KIND:

* 40+ microservices
* 2 MySQL clusters
* Nacos (3 replicas)
* RabbitMQ
* Elasticsearch
* SkyWalking
* Prometheus
* Grafana

All running on a single KIND control-plane node.

---

# 🏆 What We Solved During Setup

1. Namespace cleanup
2. Secret deletion
3. PVC cleanup
4. CPU scheduling failure
5. KIND resource exhaustion
6. NodePort misunderstanding
7. Port-forward binding issues
8. GCP firewall configuration
9. Gateway 404 confusion
10. Grafana NodePort not reachable

---

# 🚀 You Now Have

✔ Full microservices system
✔ Monitoring
✔ Distributed tracing
✔ Public access via VM
✔ Proper firewall configuration
✔ Fully reproducible environment

---

If you'd like next, I can create:

* 📄 A clean GitHub-ready README version
* 🧠 A debugging cheat sheet
* ☁️ A GKE production deployment guide
* 🔐 HTTPS + NGINX reverse proxy setup
* 🛠 Performance tuning guide

Just tell me what level you want next.
