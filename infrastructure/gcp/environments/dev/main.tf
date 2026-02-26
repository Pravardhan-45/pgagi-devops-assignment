##############################
# GCP DEV Environment - Cloud Run
# Scales to zero = truly FREE
##############################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Remote state in GCS
  backend "gcs" {
    bucket = "devops-assignment-tf-state-pravardhan-gcp"
    prefix = "gcp/dev"   # Per-environment state isolation
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = "asia-south1"  # Mumbai - low latency for India traffic
}

locals {
  env     = "dev"
  project = var.gcp_project_id
  region  = "asia-south1"
  labels = {
    project     = "devops-assignment"
    environment = local.env
    managed-by  = "terraform"
    owner       = "pravardhan-45"
  }
}

##############################
# Artifact Registry
##############################
resource "google_artifact_registry_repository" "backend" {
  location      = local.region
  repository_id = "devops-${local.env}-backend"
  description   = "Backend Docker images - ${local.env}"
  format        = "DOCKER"
  labels        = local.labels
}

resource "google_artifact_registry_repository" "frontend" {
  location      = local.region
  repository_id = "devops-${local.env}-frontend"
  description   = "Frontend Docker images - ${local.env}"
  format        = "DOCKER"
  labels        = local.labels
}

##############################
# Cloud Run Service Account (least privilege)
##############################
resource "google_service_account" "dev_runner" {
  account_id   = "devops-${local.env}-runner"
  display_name = "Dev Cloud Run Service Account"
  description  = "Least-privilege SA for Cloud Run ${local.env}"
}

# Allow SA to pull from Artifact Registry
resource "google_project_iam_member" "dev_ar_reader" {
  project = local.project
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.dev_runner.email}"
}

##############################
# Backend Cloud Run Service
##############################
resource "google_cloud_run_v2_service" "backend" {
  name     = "devops-${local.env}-backend"
  location = local.region
  labels   = local.labels

  template {
    service_account = google_service_account.dev_runner.email

    scaling {
      min_instance_count = 0   # Scales to zero (free tier)
      max_instance_count = 2   # Dev: max 2 instances
    }

    containers {
      image = "${local.region}-docker.pkg.dev/${local.project}/devops-${local.env}-backend/backend:latest"

      ports {
        container_port = 8000
      }

      env {
        name  = "ALLOWED_ORIGINS"
        value = "*"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true  # Only use CPU when processing requests (cost savings)
      }

      liveness_probe {
        http_get {
          path = "/api/health"
          port = 8000
        }
        initial_delay_seconds = 10
        period_seconds        = 30
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  deletion_protection = false  # Dev: allow destroy

  depends_on = [google_artifact_registry_repository.backend]
}

# Make backend publicly accessible (unauthenticated)
resource "google_cloud_run_v2_service_iam_member" "backend_public" {
  project  = local.project
  location = local.region
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

##############################
# Frontend Cloud Run Service
##############################
resource "google_cloud_run_v2_service" "frontend" {
  name     = "devops-${local.env}-frontend"
  location = local.region
  labels   = local.labels

  template {
    service_account = google_service_account.dev_runner.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = "${local.region}-docker.pkg.dev/${local.project}/devops-${local.env}-frontend/frontend:latest"

      ports {
        container_port = 3000
      }

      env {
        name  = "NEXT_PUBLIC_API_URL"
        value = google_cloud_run_v2_service.backend.uri
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  deletion_protection = false

  depends_on = [
    google_artifact_registry_repository.frontend,
    google_cloud_run_v2_service.backend
  ]
}

resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  project  = local.project
  location = local.region
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP Project ID"
}

output "backend_url"            { value = google_cloud_run_v2_service.backend.uri }
output "frontend_url"           { value = google_cloud_run_v2_service.frontend.uri }
output "backend_ar_repository"  { value = google_artifact_registry_repository.backend.name }
output "frontend_ar_repository" { value = google_artifact_registry_repository.frontend.name }
