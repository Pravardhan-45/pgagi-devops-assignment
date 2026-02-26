##############################
# GCP PROD Environment - Cloud Run
# High availability, traffic splitting for canary deploys
##############################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
  backend "gcs" {
    bucket = "devops-assignment-tf-state-pravardhan-gcp"
    prefix = "gcp/prod"   # Isolated from dev and staging
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = "asia-south1"
}

locals {
  env     = "prod"
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

resource "google_service_account" "prod_runner" {
  account_id   = "devops-${local.env}-runner"
  display_name = "Prod Cloud Run SA - least privilege"
}

resource "google_project_iam_member" "prod_ar_reader" {
  project = local.project
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.prod_runner.email}"
}

resource "google_cloud_run_v2_service" "backend" {
  name     = "devops-${local.env}-backend"
  location = local.region
  labels   = local.labels

  template {
    service_account = google_service_account.prod_runner.email

    # Prod: annotate with git SHA for traceability
    annotations = {
      "deploy-sha" = var.image_tag
    }

    scaling {
      min_instance_count = 2    # Prod: 2 warm instances always running
      max_instance_count = 20   # Handle 10x traffic spikes
    }

    containers {
      # Use specific tag, not 'latest', in prod
      image = "${local.region}-docker.pkg.dev/${local.project}/devops-${local.env}-backend/backend:${var.image_tag}"
      ports { container_port = 8000 }

      env {
        name  = "ALLOWED_ORIGINS"
        value = var.frontend_url
      }

      resources {
        limits   = { cpu = "2", memory = "1Gi" }
        cpu_idle = false  # Prod: CPU always on for consistent latency
      }

      liveness_probe {
        http_get { path = "/api/health", port = 8000 }
        initial_delay_seconds = 5
        period_seconds        = 30
        failure_threshold     = 3
      }

      startup_probe {
        http_get { path = "/api/health", port = 8000 }
        initial_delay_seconds = 0
        period_seconds        = 10
        failure_threshold     = 10
      }
    }
  }

  # Prod: traffic splitting enables canary / rollback
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  deletion_protection = false  # Set to true after confirming prod works
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
    service_account = google_service_account.prod_runner.email

    annotations = { "deploy-sha" = var.image_tag }

    scaling {
      min_instance_count = 2
      max_instance_count = 20
    }

    containers {
      image = "${local.region}-docker.pkg.dev/${local.project}/devops-${local.env}-frontend/frontend:${var.image_tag}"
      ports { container_port = 3000 }

      env {
        name  = "NEXT_PUBLIC_API_URL"
        value = google_cloud_run_v2_service.backend.uri
      }

      resources {
        limits   = { cpu = "2", memory = "1Gi" }
        cpu_idle = false
      }

      startup_probe {
        http_get { path = "/", port = 3000 }
        initial_delay_seconds = 0
        period_seconds        = 10
        failure_threshold     = 10
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  deletion_protection = false
  depends_on          = [google_cloud_run_v2_service.backend]
}

resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  project  = local.project
  location = local.region
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Monitoring alert for error rate in prod
resource "google_monitoring_alert_policy" "prod_error_rate" {
  display_name = "Prod - Cloud Run Error Rate"
  combiner     = "OR"

  conditions {
    display_name = "Error rate > 5%"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"devops-prod-backend\""
      duration        = "120s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  notification_channels = []  # Add email/PagerDuty channel IDs here
}

variable "gcp_project_id"  { type = string }
variable "image_tag"        { type = string, default = "latest", description = "Specific image tag to deploy (git SHA)" }
variable "frontend_url"     { type = string, default = "*", description = "Frontend URL for CORS allowlist" }

output "backend_url"   { value = google_cloud_run_v2_service.backend.uri }
output "frontend_url"  { value = google_cloud_run_v2_service.frontend.uri }
output "backend_name"  { value = google_cloud_run_v2_service.backend.name }
output "frontend_name" { value = google_cloud_run_v2_service.frontend.name }
