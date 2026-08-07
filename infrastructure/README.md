# Deja Groove Minimal Infrastructure

The legacy .NET backend, APIM, App Service container, PostgreSQL, Key Vault,
and VNet infrastructure has been retired from the active repository.

The active target is a minimum-cost Azure Function recognition proxy. Key Vault
holds the project OpenAI API key, and the Function reads it via a Key Vault
reference. The Function performs only OpenAI album recognition. The iOS app owns collection state, scan state, duplicate
detection, and local persistence.

## Scope

- Dev region: `swedencentral`
- Deployment scope: subscription
- Active runtime target: Azure Function App
- Secret store: Azure Key Vault with RBAC authorization
- Azure resource access: Function system-assigned managed identity
- Required secret: `OPENAI_KEY`
- `POST /v1/scan` requires an Azure Functions key; `GET /health` is anonymous.
- Out of scope: hosted collection API, PostgreSQL, APIM, App Service
  containers, container registry, Entra-backed API auth, and private network
  topology.

## Directory

```
infrastructure/
├── bicep/
│   ├── minimal-function.bicep      # subscription-scope RG bootstrap
│   ├── recognition-function.bicep  # Function resources in the recognition RG
│   └── parameters/
│       └── dev.bicepparam
└── scripts/
    ├── package-function.sh         # builds and zips the Function app
    ├── validate.sh                 # minimal Function lint/validate/what-if
    └── deploy.sh                   # dev infra deploy + Function publish
```

Dev resources are created in `rg-deja-groove-dev-recognition`, keeping the
recognition proxy isolated from any future platform or app concerns.

## Required Secrets/Vars

For GitHub OIDC login:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

For Function App configuration:

- `OPENAI_KEY` (pipeline secret, written into Key Vault during deployment)

Managed identity and RBAC:

- Function identity reads `openai-key` from Key Vault via `Key Vault Secrets User`.
- Function identity accesses host/deployment storage via Storage Blob Data Owner, Storage Queue Data Contributor, and Storage Table Data Contributor.
- Storage shared key access is disabled; Function storage uses identity-based settings.

For scan calls after deployment:

- Use an Azure Functions key through the `x-functions-key` header.

## Pipeline Behavior

- `infrastructure-validate.yaml`: PR-time minimal Function lint/validate/what-if,
  runs when `minimal-function.bicep` exists.
- `infrastructure-deploy-dev.yaml`: push-to-main and manual dev deployment
  using `infrastructure/scripts/deploy.sh dev`; deploys infrastructure and publishes Function code after validation.

## Local Usage

```bash
# Validate dev
./infrastructure/scripts/validate.sh dev

# Validate + what-if
./infrastructure/scripts/validate.sh dev --what-if

# Deploy dev infrastructure and Function code
./infrastructure/scripts/deploy.sh dev
```
