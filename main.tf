terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0.0"
    }
  }
}

provider "google" {
  # trimspace prevents "Permission denied" errors from hidden newlines
  project     = trimspace(file("project.txt"))
  region      = var.region
  credentials = file("gkesa_acc.json")
}

provider "google-beta" {
  project     = trimspace(file("project.txt"))
  region      = var.region
  credentials = file("gkesa_acc.json")
}

# -----------------------------------------------------------------
# 1. Identity & Security
# -----------------------------------------------------------------

locals {
  project_id = trimspace(file("project.txt"))
  # Use your custom service account to avoid default SA errors
  service_account_email = "gke-sa-test@${local.project_id}.iam.gserviceaccount.com"
}

resource "google_storage_bucket_iam_member" "storage_user" {
  bucket = google_storage_bucket.video_bucket.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${local.service_account_email}"
}

# -----------------------------------------------------------------
# 2. Storage Buckets
# -----------------------------------------------------------------

resource "google_storage_bucket" "bucket" {
  name                        = "${var.function_name}-source-bucket123123"
  location                    = var.region
  uniform_bucket_level_access = true
  
  # Cleanup old source files if any
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "video_bucket" {
  name                        = "${var.function_name}-videos-bucket123123"
  location                    = var.region
  uniform_bucket_level_access = true
}

# -----------------------------------------------------------------
# 3. Cloud Function
# -----------------------------------------------------------------

data "archive_file" "source" {
  type        = "zip"
  source_dir  = "./function-source"
  output_path = "./function-source.zip"
}

resource "google_storage_bucket_object" "archive" {
  # STATIC NAME (Overwrites the file, so no duplicates)
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = data.archive_file.source.output_path

  # Metadata forces Terraform to re-upload if code changes
  metadata = {
    hash = data.archive_file.source.output_md5
  }
}

resource "google_project_service" "cloud_run_api" {
  project            = local.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloud_scheduler_api" {
  project            = local.project_id
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

resource "google_pubsub_topic" "function_schedule_topic" {
  project = local.project_id
  name    = "${var.function_name}-schedule-topic"
}

resource "google_cloud_scheduler_job" "function_scheduler" {
  project   = local.project_id
  name      = "${var.function_name}-scheduler"
  region    = var.region
  schedule  = var.schedule
  time_zone = "Europe/Helsinki"

  pubsub_target {
    topic_name = google_pubsub_topic.function_schedule_topic.id
    data       = base64encode(file("check-channel-event.json"))
  }

  depends_on = [google_project_service.cloud_scheduler_api]
}

resource "google_cloudfunctions2_function" "my_function" {
  name     = var.function_name
  location = var.region

  build_config {
    runtime = var.runtime
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.archive.name
        # Removed unsupported 'generation' attribute
      }
    }
    
    # 🛠️ THE FIX: Add the file hash as a build env var.
    # When code changes -> Hash changes -> Terraform forces a Re-Build.
    environment_variables = {
        SOURCE_CODE_HASH = data.archive_file.source.output_md5
    }
    
    entry_point = "check_live_stream"
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.function_schedule_topic.id
  }

  service_config {
    service_account_email = local.service_account_email
    environment_variables = {
      JOB_NAME       = var.batch_job_name
      MOUNT_PATH     = var.mount_path
      VIDEO_BUCKET   = google_storage_bucket.video_bucket.name
      REGION         = var.region
      GCP_PROJECT_ID = local.project_id
    }
  }
}

resource "google_cloud_run_service_iam_member" "invoker_v2" {
  location = google_cloudfunctions2_function.my_function.location
  service  = google_cloudfunctions2_function.my_function.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# -----------------------------------------------------------------
# 4. Cloud Run Job
# -----------------------------------------------------------------

resource "google_project_service" "artifact_registry_api" {
  project            = local.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

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
  proxied_image_uri = "${var.region}-docker.pkg.dev/${local.project_id}/${google_artifact_registry_repository.ghcr_proxy.repository_id}/${local.ghcr_repo_path}"
}

resource "google_cloud_run_v2_job" "batch_job" {
  name     = var.batch_job_name
  location = var.region

  template {
    template {
      timeout = "21600s"
      service_account = local.service_account_email

      containers {
        name  = "main-container"
        image = local.proxied_image_uri
        resources {
          limits = {
            memory = "4Gi" 
            cpu    = "2"
          }
        }
      }
    }
  }
  depends_on = [google_artifact_registry_repository.ghcr_proxy]
}