# 🚀 PGAGI DevOps Assignment

> FastAPI backend + Next.js frontend deployed on **AWS** (EC2 t2.micro) and **GCP** (Cloud Run) using Terraform IaC and GitHub Actions CI/CD.

**Repository:** [pravardhan-45/codetech-task3](https://github.com/pravardhan-45/codetech-task3)

---

## 🌐 Live URLs

| Cloud | Environment | Frontend | Backend API |
|-------|-------------|----------|-------------|
| **AWS** | prod | `http://AWS_IP` *(update after deploy)* | `http://AWS_IP:8000` |
| **GCP** | prod | `https://devops-prod-frontend-*.run.app` *(update after deploy)* | `https://devops-prod-backend-*.run.app` |

> 📹 **Demo Video:** *(add Loom/YouTube link after recording)*  
> 📄 **Full Documentation:** *(add Google Docs link)*

---

## 🏗️ Architecture Overview

```
                       ┌─────────────────────────────────┐
                       │         GitHub Actions CI/CD     │
                       │  push → build → push → deploy    │
                       └────────┬───────────────┬─────────┘
                                │               │
              ┌─────────────────▼──┐   ┌────────▼─────────────┐
              │   AWS (ap-south-1) │   │  GCP (asia-south1)   │
              │                    │   │                       │
              │  EC2 t2.micro      │   │  Cloud Run            │
              │  ┌──────────────┐  │   │  ┌────────────────┐  │
              │  │ Nginx :80    │  │   │  │ Frontend :3000 │  │
              │  │  ↓ /         │  │   │  └───────┬────────┘  │
              │  │ Frontend:3000│  │   │          │ env var   │
              │  │  ↓ /api/     │  │   │  ┌───────▼────────┐  │
              │  │ Backend:8000 │  │   │  │ Backend :8000  │  │
              │  └──────────────┘  │   │  └────────────────┘  │
              │  Elastic IP (static│   │  HTTPS built-in      │
              └────────────────────┘   └──────────────────────┘
                  State: S3+DynamoDB       State: GCS bucket
```

### Key Architectural Differences

| | AWS | GCP |
|--|-----|-----|
| **Compute** | EC2 t2.micro (VM) | Cloud Run (serverless) |
| **Ingress** | Nginx reverse proxy | Built-in HTTPS |
| **Scaling** | Manual (free tier) | Auto (0→20 instances) |
| **Access** | Prod: SSM Session Manager | Cloud Console |
| **Cost** | Free tier (12 months) | Always free tier |

---

## 🏃 Running Locally

### Prerequisites
- Python 3.11+, Node.js 20+, Docker, Docker Compose

### Option 1: Docker Compose (Recommended)
```bash
git clone https://github.com/pravardhan-45/codetech-task3
cd codetech-task3
docker-compose up -d

# Verify:
curl http://localhost:8000/api/health
curl http://localhost:8000/api/message
# Open: http://localhost:3000
```

### Option 2: Manual
```bash
# Backend
cd backend
python -m venv venv && source venv/bin/activate   # Windows: .\venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000

# Frontend (new terminal)
cd frontend
cp .env.local.example .env.local
npm install
npm run dev
```

---

## 🏗️ Infrastructure (Terraform)

### Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- AWS CLI configured (`aws configure`)
- GCP CLI configured (`gcloud auth application-default login`)

### One-Time Setup (State Backends)
```bash
# Install AWS CLI + configure credentials first
bash infrastructure/bootstrap-state.sh <aws_account_id> <gcp_project_id>
```

### Deploy to AWS (Dev)
```bash
cd infrastructure/aws/environments/dev
terraform init
terraform plan -var="key_pair_name=devops-assignment-key"
terraform apply -var="key_pair_name=devops-assignment-key"
```

### Deploy to GCP (Dev)
```bash
cd infrastructure/gcp/environments/dev
terraform init
terraform plan -var="gcp_project_id=YOUR_PROJECT_ID"
terraform apply -var="gcp_project_id=YOUR_PROJECT_ID"
```

---

## 🔒 GitHub Secrets Required

Set these in **GitHub → Settings → Secrets and Variables → Actions**:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM user secret key |
| `AWS_KEY_PAIR_NAME` | EC2 key pair name (e.g. `devops-assignment-key`) |
| `GCP_PROJECT_ID` | GCP Project ID |
| `GCP_SA_KEY` | GCP Service Account JSON key (base64) |

---

## 📁 Repository Structure

```
.
├── backend/                    # FastAPI backend
│   ├── app/main.py             # API endpoints (/api/health, /api/message)
│   ├── requirements.txt
│   └── Dockerfile              # Multi-stage, non-root user
├── frontend/                   # Next.js 14 frontend
│   ├── pages/index.js          # Dashboard page
│   ├── next.config.js
│   └── Dockerfile              # Multi-stage, standalone output
├── docker-compose.yml          # Local development
├── infrastructure/
│   ├── bootstrap-state.sh      # One-time state backend setup
│   ├── aws/
│   │   └── environments/
│   │       ├── dev/            # EC2 t2.micro, open SSH, 3-day logs
│   │       ├── staging/        # EC2 t2.micro, restricted SSH, 14-day logs
│   │       └── prod/           # EC2 t2.micro, no SSH (SSM only), 30-day logs
│   └── gcp/
│       └── environments/
│           ├── dev/            # Cloud Run min=0 max=2 (scales to zero)
│           ├── staging/        # Cloud Run min=1 max=5 (no cold starts)
│           └── prod/           # Cloud Run min=2 max=20, monitoring alerts
└── .github/workflows/
    ├── aws-deploy.yml          # AWS pipeline (ECR → EC2 via SSM)
    └── gcp-deploy.yml          # GCP pipeline (AR → Cloud Run + smoke test)
```

---

## 🔄 CI/CD Flow

| Branch | AWS | GCP |
|--------|-----|-----|
| `dev` | → dev ECR + dev EC2 | → dev AR + dev Cloud Run |
| `staging` | → staging ECR + staging EC2 | → staging AR + staging Cloud Run |
| `main` | → prod ECR + prod EC2 | → prod AR + prod Cloud Run |

**Deploy order:** `build image` → `push to registry` → `terraform plan` → `terraform apply` → `rolling update`

**Rollback:** Terraform reverts to previous state; EC2 pulls previous image tag; Cloud Run re-routes traffic to previous revision.

---

## 🧪 API Endpoints

| Endpoint | Method | Response |
|----------|--------|----------|
| `/api/health` | GET | `{"status": "healthy", "message": "Backend is running successfully"}` |
| `/api/message` | GET | `{"message": "You've successfully integrated the backend!"}` |
| `/` | GET | `{"message": "DevOps Assignment Backend", "status": "running"}` |
