---
"deja-groove": minor
---

Implement production-ready Docker Hub backend delivery for Azure App Service and iPhone integration:

- Add backend API Dockerfile and dockerignore.
- Add pinned GitHub Actions workflow to build/push backend image to Docker Hub with promotion tags (`dev|staging|prod-latest`).
- Add Trivy vulnerability scan gate (HIGH/CRITICAL) in publish pipeline.
- Wire dev infrastructure deploy workflow to require and validate `DOCKER_IMAGE_REFERENCE`, verify image existence before deployment, and pass `dockerImageReference` into Bicep deployment.
- Replace dev placeholder image (`nginx:latest`) with Docker Hub backend image reference.
- Add readiness and workflow contract tests for backend container delivery and Dockerfile invariants.
- Document container image promotion and retention policy, and iOS/APIM endpoint guidance for real-device testing.
