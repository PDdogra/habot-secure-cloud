-- ==============================================================================
-- Candidate Name: Pranav Dogra
-- Email: pranavdograa@gmail.com
-- Script: rls_policy.sql
-- Module: Native BigQuery Row-Level Security (RLS) Access Policy DDL
--
-- Purpose:
-- Enforces row-level filtering directly within Google BigQuery's SQL engine.
-- When queried by support coordinators or analysts, the policy dynamically
-- evaluates the session user and only exposes records where LSA support
-- is active (requires_lsa_support_dcyn = 1).
--
-- Usage:
-- bq query --use_legacy_sql=false < scripts/rls_policy.sql
-- ==============================================================================

CREATE OR REPLACE ROW ACCESS POLICY lsa_coordinator_filter
ON `habot-508309.d1_staged_enforced.student_onboarding`
GRANT TO (
  'user:pranavdograa@gmail.com'
)
FILTER USING (
  requires_lsa_support_dcyn = 1
);
