# Container Image Policy

## Registry

- Registry: Docker Hub
- Repository: `DOCKERHUB_USERNAME/deja-groove-api`

## Tag Strategy

- Immutable build tag: `sha-<short-sha>`
- Channel promotion tag: `<channel>-latest` where channel is `dev`, `staging`, or `prod`

`dev-latest` is published on push to `main`.
`staging-latest` and `prod-latest` are published via workflow dispatch using input `release_channel`.

## Vulnerability Gate

`backend-container-publish.yml` runs Trivy scan and fails publication when HIGH or CRITICAL vulnerabilities are detected.

## Retention

- Keep channel tags (`dev-latest`, `staging-latest`, `prod-latest`) as moving pointers.
- Keep at least the latest 30 immutable `sha-*` tags for rollback.
- Remove older `sha-*` tags during scheduled registry hygiene.

## Deploy Contract

- Azure deploy uses `DOCKER_IMAGE_REFERENCE` with required format `<namespace>/<image>:<tag>`.
- Deployment fails fast if the image reference is missing or not found in registry.
