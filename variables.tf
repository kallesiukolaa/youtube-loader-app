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