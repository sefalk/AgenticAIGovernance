---
category: devops
applies_to: [cloud]
complexity: advanced
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [ci_cd, containerization, monitoring_observability]
---
# Infrastructure as Code

## Purpose

Infrastructure as Code (IaC) manages and provisions infrastructure through machine-readable configuration files rather than manual processes. It makes infrastructure reproducible, version-controlled, reviewable, and testable. Invoke this skill when provisioning cloud resources, defining Level-3 infrastructure workflows, or selecting IaC tooling at Level 4.

## Principles

- **Declarative over imperative:** Describe the desired state, not the steps to get there. Let the tool handle convergence.
- **Immutable infrastructure:** Replace, don't patch. When infrastructure needs updating, create new instances and destroy old ones.
- **Version-controlled:** All infrastructure config lives in git. Changes go through PR review (Review Principle, AAIG L1).
- **Verifiability (AAIG L1):** Infrastructure changes are validated via plan/preview before apply. Drift is detected and corrected.

## Techniques & Patterns

### Tool Comparison

| Tool | Language | State | Best For |
|------|----------|-------|----------|
| **Terraform** | HCL | Remote state file | Multi-cloud, most widely adopted |
| **OpenTofu** | HCL | Remote state file | Open-source Terraform fork |
| **Pulumi** | Python, TS, Go, C# | Remote state | Teams preferring general-purpose languages |
| **AWS CDK** | TypeScript, Python, Java | CloudFormation | AWS-only, programmatic patterns |
| **CloudFormation** | YAML/JSON | AWS-managed | AWS-native, no state management needed |
| **Ansible** | YAML | Stateless | Configuration management, server setup |
| **Crossplane** | YAML (K8s CRDs) | Kubernetes | Managing cloud resources via Kubernetes |

### Terraform Example

```hcl
# main.tf
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket = "myproject-tfstate"
    key    = "prod/terraform.tfstate"
    region = "eu-central-1"
  }
}

resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type
  tags          = { Name = "web-server", Environment = var.environment }
}
```

### Project Structure

```
infrastructure/
â"œâ"€â"€ modules/                  # Reusable modules
â"‚   â"œâ"€â"€ networking/
â"‚   â"‚   â"œâ"€â"€ main.tf
â"‚   â"‚   â"œâ"€â"€ variables.tf
â"‚   â"‚   â""â"€â"€ outputs.tf
â"‚   â""â"€â"€ compute/
â"œâ"€â"€ environments/             # Environment-specific configs
â"‚   â"œâ"€â"€ dev/
â"‚   â"‚   â"œâ"€â"€ main.tf          # Calls modules with dev params
â"‚   â"‚   â""â"€â"€ terraform.tfvars
â"‚   â"œâ"€â"€ staging/
â"‚   â""â"€â"€ production/
â""â"€â"€ README.md
```

### State Management

| Practice | Description |
|----------|-------------|
| **Remote state** | Store state in S3, GCS, Azure Blob, or Terraform Cloud. Never local. |
| **State locking** | Use DynamoDB (AWS) or equivalent to prevent concurrent modifications. |
| **State isolation** | Separate state files per environment. Never share state across envs. |
| **No manual state edits** | Use `terraform state mv`, `terraform import`, not text editors. |

### Drift Detection

Infrastructure drift occurs when real infrastructure diverges from the declared state.

**Detection:**
- Run `terraform plan` on a schedule (daily). Alert if drift detected.
- Use tools like `driftctl` for continuous drift monitoring.

**Prevention:**
- All changes go through IaC, never through the cloud console.
- Use Service Control Policies / Organization Policies to restrict manual changes.

### Testing IaC

| Level | Tool | What It Tests |
|-------|------|---------------|
| **Linting** | `tflint`, `checkov`, `tfsec` | Syntax, best practices, security misconfigurations |
| **Unit** | `terraform validate`, Pulumi unit tests | Config validity, logic correctness |
| **Plan validation** | `terraform plan`, OPA/Conftest | Change preview, policy compliance |
| **Integration** | Terratest, `kitchen-terraform` | Provision real infra, validate, destroy |
| **Compliance** | Sentinel, OPA, Checkov | Policy-as-code enforcement |

### Change Workflow

```
1. Developer modifies IaC files.
2. Open PR. CI runs: lint, validate, plan.
3. Plan output posted as PR comment for reviewer.
4. Reviewer approves (Review Principle).
5. Merge to main triggers apply to staging.
6. After staging validation, apply to production (with approval gate).
```

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Plan before apply** | Always | No apply without plan review. |
| **No security findings** | 0 critical/high (tfsec/checkov) | Block merge on critical misconfigurations. |
| **State is remote and locked** | Yes | No local state in any environment. |
| **Drift check** | Weekly minimum | Alert on any unplanned divergence. |
| **Modules versioned** | All shared modules | Pin module versions. No `source = "../"` in production. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **ClickOps** | Creating resources via cloud console. Not reproducible, not reviewable. | All infrastructure through IaC. No exceptions. |
| **Mega-state** | One state file for the entire company. Slow, risky, blast radius = everything. | Split state by environment and component. |
| **No remote state** | State on developer's laptop. Lost, conflicted, not shared. | Use remote backend with locking from day one. |
| **Hardcoded values** | IP addresses, AMI IDs, account numbers in `.tf` files. | Use variables, data sources, and SSM parameters. |
| **Ignoring drift** | "It works, don't touch it." Until it doesn't. | Monitor drift. Reconcile or document exceptions. |


## See Also

- [CI/CD](../devops/ci_cd.md)
- [Containerization](../devops/containerization.md)
- [Monitoring and Observability](../devops/monitoring_observability.md)

## References

- Terraform documentation: https://developer.hashicorp.com/terraform
- Pulumi documentation: https://www.pulumi.com/docs/
- Kief Morris, *Infrastructure as Code* (2020, 2nd ed.) -- the definitive book.
- Checkov: https://www.checkov.io/
