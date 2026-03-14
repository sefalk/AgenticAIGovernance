---
category: devops
applies_to: [api, web, microservice, cloud]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [ci_cd, infrastructure_as_code, monitoring_observability, configuration_management, ml_pipeline_design, dependency_management]
---
# Containerization

## Purpose

Containerization packages applications and their dependencies into portable, reproducible units that run identically across environments. Invoke this skill when building Docker images, optimizing container builds, or defining Level-3 container workflows.

## Principles

- **Reproducibility:** The same image produces identical behavior everywhere -- dev, CI, staging, production.
- **Minimalism:** Smaller images are faster to build, transfer, and start. They also have fewer vulnerabilities.
- **Security:** Containers run with minimal privileges. No root, no unnecessary packages, no secrets in images.
- **Verifiability (AAIG L1):** Container images are versioned, scanned, and their provenance is traceable.

## Techniques & Patterns

### Dockerfile Best Practices

#### Multi-Stage Builds
```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Production (only runtime, no build tools)
FROM node:20-alpine AS production
WORKDIR /app
RUN addgroup -g 1001 appgroup && adduser -u 1001 -G appgroup -s /bin/sh -D appuser
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
USER appuser
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

#### Layer Caching Optimization
```dockerfile
# GOOD: Copy dependency files first (changes rarely), then source code (changes often)
COPY package*.json ./
RUN npm ci                    # This layer is cached if package.json hasn't changed
COPY . .                      # Only this layer rebuilds on code changes

# BAD: Copy everything first -- every code change invalidates npm ci cache
COPY . .
RUN npm ci && npm run build
```

### Base Image Selection

| Image | Size | Use Case |
|-------|------|----------|
| `alpine` | ~5 MB | Minimal Linux (use with care -- musl libc differences) |
| `distroless` (Google) | ~2-20 MB | No shell, no package manager. Maximum security. |
| `slim` variants | 50-80 MB | Debian-slim. Good balance of size and compatibility. |
| `ubuntu` / `debian` | 80-120 MB | Maximum compatibility. Use for complex dependencies. |
| `scratch` | 0 MB | Static binaries only (Go, Rust). Nothing else in the image. |

**Recommendation:** Use `*-alpine` or `*-slim` for most workloads. Use `distroless` for production services needing maximum security. Use `scratch` for statically compiled binaries.

### Security Hardening

```dockerfile
# 1. Run as non-root
RUN addgroup -g 1001 app && adduser -u 1001 -G app -s /bin/sh -D app
USER app

# 2. No secrets in image (use runtime injection)
# BAD:  ENV API_KEY=sk-secret123
# GOOD: Pass via docker run -e API_KEY=... or Kubernetes Secrets

# 3. Pin base image versions
# BAD:  FROM node:latest
# GOOD: FROM node:20.11.1-alpine3.19@sha256:abc123...

# 4. Minimize installed packages
RUN apk add --no-cache curl  # --no-cache = no apk cache stored in image

# 5. Read-only filesystem (at runtime)
# docker run --read-only --tmpfs /tmp myapp
```

### Image Scanning

| Tool | Type | Integration |
|------|------|-------------|
| **Trivy** | Open-source, comprehensive | CLI, CI, Kubernetes |
| **Snyk Container** | Commercial, detailed remediation | CLI, CI, registry |
| **Docker Scout** | Docker-native | Docker Desktop, Docker Hub |
| **Grype** | Open-source, Anchore | CLI, CI |

**CI integration:** Scan every built image before pushing to registry. Fail on critical/high CVEs.

### Container Orchestration

| Tool | Scale | Use Case |
|------|-------|----------|
| **Docker Compose** | Single host, dev/test | Local development, small deployments |
| **Kubernetes** | Multi-host, production | Production-grade orchestration |
| **ECS / Cloud Run** | Managed | Serverless containers, less ops overhead |
| **Nomad** | Multi-host | Simpler alternative to Kubernetes |

### Docker Compose for Development

```yaml
# docker-compose.yml
services:
  app:
    build: .
    ports: ["3000:3000"]
    volumes: ["./src:/app/src"]    # Hot reload in dev
    environment:
      DATABASE_URL: postgres://user:pass@db:5432/mydb
    depends_on:
      db: { condition: service_healthy }

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    volumes: ["pgdata:/var/lib/postgresql/data"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
```

### .dockerignore

```
node_modules
.git
.env
*.md
Dockerfile
docker-compose.yml
.github
coverage
dist
```

Always include `.dockerignore` to exclude unnecessary files from build context.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Image scan** | 0 critical CVEs | Block push on critical. High with remediation plan. |
| **Non-root user** | Always | No container runs as root in production. |
| **Image size** | < 200 MB (app) | Monitor and optimize. |
| **Build time** | < 5 min | Use multi-stage, caching, minimal layers. |
| **Pinned base images** | 100% | All base images pinned to specific version + digest. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **FROM latest** | Builds are non-reproducible. Breaks without warning. | Pin exact version: `node:20.11.1-alpine3.19`. |
| **Root user** | Container compromise = host compromise risk. | `USER nonroot` in Dockerfile. |
| **Secrets in image** | Secrets visible in image layers forever. | Inject at runtime via env vars or secrets manager. |
| **Fat images** | 2 GB images with build tools, source, and dev deps. | Multi-stage builds. Copy only production artifacts. |
| **No .dockerignore** | `.git`, `node_modules` copied into build context. Slow, large. | Always include `.dockerignore`. |


## See Also

- [CI/CD](../devops/ci_cd.md)
- [Infrastructure as Code](../devops/infrastructure_as_code.md)
- [Monitoring and Observability](../devops/monitoring_observability.md)

## References

- Docker best practices: https://docs.docker.com/build/building/best-practices/
- Google Distroless: https://github.com/GoogleContainerTools/distroless
- Trivy: https://aquasecurity.github.io/trivy/
- Hadolint (Dockerfile linter): https://github.com/hadolint/hadolint
