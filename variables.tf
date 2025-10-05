variable "region" {
  description = "The GCP region to deploy the function in"
  type        = string
  default     = "europe-west1"
}

variable "function_name" {
  description = "The name of the Cloud Function"
  type        = string
  default     = "my-terraform-function"
}

variable "image_uri" {
  description = "The uri for the image used for downloading the stream."
  type        = string
  default     = "ghcr.io/kallesiukolaa/youtube_loader:latest"
}

variable "batch_job_name" {
  description = "The name for the batch job."
  type        = string
  default     = "my-batch-container-job"
}

variable "mount_path" {
  description = "The path for the container mount."
  type        = string
  default     = "/efs"
}

variable "runtime" {
  description = "The Cloud Function runtime"
  type        = string
  default     = "python311"
}

variable "schedule" {
  description = "The schedule used for the Google function"
  type        = string
  default     = "*/20 * * * *"
}