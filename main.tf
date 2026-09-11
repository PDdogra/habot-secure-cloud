terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ------------------------------------------------------------
# Project configuration
# ------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project used for the Habot staging environment."
  type        = string
  default     = "habot-508309"
}

variable "region" {
  description = "Primary region for the staging resources."
  type        = string
  default     = "us-central1"
}

variable "analyst_email" {
  description = "Analyst who requires read-only access to staged data."
  type        = string
  default     = "pranavdograa@gmail.com"
}

# ------------------------------------------------------------
# D0 - Raw Landing Bucket
#
# Purpose:
# Receives raw onboarding data before it is validated and
# moved into the enforced/staged BigQuery layer.
# ------------------------------------------------------------

resource "google_storage_bucket" "d0_raw_landing" {
  name     = "${var.project_id}-d0-raw-landing"
  location = var.region

  # Do not allow Terraform to remove the bucket together
  # with its contents accidentally.
  force_destroy = false

  # Use IAM at bucket level rather than legacy object ACLs.
  uniform_bucket_level_access = true

  # Prevent the bucket from being exposed publicly.
  public_access_prevention = "enforced"

  # Keep previous object versions so accidental overwrites
  # can be recovered.
  versioning {
    enabled = true
  }

  # Raw landing data is temporary and should not remain
  # indefinitely.
  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      age = 30
    }
  }
}

# ------------------------------------------------------------
# D1 - Staged / Enforced BigQuery Dataset
#
# Purpose:
# Stores data only after it has passed the validation and
# schema enforcement stage of the pipeline.
# ------------------------------------------------------------

resource "google_bigquery_dataset" "d1_staged_enforced" {
  dataset_id = "d1_staged_enforced"

  friendly_name = "D1 Staged Enforced"

  description = "Validated and schema-enforced staging dataset for student onboarding data."

  location = var.region

  # Prevent staged data from remaining permanently.
  default_table_expiration_ms = 3600000000

  # Project owners retain administrative ownership.
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  # The analyst only needs to read the validated data.
  # No write or administrative permissions are granted.
  access {
    role          = "READER"
    user_by_email = var.analyst_email
  }
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------

output "raw_landing_bucket" {
  description = "Name of the D0 raw landing bucket."
  value       = google_storage_bucket.d0_raw_landing.name
}

output "raw_landing_bucket_url" {
  description = "GCS URL for the D0 raw landing bucket."
  value       = google_storage_bucket.d0_raw_landing.url
}

output "staged_dataset_id" {
  description = "BigQuery dataset ID for the D1 staged/enforced layer."
  value       = google_bigquery_dataset.d1_staged_enforced.dataset_id
}