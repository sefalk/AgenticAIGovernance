---
name: containerization
description: Package applications into portable, reproducible containers — Dockerfile best practices, multi-stage builds, security hardening, image scanning, and orchestration.
argument-hint: '[application or service] [focus: dockerfile|security|compose|scanning]'
---

# Containerization

## When to Use

- When building Docker images for applications
- When optimizing container builds (size, speed, caching)
- When hardening containers for production security
- When setting up local development with Docker Compose

## Principles

1. **Reproducibility** — The same image produces identical behavior
   everywhere: dev, CI, staging, production.
2. **Minimalism** — Smaller images build faster, transfer faster, and
   have fewer vulnerabilities.
3. **Security** — Containers run with minimal privileges. No root, no
   unnecessary packages, no secrets in images.
4. **Verifiability** — Images are versioned, scanned, and their provenance
   is traceable.

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

# Stage 2: Production
FROM node:20-alpine AS production
WORKDIR /app
RUN addgroup -g 1001 app && adduser -u 1001 -G app -s /bin/sh -D app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
USER app
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

#### Layer Caching
```dockerfile
# GOOD: Copy deps first (rarely change), then source (often changes)
COPY package*.json ./
RUN npm ci
COPY . .

# BAD: Copy everything first → npm ci cache invalidated on every code change
COPY . .
RUN npm ci && npm run build
```

### Base Image Selection

| Image | Size | Use Case |
|-------|------|----------|
| `alpine` | ~5 MB | Minimal Linux (musl libc) |
| `distroless` | ~2–20 MB | No shell, no pkg manager. Maximum security. |
| `*-slim` | 50–80 MB | Good balance of size and compatibility |
| `scratch` | 0 MB | Static binaries only (Go, Rust) |

### Security Hardening

```dockerfile
# Non-root user
RUN addgroup -g 1001 app && adduser -u 1001 -G app -s /bin/sh -D app
USER app

# Pin base image versions (never FROM latest)
FROM node:20.11.1-alpine3.19@sha256:abc123...

# No secrets in image — inject at runtime
# Minimal packages
RUN apk add --no-cache curl
```

### Image Scanning

| Tool | Integration |
|------|-------------|
| **Trivy** | CLI, CI, Kubernetes |
| **Snyk Container** | CLI, CI, registry |
| **Docker Scout** | Docker Desktop, Docker Hub |
| **Grype** | CLI, CI |

Scan every image before pushing. Fail on critical/high CVEs.

### Docker Compose for Development

```yaml
services:
  app:
    build: .
    ports: ["3000:3000"]
    volumes: ["./src:/app/src"]
    depends_on:
      db: { condition: service_healthy }
  db:
    image: postgres:16-alpine
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user"]
      interval: 5s
```

### .dockerignore

Always include to exclude `.git`, `node_modules`, `.env`, etc. from build
context.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Image scan** | 0 critical CVEs | Block push on critical |
| **Non-root user** | Always | No root in production |
| **Image size** | < 200 MB (app) | Monitor and optimize |
| **Build time** | < 5 min | Multi-stage, caching |
| **Pinned base images** | 100% | Version + digest |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **FROM latest** | Non-reproducible builds. | Pin exact version. |
| **Root user** | Container compromise = host risk. | `USER nonroot`. |
| **Secrets in image** | Visible in layers forever. | Inject at runtime. |
| **Fat images** | 2 GB with build tools and dev deps. | Multi-stage builds. |
| **No .dockerignore** | `.git` and `node_modules` in build context. | Always include. |

## References

- Docker best practices: https://docs.docker.com/build/building/best-practices/
- Google Distroless: https://github.com/GoogleContainerTools/distroless
- Trivy: https://aquasecurity.github.io/trivy/
- Hadolint: https://github.com/hadolint/hadolint
