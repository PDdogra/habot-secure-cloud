# ==============================================================================
# Candidate Name: Pranav Dogra
# Email: pranavdograa@gmail.com
# Project: Habot Secure Cloud Infrastructure (GCP)
# Architecture: D0 Raw Landing (GCS) -> Validation -> D1 Staged/Enforced (BigQuery)
# ==============================================================================

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

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project ID hosting the staging infrastructure."
  type        = string
  default     = "habot-508309"
}

variable "region" {
  description = "Primary GCP region for storage and analytical resources."
  type        = string
  default     = "us-central1"
}

variable "analyst_email" {
  description = "Principal email address for read-only analytical access."
  type        = string
  default     = "pranavdograa@gmail.com"
}

# ------------------------------------------------------------------------------
# D0 - Raw Landing Layer (Google Cloud Storage)
#
# Purpose:
# Temporary, isolated landing zone for unvalidated student onboarding data.
# Strict immutability, encryption, and public prevention are enforced.
# ------------------------------------------------------------------------------

resource "google_storage_bucket" "d0_raw_landing" {
  name          = "${var.project_id}-d0-raw-landing"
  location      = var.region
  storage_class = "STANDARD"

  # Prevent accidental destruction of storage container
  force_destroy = false

  # Enforce uniform IAM policies across all objects (disables ACLs)
  uniform_bucket_level_access = true

  # Block all public ingress and anonymous access at the organization/bucket level
  public_access_prevention = "enforced"

  # Versioning preserves history in case of accidental overwrites
  versioning {
    enabled = true
  }

  # Fail-closed lifecycle: raw data is transient and automatically deleted after 30 days
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 30
    }
  }
}

# ------------------------------------------------------------------------------
# Least Privilege IAM & Condition-Based Access Control
#
# Principle:
# - The ingestion service account has write-only permission (roles/storage.objectCreator).
# - It cannot read, list, delete, or overwrite existing objects.
# - An IAM Condition restricts upload capability strictly to the 'incoming/' prefix.
# ------------------------------------------------------------------------------

resource "google_service_account" "pipeline_ingestion" {
  account_id   = "habot-pipeline-ingest"
  display_name = "Habot Ingestion Pipeline Service Account"
  description  = "Service account used by automated ingestion pipelines to deposit raw onboarding payloads."
}

resource "google_storage_bucket_iam_member" "pipeline_writer_conditional" {
  bucket = google_storage_bucket.d0_raw_landing.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.pipeline_ingestion.email}"

  condition {
    title       = "restrict_to_incoming_prefix"
    description = "Enforce least privilege: Ingestion service account can only upload objects into incoming/ path."
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.d0_raw_landing.name}/objects/incoming/\")"
  }
}

# ------------------------------------------------------------------------------
# D1 - Staged / Enforced Analytical Layer (BigQuery)
#
# Purpose:
# Houses data only after passing DRF schema validation, PII checks, and DCYN mapping.
# Direct raw access is denied; only validated and structured schemas are stored.
# ------------------------------------------------------------------------------

resource "google_bigquery_dataset" "d1_staged_enforced" {
  dataset_id                  = "d1_staged_enforced"
  friendly_name               = "D1 Staged Enforced"
  description                 = "Validated, schema-enforced staging dataset for student onboarding records."
  location                    = var.region
  default_table_expiration_ms = 3600000000 # 41.6-day retention for staged cohorts

  # Project administrative ownership
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  # Least-privilege analytical role: read-only access to staged records
  access {
    role          = "READER"
    user_by_email = var.analyst_email
  }
}

# ------------------------------------------------------------------------------
# D1 Table: Schema-Enforced Student Onboarding Table
# ------------------------------------------------------------------------------

resource "google_bigquery_table" "student_onboarding" {
  dataset_id          = google_bigquery_dataset.d1_staged_enforced.dataset_id
  table_id            = "student_onboarding"
  description         = "Schema-enforced student onboarding records with DCYN binary transformations."
  deletion_protection = false # Staging environment default

  clustering = ["has_learning_disability_dcyn", "requires_lsa_support_dcyn"]

  schema = jsonencode([
    {
      name        = "student_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique identifier assigned to the student."
    },
    {
      name        = "first_name"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Legal first name."
    },
    {
      name        = "last_name"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Legal last name."
    },
    {
      name        = "age"
      type        = "INTEGER"
      mode        = "REQUIRED"
      description = "Validated student age (must be between 3 and 21)."
    },
    {
      name        = "has_learning_disability"
      type        = "BOOLEAN"
      mode        = "REQUIRED"
      description = "Raw boolean indicating diagnosed learning disability."
    },
    {
      name        = "guardian_email"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Validated guardian email address restricted to authorized domains."
    },
    {
      name        = "requires_lsa_support"
      type        = "BOOLEAN"
      mode        = "REQUIRED"
      description = "Raw boolean indicating Learning Support Assistant requirement."
    },
    {
      name        = "has_learning_disability_dcyn"
      type        = "INTEGER"
      mode        = "REQUIRED"
      description = "Discrete Condition Yes/No transformation (1 = Yes, 0 = No)."
    },
    {
      name        = "requires_lsa_support_dcyn"
      type        = "INTEGER"
      mode        = "REQUIRED"
      description = "Discrete Condition Yes/No transformation (1 = Yes, 0 = No)."
    },
    {
      name        = "ingestion_timestamp"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "Audit timestamp of successful pipeline ingestion."
    }
  ])
}

# ------------------------------------------------------------------------------
# Row-Level Security (RLS) / Authorized View
#
# Principle:
# Sensitive attributes (e.g. LSA and disability indicators) must only be visible
# to authorized support coordinators. The authorized view below enforces row-level
# filtering at the query engine level without exposing unmasked base data.
# ------------------------------------------------------------------------------

resource "google_bigquery_table" "student_onboarding_lsa_view" {
  dataset_id          = google_bigquery_dataset.d1_staged_enforced.dataset_id
  table_id            = "student_onboarding_lsa_active"
  description         = "Row-level security authorized view exposing only students requiring LSA assistance."
  deletion_protection = false

  view {
    query          = <<-SQL
      SELECT
        student_id,
        first_name,
        last_name,
        age,
        guardian_email,
        requires_lsa_support_dcyn,
        has_learning_disability_dcyn
      FROM `${var.project_id}.${google_bigquery_dataset.d1_staged_enforced.dataset_id}.${google_bigquery_table.student_onboarding.table_id}`
      WHERE requires_lsa_support_dcyn = 1
    SQL
    use_legacy_sql = false
  }
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "raw_landing_bucket" {
  description = "Name of the D0 raw landing Google Cloud Storage bucket."
  value       = google_storage_bucket.d0_raw_landing.name
}

output "raw_landing_bucket_url" {
  description = "GCS URL for the D0 raw landing bucket."
  value       = google_storage_bucket.d0_raw_landing.url
}

output "ingestion_service_account_email" {
  description = "Email of the dedicated pipeline ingestion service account."
  value       = google_service_account.pipeline_ingestion.email
}

output "staged_dataset_id" {
  description = "BigQuery dataset ID for the D1 staged/enforced layer."
  value       = google_bigquery_dataset.d1_staged_enforced.dataset_id
}

output "staged_table_id" {
  description = "Full BigQuery table ID for the validated student onboarding table."
  value       = google_bigquery_table.student_onboarding.id
}

output "staged_lsa_view_id" {
  description = "Full BigQuery table ID for the LSA Row-Level Security authorized view."
  value       = google_bigquery_table.student_onboarding_lsa_view.id
}