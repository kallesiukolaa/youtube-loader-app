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