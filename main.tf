terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      # Using a stable modern version
      version = ">= 5.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0.0"
    }
  }
}

provider "google" {
  project     = file("project.txt")
  region      = var.region
  credentials = file("gkesa_acc.json")
}

provider "google-beta" {
  project     = file("project.txt")
  region      = var.region
  credentials = file("gkesa_acc.json")
}

# Get the default Service Account used by Cloud Run/Functions
data "google_compute_default_service_account" "default" {
  project = file("project.txt")
}

# Grant "Object User" (Read + Write) to the Video Bucket
# This allows the job to:
# 1. READ cookies.txt (Fixes "Proceeding without authentication")
# 2. WRITE video files (Fixes upload permissions)
resource "google_storage_bucket_iam_member" "storage_user" {
  bucket = google_storage_bucket.video_bucket.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# -----------------------------------------------------------------
# 2. Storage Buckets
# -----------------------------------------------------------------

# Source Code Bucket
resource "google_storage_bucket" "bucket" {
  name                        = "${var.function_name}-source-bucket123123"
  location                    = var.region
  uniform_bucket_level_access = true
}

# Video Storage Bucket
resource "google_storage_bucket" "video_bucket" {
  name                        = "${var.function_name}-videos-bucket123123"
  location                    = var.region
  uniform_bucket_level_access = true
}

# -----------------------------------------------------------------
# 3. Cloud Function (Scheduler & Trigger)
# -----------------------------------------------------------------

# Zip the python source code
data "archive_file" "source" {
  type        = "zip"
  source_dir  = "./function-source"
  output_path = "./function-source.zip"
}

# Upload zip to bucket
resource "google_storage_bucket_object" "archive" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = data.archive_file.source.output_path
}

# Enable APIs
resource "google_project_service" "cloud_run_api" {
  project            = file("project.txt")
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloud_scheduler_api" {
  project            = file("project.txt")
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

# Pub/Sub Topic
resource "google_pubsub_topic" "function_schedule_topic" {
  project = file("project.txt")
  name    = "${var.function_name}-schedule-topic"
}

# Scheduler Job
resource "google_cloud_scheduler_job" "function_scheduler" {
  project   = file("project.txt")
  name      = "${var.function_name}-scheduler"
  region    = var.region
  schedule  = var.schedule
  time_zone = "Europe/Helsinki"

  pubsub_target {
    topic_name = google_pubsub_topic.function_schedule_topic.id
    # Default payload to check a specific handle (can be overridden)
    data       = base64encode(jsonencode({"channel_handle": "CHANGE_ME_TO_DEFAULT_HANDLE"}))
  }

  depends_on = [google_project_service.cloud_scheduler_api]
}

# The Cloud Function (Manager)
resource "google_cloudfunctions2_function" "my_function" {
  name     = var.function_name
  location = var.region

  build_config {
    runtime = var.runtime
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.archive.name
      }
    }
    entry_point = "check_live_stream"
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.function_schedule_topic.id
  }

  service_config {
    environment_variables = {
      JOB_NAME       = var.batch_job_name
      MOUNT_PATH     = var.mount_path
      VIDEO_BUCKET   = google_storage_bucket.video_bucket.name
      REGION         = var.region
      GCP_PROJECT_ID = file("project.txt")
    }
  }
}

# Make the Function Public (Optional - based on your original file)
resource "google_cloud_run_service_iam_member" "invoker_v2" {
  location = google_cloudfunctions2_function.my_function.location
  service  = google_cloudfunctions2_function.my_function.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# -----------------------------------------------------------------
# 4. Cloud Run Job (The Worker - Simplified)
# -----------------------------------------------------------------

resource "google_project_service" "artifact_registry_api" {
  project            = file("project.txt")
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Proxy GHCR so Cloud Run can pull images reliably
resource "google_artifact_registry_repository" "ghcr_proxy" {
  provider      = google-beta
  location      = var.region
  repository_id = "github-container-proxy"
  description   = "Remote repository proxying ghcr.io"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"
  
  remote_repository_config {
    common_repository {
      uri = "https://ghcr.io"
    }
  }
  depends_on = [google_project_service.artifact_registry_api]
}

locals {
  ghcr_repo_path    = trimprefix(var.image_uri, "ghcr.io/")
  proxied_image_uri = "${var.region}-docker.pkg.dev/${file("project.txt")}/${google_artifact_registry_repository.ghcr_proxy.repository_id}/${local.ghcr_repo_path}"
}

resource "google_cloud_run_v2_job" "batch_job" {
  name     = var.batch_job_name
  location = var.region

  template {
    template {
      timeout = "21600s" # 6 Hours

      containers {
        name  = "main-container"
        image = local.proxied_image_uri
        
        resources {
          limits = {
            # We keep RAM high to be safe, but piping uses much less than this.
            memory = "4Gi" 
            cpu    = "2"
          }
        }
      }
    }
  }
  depends_on = [google_artifact_registry_repository.ghcr_proxy]
}