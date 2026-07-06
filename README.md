# CloudTech 2026 — Cloud Computing Infrastructure Automation

**LKS Nasional 2026 · Level: Advanced · Duration: 5 Hours**

---

## 📋 Read This First

Read the **shared module** for complete specifications of the 10 tasks to be completed.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────┐    ┌─────────────────────────────────────────────┐
│       us-east-1 (Virginia)                  │    │       us-west-2 (Oregon)                    │
├─────────────────────────────────────────────┤    ├─────────────────────────────────────────────┤
│                                             │    │                                             │
│  ┌─────────────────────────────────────┐   │    │  ┌─────────────────────────────────────┐   │
│  │ VPC App (10.10.0.0/16)              │   │    │  │ VPC DR (10.30.0.0/16)               │   │
│  │                                     │   │    │  │                                     │   │
│  │  Public Subnet:                     │   │    │  │  • Aurora DR Replica                │   │
│  │    • ALB                            │   │    │  │  • S3 Cross-Region Replication      │   │
│  │    • Internet Gateway               │   │    │  │  • DR Failover Lambda               │   │
│  │    • NAT Gateway                    │   │    │  │                                     │   │
│  │                                     │   │    │  └─────────────────────────────────────┘   │
│  │  Private Subnet:                    │   │    │                                             │
│  │    • EKS Cluster                    │   │    │                                             │
│  │    • Grafana (ECS Fargate)          │   │    │                                             │
│  └─────────────────────────────────────┘   │    │                                             │
│                                             │    │                                             │
│              ↕ VPC Peering                  │    │                                             │
│                                             │    │                                             │
│  ┌─────────────────────────────────────┐   │    │                                             │
│  │ VPC Data (10.20.0.0/16)             │   │    │                                             │
│  │                                     │   │    │                                             │
│  │  Isolated Subnet:                   │   │    │                                             │
│  │    • Aurora PostgreSQL              │   │    │                                             │
│  │    • Redis (ElastiCache)            │   │    │                                             │
│  └─────────────────────────────────────┘   │    │                                             │
│                                             │    │                                             │
│  ┌─────────────────────────────────────┐   │    │  ┌─────────────────────────────────────┐   │
│  │ Transit Gateway                     │───┼────┼──│ Transit Gateway                     │   │
│  │ cloudtech-tgw-2026                  │   │    │  │ cloudtech-tgw-secondary             │   │
│  └─────────────────────────────────────┘   │    │  └─────────────────────────────────────┘   │
│                                             │    │                                             │
└─────────────────────────────────────────────┘    └─────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
.
├── .github/workflows/        # CI/CD Pipeline (7 jobs)
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