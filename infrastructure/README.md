# Deja Groove Minimal Infrastructure

The legacy .NET backend, APIM, App Service container, PostgreSQL, Key Vault,
and VNet infrastructure has been retired from the active repository.

The active target is a minimum-cost Azure Function recognition proxy. The
Function holds the project OpenAI API key and performs only OpenAI album
recognition. The iOS app owns collection state, scan state, duplicate
detection, and local persistence.

## Scope

- Dev region: `swedencentral`
- Deployment scope: subscription
- Active runtime target: Azure Function App
- Required secret: `OPENAI_KEY`
- Out of scope: hosted collection API, PostgreSQL, APIM, App Service
  containers, container registry, Entra-backed API auth, and private network
  topology.

## Directory

```
infrastructure/
└── scripts/
    ├── validate.sh                 # minimal Function lint/validate/what-if
    └── deploy.sh                   # minimal Function dev deploy
```

`infrastructure/bicep/minimal-function.bicep` will be added under issue #169.
Until that file exists, validation skips cleanly and deployment fails fast.

## Required Secrets/Vars

For GitHub OIDC login:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

For Function App configuration:

- `OPENAI_KEY`

## Pipeline Behavior

- `infrastructure-validate.yaml`: PR-time minimal Function lint/validate/what-if,
  skipped until `minimal-function.bicep` exists.
- `infrastructure-deploy-dev.yaml`: push-to-main and manual dev deployment
  using `infrastructure/scripts/deploy.sh dev`.

## Local Usage

```bash
# Validate dev
./infrastructure/scripts/validate.sh dev

# Validate + what-if
./infrastructure/scripts/validate.sh dev --what-if

# Deploy dev
./infrastructure/scripts/deploy.sh dev
```
