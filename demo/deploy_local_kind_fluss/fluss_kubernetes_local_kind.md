# Fluss on Kind: Local Kubernetes Deployment

This walkthrough captures the exact steps we used to run Apache Fluss on a local [Kind](https://kind.sigs.k8s.io/) cluster using a lightweight ZooKeeper deployment and the Fluss Helm chart.

---

## 1. Prerequisites

- Docker Desktop (or another Docker runtime) running locally
- `kind` CLI (v0.20 or newer)
- `kubectl` (points to your local kubeconfig)
- `helm` v3.8+
- The Fluss repo (this directory structure) checked out locally

Optional but recommended:
- `docker` CLI access for pre-loading images

---

## 2. Create the Kind cluster (with extra capacity)

We run a control-plane node plus two workers so Fluss tablets can spread out. A custom Kind config also pre-opens useful ports.

```bash
# from the FLUSS workspace root
cat <<'EOF' > kind-cluster-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            max-pods: "150"
    extraPortMappings:
      - containerPort: 30181
        hostPort: 8081
        protocol: TCP
      - containerPort: 30923
        hostPort: 9123
        protocol: TCP
      - containerPort: 30924
        hostPort: 9124
        protocol: TCP
  - role: worker
  - role: worker
EOF

kind create cluster --name fluss-kind --config kind-cluster-config.yaml
kubectl wait --for=condition=Ready node --all --timeout=180s
kubectl get nodes
```

(Optional) bump container resources so each node gets more CPU/RAM:

```bash
# adjust to taste
docker update --cpus 4 --memory 6g --memory-swap 6g fluss-kind-control-plane
docker update --cpus 3 --memory 5g --memory-swap 5g fluss-kind-worker
docker update --cpus 3 --memory 5g --memory-swap 5g fluss-kind-worker2
```

Verify the cluster:

```bash
kubectl get nodes
```

---

## 3. Install ZooKeeper (official image)

We avoid the Bitnami chart (their registry now requires credentials) and instead deploy a one-pod stateful set using the upstream `zookeeper:3.9.2` image.

```bash
kubectl apply -f zookeeper-kind.yaml
kubectl rollout status statefulset/zk
kubectl get pods
```

`zookeeper-kind.yaml` already lives in this repo and sets up:
- Service `zk-svc` (cluster IP, port 2181)
- StatefulSet `zk` (1 replica)

---

## 4. Install Fluss via Helm

Create a minimal values file that points Fluss at the custom ZooKeeper service and uses the published Apache image:

```bash
cat <<'EOF' > fluss-values-kind.yaml
persistence:
  enabled: false
image:
  registry: docker.io
  repository: apache/fluss
  tag: 0.8.0-incubating
configurationOverrides:
  "zookeeper.address": zk-svc.default.svc.cluster.local:2181
EOF
```

Add/update Helm repos and install:

```bash
helm repo add fluss https://downloads.apache.org/incubator/fluss/helm-chart
helm repo update
helm install fluss fluss/fluss \
  --version 0.8.0-incubating \
  -f fluss-values-kind.yaml
```

Watch the pods start (initial pull is ~1.3 GB; loading the Docker image into Kind ahead of time makes this instant on subsequent runs):

```bash
kubectl get pods
```

Expected state:

```
NAME                   READY   STATUS    RESTARTS   AGE
zk-0                   1/1     Running   0          2m
coordinator-server-0   1/1     Running   0          1m
tablet-server-0        1/1     Running   0          1m
tablet-server-1        1/1     Running   0          30s
tablet-server-2        1/1     Running   0          25s
```

(Optional) pre-load the Fluss image to avoid slow first runs:

```bash
docker pull apache/fluss:0.8.0-incubating
kind load docker-image apache/fluss:0.8.0-incubating --name fluss-kind
```

---

## 5. Connect & use

- Port-forward the client listener: `kubectl port-forward svc/coordinator-server-hs 9124:9124`
- Run Flink jobs / SQL clients against the Fluss catalog (`bootstrap.servers=localhost:9124`) or the raw ZooKeeper (`zk-svc.default.svc.cluster.local:2181`).

---

## 6. Teardown

```bash
helm uninstall fluss
kubectl delete -f zookeeper-kind.yaml
kind delete cluster --name fluss-kind
rm kind-cluster-config.yaml fluss-values-kind.yaml
```

---

## 7. Automate it (script)

You can run everything end-to-end with `scripts/deploy_fluss_kind.sh` (see script in this repo). It handles cluster creation, resource tuning, ZooKeeper install, Helm deploy, and basic status checks.
