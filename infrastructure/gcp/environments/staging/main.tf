##############################
# GCP STAGING Environment - Cloud Run
# Min 1 instance (no cold start), tighter security
##############################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
  backend "gcs" {
    bucket = "devops-assignment-tf-state-pravardhan-gcp"
    prefix = "gcp/staging"  # Isolated state from dev
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = "asia-south1"
}

locals {
  env     = "staging"
  project = var.gcp_project_id
  region  = "asia-south1"
  labels  = { project = "devops-assignment", environment = local.env, managed-by = "terraform" }
}

resource "google_artifact_registry_repository" "backend" {
  location      = local.region
  repository_id = "devops-${local.env}-backend"
  format        = "DOCKER"
  labels        = local.labels
}

resource "google_artifact_registry_repository" "frontend" {
  location      = local.region
  repository_id = "devops-${local.env}-frontend"
  format        = "DOCKER"
  labels        = local.labels
}

resource "google_service_account" "staging_runner" {
  account_id   = "devops-${local.env}-runner"
  display_name = "Staging Cloud Run SA"
}

resource "google_project_iam_member" "staging_ar_reader" {
  project = local.project
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.staging_runner.email}"
}

resource "google_cloud_run_v2_service" "backend" {
  name     = "devops-${local.env}-backend"
  location = local.region
  labels   = local.labels

  template {
    service_account = google_service_account.staging_runner.email

    scaling {
      min_instance_count = 1   # Staging: keep 1 warm (no cold starts)
      max_instance_count = 5
    }

    containers {
      image = "${local.region}-docker.pkg.dev/${local.project}/devops-${local.env}-backend/backend:latest"
      ports { container_port = 8000 }

      env {
        name  = "ALLOWED_ORIGINS"
        value = "https://devops-staging-frontend-*.run.app"
      }

      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = false  # Keep CPU always allocated in staging for accurate testing
      }

      liveness_probe {
        http_get { path = "/api/health", port = 8000 }
        initial_delay_seconds = 10
        period_seconds        = 30
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  deletion_protection = false
}

resource "google_cloud_run_v2_service_iam_member" "backend_public" {
  project  = local.project
  location = local.region
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service" "frontend" {
  name     = "devops-${local.env}-frontend"
  location = local.region
  labels   = local.labels

  template {
    service_account = google_service_account.staging_runner.email

    scaling {
      min_instance_count = 1
      max_instance_count = 5
    }

    containers {
      image = "${local.region}-docker.pkg.dev/${local.project}/devops-${local.env}-frontend/frontend:latest"
      ports { container_port = 3000 }

      env {
        name  = "NEXT_PUBLIC_API_URL"
        value = google_cloud_run_v2_service.backend.uri
      }

      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = false
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  deletion_protection = false
  depends_on = [google_cloud_run_v2_service.backend]
}

resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  project  = local.project
  location = local.region
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

variable "gcp_project_id" { type = string }

output "backend_url"  { value = google_cloud_run_v2_service.backend.uri }
output "frontend_url" { value = google_cloud_run_v2_service.frontend.uri }
