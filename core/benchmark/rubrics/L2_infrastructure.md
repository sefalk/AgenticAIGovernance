# Rubric: L2 Infrastructure Domain

**Evaluates:** L2 Domain Rules → Infrastructure (15 rules)
**Source:** [L2_Infrastructure.md](../../../domains/L2_Infrastructure.md)

---

> This rubric evaluates all 15 R-IF rules. Rules are grouped by parent L1 principle.

---

## From: Verifiability & Quality Assurance

### R-IF-01: Infrastructure as Code (IaC)
| Score | Criteria |
|-------|----------|
| **Pass** | All changes expressed as code; no manual console configuration |
| **Fail** | Manual provisioning or configuration drift via console changes |

### R-IF-02: Change Preview
| Score | Criteria |
|-------|----------|
| **Pass** | Changes previewed (`plan`, `preview`) before apply |
| **Fail** | Blind applies without reviewing the change set |

### R-IF-03: Validation via Static Analysis
| Score | Criteria |
|-------|----------|
| **Pass** | IaC validated via automated security/lint checks before merge |
| **Partial** | Validation runs but ignores warnings/minor security flaws |
| **Fail** | No automated validation performed |

---

## From: Transparency/Traceability

### R-IF-04: Resource Tagging
| Score | Criteria |
|-------|----------|
| **Pass** | Resources tagged with `owner`, `environment`, `project`, `managed-by` |
| **Partial** | Some tags applied, but key tags missing |
| **Fail** | Resources created without mandatory tracking tags |

### R-IF-05: Remote State Management
| Score | Criteria |
|-------|----------|
| **Pass** | State files in remote, versioned, locked backend |
| **Partial** | Remote backend used, but lacks locking or versioning |
| **Fail** | Local state files used for shared environments |

### R-IF-06: PR-Driven Changes
| Score | Criteria |
|-------|----------|
| **Pass** | Changes tracked via version-controlled PRs; no direct CLI applies |
| **Partial** | PRs used, but CLI applies occur as "exceptions" |
| **Fail** | Direct CLI apply from developer machine |

---

## From: Safety & Security

### R-IF-07: Environment Isolation
| Score | Criteria |
|-------|----------|
| **Pass** | Prod isolated from Dev/Stage at account/project level with strict IAM |
| **Partial** | Isolated by VPC only, sharing the same account |
| **Fail** | Environments share networks or accounts without isolation boundaries |

### R-IF-08: Deny-by-Default Network Ingress
| Score | Criteria |
|-------|----------|
| **Pass** | Security groups/firewalls open minimum required ports/ranges |
| **Fail** | Overly permissive ingress (e.g., `0.0.0.0/0` on sensitive ports like 22, 3306) |

### R-IF-09: Ubiquitous Encryption
| Score | Criteria |
|-------|----------|
| **Pass** | Encryption enabled at rest and in transit for all data stores/communication |
| **Fail** | Unencrypted production data stores or plain-text communication |

### R-IF-10: Credential Management
| Score | Criteria |
|-------|----------|
| **Pass** | IAM roles, federation, or short-lived tokens used |
| **Fail** | Long-lived access keys hardcoded or committed to VCS |

---

## From: Fail-Safe & Ask First

### R-IF-11: Destructive Operation Safeguards
| Score | Criteria |
|-------|----------|
| **Pass** | Deletion protection enabled; explicit confirmation/two-phase apply for teardowns |
| **Partial** | Confirmation required in UI/CLI, but no resource-level configuration safeguard |
| **Fail** | Destructive commands run without safeguards |

### R-IF-12: Drift Detection
| Score | Criteria |
|-------|----------|
| **Pass** | Drift detected periodically, reported, and treated as incident |
| **Partial** | Drift detected but ignored or silently overwritten |
| **Fail** | No drift detection mechanism in place |

---

## From: Continuous Improvement

### R-IF-13: Cost Monitoring
| Score | Criteria |
|-------|----------|
| **Pass** | Infrastructure costs monitored; low-utilization resources flagged |
| **Fail** | No cost monitoring or review cadences |

### R-IF-14: Modular Reusability
| Score | Criteria |
|-------|----------|
| **Pass** | Repeated resource patterns extracted into versioned shared modules |
| **Partial** | Modules exist but are tightly coupled to specific projects |
| **Fail** | Copy-pasting raw resource blocks across environments/projects |

---

## From: Identity & Least Privilege

### R-IF-15: CI/CD Service Account Scoping
| Score | Criteria |
|-------|----------|
| **Pass** | CI/CD uses scoped service accounts with only necessary permissions |
| **Fail** | CI/CD uses admin-level or overly broad credentials |
