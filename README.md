# CloudTech 2026 — Cloud Computing Infrastructure Automation

**LKS Nasional 2026 · Level: Advanced · Duration: 5 Hours**

---

## 📋 Read This First

Read the **shared module** for complete specifications of the 10 tasks to be completed.

---

## 🏗️ Architecture

**CloudTech 2026 — Multi-Tenant SaaS Platform (Dual-VPC Architecture)**

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ AWS Cloud                                                                                                   │
│                                                                                                             │
│  ╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗   │
│  ║ Region: us-east-1 (Virginia) — Application + Data + Monitoring                                       ║   │
│  ║                                                                                                       ║   │
│  ║  ┌───────────────────────────────────────────────────┐        ┌────────────────────────────────┐   ║   │
│  ║  │ VPC Application — cloudtech-app (10.10.0.0/16)     │        │ VPC Data — cloudtech-data       │   ║   │
│  ║  │                                                   │        │ (10.20.0.0/16)                  │   ║   │
│  ║  │  Public Subnets (10.10.1.0/24, 10.10.2.0/24)      │        │                                 │   ║   │
│  ║  │    ALB cloudtech-alb (80/443)                     │        │  Isolated Subnets               │   ║   │
│  ║  │        → Internet Gateway → NAT Gateway           │        │  (10.20.1.0/24, 10.20.2.0/24)   │   ║   │
│  ║  │                                                   │        │    • Aurora PostgreSQL 16.4     │   ║   │
│  ║  │  Private Subnets (10.10.10.0/24, 10.10.11.0/24)   │  VPC   │      Multi-AZ (2 instances)     │   ║   │
│  ║  │   ┌─────────────────────────────────────────┐     │ Peering│      cloudtech-aurora-cluster   │   ║   │
│  ║  │   │ EKS Cluster: cloudtech-eks-cluster v1.31 │◄───┼───────►│    • ElastiCache Redis 7.1      │   ║   │
│  ║  │   │  Namespace tenant-alpha:                │     │  DNS   │      cloudtech-redis            │   ║   │
│  ║  │   │    cloudtech-api (8080, metrics 9100)   │     │ enabled└────────────────────────────────┘   ║   │
│  ║  │   │    cloudtech-fe  (3000)                 │     │                                             ║   │
│  ║  │   │  Namespace tenant-beta:                 │     │  ┌──────────────────────────────────────┐   ║   │
│  ║  │   │    cloudtech-api (8080, metrics 9100)   │     │  │ Event-Driven Pipeline                │   ║   │
│  ║  │   │    cloudtech-fe  (3000)                 │     │  │  Kinesis cloudtech-event-stream      │   ║   │
│  ║  │   │  • NetworkPolicy (Tenant Isolation)     │     │  │    (2 shards, 24h)                   │   ║   │
│  ║  │   │  • Pod Security Standard: restricted    │     │  │      ↓                               │   ║   │
│  ║  │   │  • HPA (min 2, max 6, CPU 70%)          │     │  │  Lambda cloudtech-event-processor    │   ║   │
│  ║  │   └─────────────────────────────────────────┘     │  │    (Python 3.13, 512MB)              │   ║   │
│  ║  │   ┌─────────────────────────────────────────┐     │  │      ↓                               │   ║   │
│  ║  │   │ ECS Fargate (same VPC)                  │     │  │  EventBridge cloudtech-saas-events   │   ║   │
│  ║  │   │  Grafana OSS cloudtech-grafana-service  │     │  │      ├→ SNS cloudtech-user-events    │   ║   │
│  ║  │   │  Private IP (10.10.x.x)                 │     │  │      ├→ SQS cloudtech-event-queue    │   ║   │
│  ║  │   │  admin / cloudtech2026                  │     │  │      │     ↓ SQS DLQ cloudtech-dlq   │   ║   │
│  ║  │   └─────────────────────────────────────────┘     │  │      └→ DynamoDB cloudtech-audit-log │   ║   │
│  ║  └───────────────────────────────────────────────────┘  │        (TTL: expiresAt)              │   ║   │
│  ║       ▲                                                  └──────────────────────────────────────┘   ║   │
│  ║       │ Internet → ALB                                                                               ║   │
│  ║                                                                                                       ║   │
│  ║  ┌──────────────────────┐  ┌──────────────────────────┐  ┌────────────────────┐  ┌──────────────┐  ║   │
│  ║  │ ECR Repositories     │  │ CodeDeploy               │  │ CloudWatch Alarms  │  │ Transit      │  ║   │
│  ║  │  cloudtech-api-app   │  │  cloudtech-eks-app       │  │  + Container       │  │ Gateway      │  ║   │
│  ║  │  cloudtech-fe-app    │  │  Blue/Green Canary       │  │  Insights          │  │ cloudtech-   │  ║   │
│  ║  │                      │  │  10% → 100% (5 min)      │  │                    │  │ tgw-2026     │  ║   │
│  ║  │                      │  │  Trigger: manual (CLI)   │  │                    │  │              │  ║   │
│  ║  └──────────────────────┘  └────────────┬─────────────┘  └────────────────────┘  └──────┬───────┘  ║   │
│  ║                                          │ deploy (Blue/Green) to EKS                    │          ║   │
│  ║                                          └──────────────────────────────────────────────┼──▶ EKS   ║   │
│  ║                                                                                          │          ║   │
│  ╚═══════════════════════════════════════════════════════════════════════════════════════════╪═══════╝   │
│                                                                                                │           │
│                                          ┌──────────────────────┐                             │           │
│                                          │ TGW Peering          │◄────────────────────────────┘           │
│                                          │ Cross-Region         │                                          │
│                                          └──────────┬───────────┘                                          │
│                                                     │                                                      │
│  ╔══════════════════════════════════════════════════╪══════════════════════════════════════════════════╗ │
│  ║ Region: us-west-2 (Oregon) — DR Only (No Application Workload)                                        ║ │
│  ║                                                    ▼                                                   ║ │
│  ║  ┌──────────────────────┐   ┌─────────────────────────┐   ┌──────────────────────────────────────┐   ║ │
│  ║  │ Transit Gateway      │   │ DR Infrastructure       │   │ Disaster Recovery                    │   ║ │
│  ║  │ cloudtech-tgw-       │   │  VPC DR — cloudtech-mon │   │  • Aurora Global DB Replica          │   ║ │
│  ║  │ secondary            │   │  (10.30.0.0/16)         │   │  • S3 cloudtech-assets-dr            │   ║ │
│  ║  └──────────────────────┘   │  Reserved for DR        │   │    Cross-Region Replication          │   ║ │
│  ║                             └─────────────────────────┘   └──────────────────────────────────────┘   ║ │
│  ║                                                                                                       ║ │
│  ║  DR Automation:                                                                                       ║ │
│  ║   CloudWatch Alarm (cloudtech-primary-health-alarm) → EventBridge (cloudtech-dr-failover-trigger)     ║ │
│  ║     → Lambda (cloudtech-dr-failover) → SNS (cloudtech-dr-alerts)                                       ║ │
│  ╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝   │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Legend:  →  Traffic Flow    ┈┈►  Cross-VPC / Peering    ▪▪►  Replication / Failover
```

---

## 📁 Project Structure

```
.
├── app/
│   ├── api.py               # Flask REST API (:8080) + Prometheus (:9100)
│   ├── frontend.py          # Flask Frontend Dashboard (:3000)
│   └── templates/           # HTML templates (index.html)
├── docker/
│   ├── Dockerfile.api       # API container image
│   └── Dockerfile.frontend  # Frontend container image
├── helm/
│   ├── api/                 # Helm chart: API deployment
│   └── frontend/            # Helm chart: Frontend deployment
├── k8s/
│   ├── hpa.yaml             # HorizontalPodAutoscaler
│   ├── network-policies.yaml # Tenant isolation + Services
│   └── resource-quota.yaml  # Per-namespace quotas
├── lambda/
│   └── event-processor.py   # Kinesis → EventBridge → DynamoDB
├── terraform/
│   ├── main.tf              # Root config (⚠️ DO NOT MODIFY)
│   └── modules/             # ⚠️ INTENTIONAL BUGS — fix here
│       ├── alb/
│       ├── ecr/
│       ├── eks/
│       ├── elasticache/
│       ├── event-processing/
│       ├── lambda/
│       ├── monitoring/
│       ├── rds/
│       ├── s3/
│       ├── security-groups/
│       ├── transit-gateway/
│       ├── transit-gateway-peer/
│       ├── vpc/
│       └── vpc-peering/
├── requirements-api.txt      # Python deps for API
├── requirements-frontend.txt # Python deps for Frontend
└── README.md                # This file
```

---

## ⚡ Quick Start

```bash
# 1. Verify AWS credentials
aws sts get-caller-identity

