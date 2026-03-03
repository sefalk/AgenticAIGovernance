**Version: 1.0 | Date: 2026-03-04**
**Level: 2 | Domain: Infrastructure**
**Derived from:** [L1_Core_Principles.md](L1_Core_Principles.md) (Level 1, v3.8)

---

# Level 2 — Infrastructure Domain Rules

## Purpose

This artifact derives domain-specific rules for cloud infrastructure, Infrastructure as Code (IaC), and platform engineering from the Level-1 Core Principles. These rules apply to all infrastructure management regardless of provider (AWS, GCP, Azure) or tooling (Terraform, Pulumi, CloudFormation). They are declarative constraints (SHALL/SHALL NOT) that Level-3 workflows must operationalize.

> **Note:** Rule IDs are grouped by their parent L1 principle, not assigned sequentially.

---

## Derived Rules

### From: Verifiability & Quality Assurance (L1)

**R-IF-01:** All infrastructure changes SHALL be expressed as code (IaC). Manual provisioning or configuration via cloud consoles SHALL NOT be permitted for production environments.

**R-IF-02:** Infrastructure changes SHALL be previewed before application (e.g., `terraform plan`, `pulumi preview`). Blind applies without reviewing the change set SHALL NOT be permitted.

**R-IF-03:** Infrastructure code SHALL be validated via automated checks (e.g., `tflint`, `checkov`, `tfsec`) before merge. Security misconfigurations (public S3 buckets, open security groups) SHALL be caught in CI.

### From: Transparency/Traceability (L1)

**R-IF-04:** All cloud resources SHALL be tagged with at minimum: `owner`, `environment`, `project`, and `managed-by` (e.g., `terraform`, `pulumi`). Untagged resources SHALL be flagged for cleanup.

**R-IF-05:** Infrastructure state files SHALL be stored in a remote, versioned, locked backend (e.g., S3 + DynamoDB, GCS + lock). Local state files SHALL NOT be used for shared environments.

**R-IF-06:** All infrastructure changes SHALL be tracked through version-controlled pull requests. Direct CLI applies from developer machines to shared environments SHALL NOT be permitted.

### From: Safety & Security (L1)

**R-IF-07:** Production environments SHALL be isolated from development and staging at the account/project level (e.g., separate AWS accounts, GCP projects). Cross-environment access SHALL require explicit IAM roles.

**R-IF-08:** All network ingress SHALL follow deny-by-default. Security groups and firewall rules SHALL only open the minimum required ports and source ranges.

**R-IF-09:** Encryption SHALL be enabled at rest and in transit for all data stores, object storage, and inter-service communication. Unencrypted resources SHALL NOT exist in production.

**R-IF-10:** Infrastructure credentials and cloud provider keys SHALL be managed via IAM roles, workload identity federation, or short-lived tokens. Long-lived access keys SHALL NOT be hardcoded or committed to version control.

### From: Fail-Safe & Ask First (L1)

**R-IF-11:** Destructive infrastructure operations (database deletion, storage bucket removal, VPC teardown) SHALL require explicit confirmation or a two-phase apply process. Accidental deletion protection SHALL be enabled on all stateful resources.

**R-IF-12:** Infrastructure drift (differences between the declared state and actual cloud state) SHALL be detected periodically and reported. Unresolved drift SHALL be treated as a high-priority incident.

### From: Continuous Improvement (L1)

**R-IF-13:** Infrastructure costs SHALL be monitored and reviewed. Resources with sustained low utilization SHALL be flagged for right-sizing or decommissioning.

**R-IF-14:** Infrastructure modules SHALL be reusable. Repeated copy-paste of resource blocks across projects SHALL be refactored into shared modules with versioned releases.

### From: Identity & Least Privilege (L1)

**R-IF-15:** CI/CD pipelines applying infrastructure changes SHALL use scoped service accounts with only the permissions necessary for the specific change. Admin-level credentials SHALL NOT be used in automation.

---

## Applicability

These rules apply to all infrastructure and platform engineering projects governed by the AAIG framework. They are refined at Level 3 (workflows) and Level 4 (project bindings).

## Relationship to Skills Toolbox

- R-IF-01, R-IF-02, R-IF-05 → `infrastructure_as_code.md`
- R-IF-03 → `static_analysis.md`
- R-IF-04, R-IF-13 → `monitoring_observability.md`
- R-IF-07, R-IF-08, R-IF-09, R-IF-10 → `secure_coding.md`, `secrets_management.md`
- R-IF-06 → `version_control.md`, `ci_cd.md`
- R-IF-15 → `version_control.md` (Identity section)
