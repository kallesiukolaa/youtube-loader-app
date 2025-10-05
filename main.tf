terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  project = file("project.txt")
  region  = var.region
  credentials = file("gkesa_acc.json")
}

# Creates a zip archive of the function's source code
data "archive_file" "source" {
  type        = "zip"
  source_dir  = "./function-source"
  output_path = "./function-source.zip"
}

# Creates a Google Cloud Storage bucket to hold the function's code
resource "google_storage_bucket" "bucket" {
  name    = "${var.function_name}-source-bucket123123"
  location = var.region
  uniform_bucket_level_access = true
}

# 🛠️ FIX 1: Removed the unsupported 'content_hash' line.
# Uploads the zipped source code to the bucket
resource "google_storage_bucket_object" "archive" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = data.archive_file.source.output_path
}

# Ensures the Cloud Run API is enabled, as it is required for Gen 2 Functions
resource "google_project_service" "cloud_run_api" {
  project = file("project.txt")
  service = "run.googleapis.com"
  disable_on_destroy = false
}

# Ensures the Cloud Scheduler API is enabled
resource "google_project_service" "cloud_scheduler_api" {
  project = file("project.txt")
  service = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

# Creates a Pub/Sub topic for the scheduler to target
resource "google_pubsub_topic" "function_schedule_topic" {
  project = file("project.txt")
  name    = "${var.function_name}-schedule-topic"
  # You may need to add a depends_on if the pubsub.googleapis.com API is not yet enabled
}

# Creates a Cloud Scheduler job to trigger the Pub/Sub topic
resource "google_cloud_scheduler_job" "function_scheduler" {
  project  = file("project.txt")
  name     = "${var.function_name}-scheduler"
  region   = var.region
  
  schedule = var.schedule
  
  # A descriptive name/payload to send to the function (optional but useful)
  time_zone = "Europe/Helsinki" 

  # Set the target that contains the event for the function
  # The event is stored in the file as a format {"channel_handle": "XXXYYY"}
  # You can find it from the channel url
  # https://www.youtube.com/@XXXYYY
  pubsub_target {
    topic_name = google_pubsub_topic.function_schedule_topic.id
    data       = base64encode(file("check-channel-event.json"))
  }

  depends_on = [
    google_project_service.cloud_scheduler_api
  ]
}

# Deploys the Cloud Function
resource "google_cloudfunctions2_function" "my_function" {
  name     = var.function_name
  location = var.region

  build_config {
    runtime = var.runtime
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        # 🛠️ FIX 2: Reference the object's name in the bucket, not the local file path.
        object = google_storage_bucket_object.archive.name
      }
    }
    entry_point = "check_live_stream"
    environment_variables = {
      JOB_NAME   = var.batch_job_name
      MOUNT_PATH = var.mount_path
    }
  }
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.function_schedule_topic.id
    
    # Required for Cloud Functions to automatically manage the Eventarc Service Account
  }
}

# 🛠️ FIX 3: Changed to the correct 2nd Gen/Cloud Run IAM resource and role.
# Allows the 2nd Generation function's underlying Cloud Run service to be invoked publicly
resource "google_cloud_run_service_iam_member" "invoker_v2" {
  location = google_cloudfunctions2_function.my_function.location
  service  = google_cloudfunctions2_function.my_function.name
  role     = "roles/run.invoker" # Required role for Cloud Run invoker
  member   = "allUsers"
}

# Define the Google Beta provider
provider "google-beta" {
  project     = file("project.txt")
  region      = var.region
  credentials = file("gkesa_acc.json")
}

# Ensures the Artifact Registry API is enabled
resource "google_project_service" "artifact_registry_api" {
  project = file("project.txt")
  service = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Create an Artifact Registry Remote Repository to proxy ghcr.io
resource "google_artifact_registry_repository" "ghcr_proxy" {
  provider = google-beta # Required to use the 'remote_repository_config' block
  
  location      = var.region
  repository_id = "github-container-proxy" # A unique name for your proxy repository
  description   = "Remote repository proxying ghcr.io for Cloud Run access"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY" 
  
  # Configuration specific to remote repositories
  remote_repository_config {
    description = "Proxy for ghcr.io"
    upstream_credentials {
      # Use an existing secret for authentication if the ghcr.io repo is private.
      # Public repository so no need for credentials.
    }
    # Defines the remote registry being proxied
    common_repository {
      uri =  "https://ghcr.io"
    }
  }

  depends_on = [
    google_project_service.artifact_registry_api
  ]
}

locals {
  # Strip the ghcr.io host and append the Artifact Registry path
  ghcr_repo_path = trimprefix(var.image_uri, "ghcr.io/")
  
  # Build the full proxy path: [region]-docker.pkg.dev/[project]/[remote_repo_id]/[ghcr_path]
  proxied_image_uri = "${var.region}-docker.pkg.dev/${file("project.txt")}/${google_artifact_registry_repository.ghcr_proxy.repository_id}/${local.ghcr_repo_path}"
}

# The Cloud Run Job resource definition
resource "google_cloud_run_v2_job" "batch_job" {
  name     = var.batch_job_name
  location = var.region
  template {
    template {
      containers {
        image = local.proxied_image_uri 
        volume_mounts {
          name = "output-location"
          mount_path = var.mount_path
        }
      }
      volumes {
        name = "output-location"
      }
    }
  }
  depends_on = [
    google_artifact_registry_repository.ghcr_proxy
  ]
}