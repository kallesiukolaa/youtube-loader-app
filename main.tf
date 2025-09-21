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
  name     = "${var.function_name}-source-bucket123123"
  location = var.region
  uniform_bucket_level_access = true
}

# Uploads the zipped source code to the bucket
resource "google_storage_bucket_object" "archive" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = data.archive_file.source.output_path
}

# Deploys the Cloud Function
resource "google_cloudfunctions_function" "my_function" {
  name     = var.function_name
  runtime  = var.runtime
  region   = var.region

  entry_point         = "hello_http"
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.archive.name

  trigger_http = true
}

# Allows the function to be invoked publicly
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = file("project.txt")
  region         = google_cloudfunctions_function.my_function.region
  cloud_function = google_cloudfunctions_function.my_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}