# 2. Set environment
export AWS_REGION="us-east-1"
export STUDENT_NAME="<nama-kamu>"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 3. Fix Terraform bugs, then deploy
cd terraform
terraform init -backend-config="bucket=cloudtech-tfstate-${STUDENT_NAME}-${ACCOUNT_ID}" ...
terraform apply ...
```

---

## ⚠️ IMPORTANT NOTES

1. **Terraform modules contain INTENTIONAL BUGS AND MISSING RESOURCES** — you must find bugs, fix them, AND write missing resource blocks from scratch
2. **DO NOT modify `terraform/main.tf`** — only fix/add code inside `modules/`
3. **Resource prefix: `cloudtech-`** — all AWS resources must use this prefix
4. **Two VPCs in us-east-1** connected via VPC Peering (App ↔ Data)
5. **Transit Gateway** connects Virginia ↔ Oregon (cross-region DR)
6. **Grafana runs in Virginia** (ECS Fargate, private subnet) — NOT Oregon
7. **Oregon is DR only** — no application workload runs there

---

## 🔧 Key Specifications

| Component | Detail |
|-----------|--------|
| EKS | `cloudtech-eks-cluster` v1.31, t3.medium, 2-4 nodes |
| Namespaces | `tenant-alpha`, `tenant-beta` with PSS `restricted` |
| API | Port 8080, CPU 256m, Mem 512Mi, 2 replicas |
| Frontend | Port 3000, CPU 128m, Mem 256Mi, 1 replica |
| ALB Routing | `/api/*` → API, `/` → Frontend |
| Grafana | ECS Fargate, private IP, same VPC as EKS |
| Event Pipeline | Kinesis → Lambda → EventBridge → SNS/SQS/DynamoDB |
| DR | S3 CRR + CloudWatch Alarm + EventBridge + Lambda failover |

---

## 📎 References

- AWS EKS: https://docs.aws.amazon.com/eks/latest/userguide/
- Terraform AWS: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- Helm: https://helm.sh/docs/
- Kubernetes NetworkPolicy: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- VPC Peering: https://docs.aws.amazon.com/vpc/latest/peering/
- Transit Gateway: https://docs.aws.amazon.com/vpc/latest/tgw/

---

*LKS Nasional 2026 · Cloud Computing · Infrastructure Automation*
*© 2026 Cloud Computing Competition*