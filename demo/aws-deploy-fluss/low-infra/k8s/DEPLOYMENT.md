# Complete Deployment Guide

This guide walks through deploying the entire Fluss + Flink stack on AWS EKS.

## Prerequisites

1. **AWS CLI configured** with appropriate credentials
2. **Terraform** installed (>= 1.0)
3. **kubectl** installed and configured
4. **helm** installed (>= 3.0)
5. **Docker images** built and pushed to ECR:
   - Fluss image: `fluss:0.8.0-incubating`
   - Demo image: `fluss-demo:latest` (contains producer and Flink job JAR)

## Step 1: Create EKS Cluster and Node Groups

```bash
cd aws-deploy-fluss/low-infra/terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply infrastructure
terraform apply
```

This creates:
- VPC with public/private subnets
- EKS cluster
- Node groups:
  - Coordinator nodes (1 node)
  - Tablet server nodes (3 nodes)
  - Flink JobManager node (1 node)
  - Flink TaskManager nodes (2 nodes)
- ECR repositories
- EBS CSI driver

**Wait for all nodes to join the cluster:**
```bash
kubectl get nodes
# Should show 7 nodes total
```

## Step 2: Configure kubectl

```bash
# Get kubeconfig
aws eks update-kubeconfig --name fluss-eks-cluster --region us-west-2

# Verify access
kubectl get nodes
```

## Step 3: Deploy All Kubernetes Resources

```bash
cd aws-deploy-fluss/low-infra/k8s

# Get ECR repository URLs from Terraform outputs
cd ../terraform
DEMO_IMAGE_REPO=$(terraform output -raw ecr_repository_url)
FLUSS_IMAGE_REPO=$(terraform output -raw ecr_fluss_repository_url)

# Deploy everything
cd ../k8s
./deploy.sh fluss "${DEMO_IMAGE_REPO}" latest "${FLUSS_IMAGE_REPO}"
```

The deployment script will:
1. Create namespace
2. Deploy ZooKeeper
3. Deploy Fluss (via Helm)
4. Deploy Flink cluster (JobManager + 2 TaskManagers)
5. Deploy monitoring stack (Prometheus + Grafana)
6. Deploy producer job
7. Submit Flink aggregator job to Flink cluster
8. Deploy ServiceMonitors and PodMonitors
9. Wait for components to be ready

## Step 4: Verify Deployment

### Check all pods are running:
```bash
kubectl get pods -n fluss
kubectl get pods -n monitoring
```

### Verify Flink cluster:
```bash
# Check Flink pods
kubectl get pods -n fluss -l app=flink

# Verify node placement
kubectl get pods -n fluss -l app=flink -o wide
kubectl get nodes -l flink-component --show-labels
```

### Check Flink job submission:
```bash
kubectl logs -n fluss -l app=flink-job-submission --tail=50
```

### Verify monitoring:
```bash
# Check ServiceMonitors
kubectl get servicemonitor -n fluss

# Check PodMonitors
kubectl get podmonitor -n fluss

# Check Prometheus targets (after port-forwarding)
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets
```

## Step 5: Access Services

### Flink Web UI
```bash
kubectl port-forward -n fluss svc/flink-jobmanager 8081:8081
# Open http://localhost:8081
```

### Grafana
```bash
GRAFANA_SVC=$(kubectl get svc -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n monitoring svc/$GRAFANA_SVC 3000:80
# Open http://localhost:3000
# Username: admin
# Password: admin123
```

### Prometheus
```bash
PROM_SVC=$(kubectl get svc -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n monitoring svc/$PROM_SVC 9090:9090
# Open http://localhost:9090
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      EKS Cluster                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ Coordinator │  │ Tablet Svr 1 │  │ Tablet Svr 2 │     │
│  │   (1 node)  │  │   (1 node)   │  │   (1 node)   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ JobManager  │  │ TaskManager │  │ TaskManager │     │
│  │   (1 node)  │  │   (1 node)  │  │   (1 node)  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐                       │
│  │  Producer    │  │  Monitoring │                       │
│  │    Job       │  │  (Prom/Graf)│                       │
│  └──────────────┘  └──────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Pods not starting
```bash
# Check pod events
kubectl describe pod <pod-name> -n fluss

# Check logs
kubectl logs <pod-name> -n fluss
```

### Flink job not submitted
```bash
# Check job submission logs
kubectl logs -n fluss -l app=flink-job-submission

# Check if Flink JobManager is ready
kubectl get pods -n fluss -l component=jobmanager
kubectl logs -n fluss -l component=jobmanager
```

### Metrics not appearing
```bash
# Check if ServiceMonitors are created
kubectl get servicemonitor -n fluss

# Check Prometheus targets
# Port-forward Prometheus and check /targets endpoint

# Verify metrics endpoints
kubectl port-forward -n fluss <pod-name> 8080:8080
curl http://localhost:8080/metrics
```

### Node placement issues
```bash
# Check node labels
kubectl get nodes --show-labels

# Check pod node placement
kubectl get pods -n fluss -o wide

# Check pod events for scheduling issues
kubectl describe pod <pod-name> -n fluss | grep -A 10 Events
```

## Cleanup

To destroy everything:
```bash
# Delete Kubernetes resources
kubectl delete namespace fluss monitoring

# Destroy Terraform infrastructure
cd aws-deploy-fluss/low-infra/terraform
terraform destroy
```

