# Deja Groove Infrastructure (Dev Bootstrap)

This repository currently implements infrastructure in Azure using Bicep, with dev validation and deploy workflows wired today.

## Scope

- Dev region: `swedencentral`
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
- App Service remains the runtime platform behind APIM.
- App Service uses inbound access restrictions with default deny.
- App Service allows `ApiManagement` service-tag ingress and denies all other direct internet ingress.
- SCM/Kudu restrictions are managed separately and default to deny.
- `GET /health` is the shared backend and platform probe endpoint.
- PostgreSQL and Key Vault are private-only (`publicNetworkAccess: Disabled`) and reachable through private networking.

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
    ├── check-apim-policy.sh        # static APIM policy sanity checks
    ├── validate.sh                 # dev validate + optional what-if
    └── deploy.sh                   # dev deploy
```

## Required Secrets/Vars

For CI/CD and local script execution:

- `AZURE_POSTGRES_ADMIN_LOGIN`
- `AZURE_POSTGRES_ADMIN_PASSWORD`
- `AZURE_POSTGRES_APP_PASSWORD`

For GitHub OIDC login:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

## Pipeline Behavior

- `infrastructure-validate.yaml`: PR-time APIM policy sanity check + Bicep build + `az deployment sub validate` + `what-if`
- `infrastructure-deploy-dev.yaml`: push-to-main APIM policy sanity check + deploy for dev using `az deployment sub create`

## Local Usage

```bash
# Validate dev
./infrastructure/scripts/validate.sh dev

# Validate + what-if
./infrastructure/scripts/validate.sh dev --what-if

# Deploy dev
./infrastructure/scripts/deploy.sh dev
```
