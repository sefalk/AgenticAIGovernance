---
title: Compliance & Regulatory
description: Implementing controls for GDPR, SOC2, HIPAA, and data residency
applies_to: [all, cloud, web, data]
complexity: advanced
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [data_modeling, data_quality, secrets_management, secure_coding, authentication_authorization, structured_logging]
---
# Compliance & Regulatory

## Purpose
To ensure systems are architected and implemented to meet legal and industry regulatory requirements (e.g., GDPR, CCPA, SOC2, HIPAA) regarding data privacy, security, and auditability.

## Principles
1. **Privacy by Default and Design:** Data protection features must be built into the system core, not bolted on as an afterthought. *(AAIG L1: Safety & Security)*
2. **Data Minimization:** Only collect, process, and store the absolute minimum Personal Identifiable Information (PII) or Protected Health Information (PHI) required for the specific business context.
3. **Auditability:** User actions, system changes, and access to sensitive data must be securely logged in an immutable format to prove compliance. *(AAIG L1: Transparency/Traceability)*
4. **Residency and Sovereignty:** Architect the system to ensure data physically resides only in the jurisdictions permitted by applicable law (e.g., EU data in EU regions).

## Techniques & Patterns

### 1. Handling PII and PHI (GDPR/HIPAA)
*   **Encryption at Rest and in Transit:** Mandatory for all data stores (S3, RDS, local storage). Use TLS 1.2+ for all data movement.
*   **Tokenization/Pseudonymization:** Replace sensitive fields (SSN, credit card) with non-sensitive tokens in the primary database. Store the actual mapping in a highly restricted, isolated vault.
*   **Field-Level Encryption:** Encrypt specific sensitive columns natively in the database so that even a DBA with full access cannot read the plaintext values without the application-layer key.

### 2. The "Right to be Forgotten" (GDPR/CCPA)
*   **Soft vs. Hard Deletes:** Soft deletes (e.g., `deleted_at`) are legally insufficient for a deletion request. The application must support a "hard delete" or "cryptographic erasure" (deleting the encryption key used for that user's data).
*   **Anonymization:** Instead of outright deletion, data can be permanently anonymized (removing all links to the user's identity) so it can still be used for aggregate analytics.
*   **Cascading Deletions:** Ensure a delete request correctly spans across all microservices, caches, and third-party SaaS integrations via an orchestration workflow.

### 3. Audit Logging (SOC2/HIPAA)
*   **Immutable Logs:** Write audit logs to a Write-Once-Read-Many (WORM) storage bucket.
*   **What to Log:** Administrative actions, access to PHI/PII, authentication successes/failures, and changes to permissions.
*   **No PII in Logs:** Ensure the audit log system itself does not inadvertently become a repository of PII. Redact sensitive fields before writing.

### 4. Consent Management
*   **Granular Opt-In:** Users must explicitly opt-in to specific types of processing (marketing, analytics, essential).
*   **Revocation:** Users must be able to revoke consent as easily as they gave it, which must immediately halt subsequent processing.

## Quality Gates
*   **PII Scanning:** CI/CD pipeline runs a scanner (e.g., Nightfall, Macie) to detect accidental PII commitments in code or test fixtures.
*   **Encryption Verification:** Infrastructure-as-code linting (e.g., Checkov, tfsec) fails if a database or bucket is provisioned without encryption enabled.
*   **Tombstone Testing:** Automated integration test verifies that invoking the "Delete User" endpoint successfully removes or anonymizes data across primary tables and read replicas.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **"Just store it all"** | Storing unstructured JSON blobs indiscriminately maximizes legal liability if breached. | Define strict schemas and drop unknown fields containing potential PII. |
| **Backups as Loopholes** | Deleting a user from production but leaving their data in 7 years of backups violates GDPR. | Implement cryptographic erasure or automated backup-scrubbing. |
| **Sharing Prod DBs** | Giving developers complete dumps of the production database for local testing exposes PII. | Use data masking/obfuscation tools to generate synthetic but realistic test data. |
| **Implicit Consent** | Pre-checked boxes or "by using this site you agree" are legally invalid under GDPR. | Require explicit, active opt-in for each processing purpose. |

## See Also
*   [Data Modeling](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/data_engineering/data_modeling.md)
*   [Secure Coding](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/security/secure_coding.md)

## References
*   [GDPR Official Text](https://gdpr-info.eu/)
*   [OWASP Top 10 Privacy Risks](https://owasp.org/www-project-top-10-privacy-risks/)
*   [AICPA SOC 2 Criteria](https://www.aicpa.org/)
