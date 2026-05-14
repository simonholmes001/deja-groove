# Deja Groove Infrastructure (Dev Bootstrap)

This repository currently implements **dev-only** infrastructure in Azure using Bicep.

## Scope

- Environment: `dev` only
- Region: `swedencentral` only
- Deployment scope: **subscription** (creates resource groups + deploys resources)

## Dev Resource Group Layout

The subscription-scope template creates and manages these RGs:

- `rg-deja-dev-network` (VNet, subnets, NSGs, private DNS zones)
- `rg-deja-dev-data` (PostgreSQL Flexible Server)
- `rg-deja-dev-security` (Key Vault + private endpoint)
- `rg-deja-dev-app` (App Service + APIM)
- `rg-deja-dev-observability` (Log Analytics + Application Insights)

## Ingress Posture

- APIM is the intended public ingress tier.
- App Service uses inbound access restrictions with default deny and only allows the `ApiManagement` service tag.
- SCM/Kudu restrictions are managed separately and default to deny.
- PostgreSQL and Key Vault are private-only (`publicNetworkAccess: Disabled`) and reachable through private networking.

## Break-Glass Access (Dev)

- Manual workflow: `.github/workflows/appservice-breakglass-access.yaml`
- Purpose: temporary allow/remove emergency CIDR access to App Service main and SCM endpoints.
- Use only for incident recovery and remove rule immediately after use.

## Directory

```
infrastructure/
├── bicep/
│   ├── main.bicep                  # Subscription-scope orchestrator
│   ├── modules/
│   │   ├── monitoring/
│   │   ├── networking/
│   │   ├── key-vault/
│   │   ├── postgresql/
│   │   ├── app-service/
│   │   └── apim/
│   └── parameters/
│       └── dev.bicepparam
└── scripts/
    ├── validate.sh                 # dev validate + optional what-if
    └── deploy.sh                   # dev deploy
```

## Required Secrets/Vars

For CI/CD and local script execution:

- `AZURE_POSTGRES_ADMIN_LOGIN`
- `AZURE_POSTGRES_ADMIN_PASSWORD`

For GitHub OIDC login:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

## Pipeline Behavior

- `infrastructure-validate.yaml`: PR-time Bicep build + `az deployment sub validate` + `what-if`
- `infrastructure-deploy-dev.yaml`: push-to-main deploy for dev using `az deployment sub create`
- `appservice-breakglass-access.yaml`: manual emergency access control for App Service

## Local Usage

```bash
# Validate dev
./infrastructure/scripts/validate.sh dev

# Validate + what-if
./infrastructure/scripts/validate.sh dev --what-if

# Deploy dev
./infrastructure/scripts/deploy.sh dev
```
