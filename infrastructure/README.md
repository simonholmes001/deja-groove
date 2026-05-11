# Déjà Groove — Infrastructure

Bicep IaC for the Déjà Groove Azure platform. All environments (dev / staging / prod) are provisioned from the same module set using per-environment parameter files.

---

## Directory structure

```
infrastructure/
├── bicep/
│   ├── main.bicep              # Orchestration entry point (resource-group scope)
│   ├── modules/
│   │   ├── monitoring/         # Log Analytics workspace + Application Insights
│   │   ├── networking/         # VNet, subnets, NSGs, private DNS zones
│   │   ├── key-vault/          # Key Vault + private endpoint
│   │   ├── postgresql/         # PostgreSQL Flexible Server (VNet integration)
│   │   ├── container-apps/     # Container Apps environment + Container App + managed identity
│   │   └── apim/               # API Management (Consumption tier)
│   └── parameters/
│       ├── dev.bicepparam
│       ├── staging.bicepparam
│       └── prod.bicepparam
└── scripts/
    ├── deploy.sh               # Deploy to a target environment
    └── validate.sh             # Lint, validate, and what-if without deploying
```

---

## Module boundaries

Each module owns one bounded concern and exposes a typed interface (params → outputs). No module imports types from another module directly; cross-module wiring happens in `main.bicep` only.

| Module | Owns | Key outputs |
|---|---|---|
| `monitoring` | Log Analytics workspace, App Insights component | `logAnalyticsWorkspaceId`, `appInsightsConnectionString` |
| `networking` | VNet, subnets, NSGs, private DNS zones, VNet-DNS links | `containerAppsSubnetId`, `privateEndpointSubnetId`, `postgresSubnetId` |
| `key-vault` | Key Vault, private endpoint, DNS zone group | `keyVaultUri`, `keyVaultId` |
| `postgresql` | PostgreSQL Flexible Server, VNet integration, admin credentials reference | `postgresqlFqdn` |
| `container-apps` | ACA environment, Container App, user-assigned managed identity | `containerAppFqdn`, `containerAppPrincipalId` |
| `apim` | APIM Consumption instance, logger | `apimGatewayUrl` |

Deployment order enforced by `main.bicep` dependency graph:
```
monitoring ─┐
networking  ─┼─► key-vault ─┐
             └─► postgresql  ┤
                             ├─► container-apps ─► apim
                             └───────────────────────►
```

---

## Naming conventions

Follows [Azure Cloud Adoption Framework abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations). Pattern: `{abbrev}-deja-{env}[-{suffix}]`

Globally unique resources (Key Vault, APIM, PostgreSQL) append a 6-character suffix derived from `uniqueString(resourceGroup().id)` to avoid name collisions across subscriptions.

| Resource type | Abbreviation | Pattern | Example (prod) |
|---|---|---|---|
| Resource Group | `rg` | `rg-deja-{env}` | `rg-deja-prod` |
| Log Analytics Workspace | `log` | `log-deja-{env}` | `log-deja-prod` |
| Application Insights | `appi` | `appi-deja-{env}` | `appi-deja-prod` |
| Virtual Network | `vnet` | `vnet-deja-{env}` | `vnet-deja-prod` |
| Network Security Group | `nsg` | `nsg-{subnet}-deja-{env}` | `nsg-aca-deja-prod` |
| Container Apps Environment | `cae` | `cae-deja-{env}` | `cae-deja-prod` |
| Container App | `ca` | `ca-deja-api-{env}` | `ca-deja-api-prod` |
| User-Assigned Managed Identity | `id` | `id-deja-api-{env}` | `id-deja-api-prod` |
| PostgreSQL Flexible Server | `psql` | `psql-deja-{env}-{suffix}` | `psql-deja-prod-a1b2c3` |
| Key Vault | `kv` | `kv-deja-{env}-{suffix}` | `kv-deja-prod-a1b2c3` |
| API Management | `apim` | `apim-deja-{env}-{suffix}` | `apim-deja-prod-a1b2c3` |
| Private Endpoint | `pe` | `pe-{resource}-deja-{env}` | `pe-kv-deja-prod` |
| Private DNS Zone | (standard) | `privatelink.{service}` | `privatelink.vaultcore.azure.net` |

---

## Mandatory resource tags

All resources carry these tags, enforced as parameters in every module. Policy-as-code (`Deny` effect) is applied at the subscription level in the platform subscription.

| Tag | Values | Purpose |
|---|---|---|
| `environment` | `dev` \| `staging` \| `prod` | Cost attribution, alert scoping |
| `application` | `deja-groove` | Portfolio grouping |
| `owner` | owner email | Incident escalation |
| `cost-centre` | `deja-groove-v1` | Budget alert binding |

---

## State strategy

Bicep uses Azure Resource Manager as the implicit state backend — there is no local state file. Deployment history is tracked natively in each resource group.

- Each environment deploys into its own resource group (`rg-deja-{env}`).
- Resource groups are created once manually (or via a bootstrap script) before first deployment; they are not managed inside `main.bicep` to avoid accidental deletion.
- Deployment names follow `deja-{module}-{env}-{timestamp}` for auditable history.
- `--mode Incremental` is always used; complete mode is never used to prevent accidental resource deletion.

---

## CIDR address plan

| Segment | Prod CIDR | Nonprod CIDR | Notes |
|---|---|---|---|
| VNet | `10.1.0.0/22` | `10.2.0.0/22` | 1022 usable hosts |
| Container Apps subnet | `10.1.0.0/23` | `10.2.0.0/23` | Minimum /23 required by ACA |
| Private endpoint subnet | `10.1.2.0/27` | `10.2.2.0/27` | Key Vault PE |
| PostgreSQL subnet | `10.1.2.32/27` | `10.2.2.32/27` | Delegated to `Microsoft.DBforPostgreSQL/flexibleServers` |

---

## Environment promotion path

| Environment | Trigger | Approval | Replicas | Notes |
|---|---|---|---|---|
| `dev` | Merge to `main` | None — automatic | Scale to 0 allowed | Integration testing |
| `staging` | Git tag `v*-rc*` | None — automatic after what-if | Min 1 replica | Mirrors prod topology |
| `prod` | Git tag `v*` | Manual approval required | Min 1 replica | What-if review before apply |

Pipeline steps (implemented in issue #10):
1. `bicep lint` — static analysis
2. `az deployment group validate` — ARM template validation
3. `az deployment group what-if` — preview resource changes
4. Manual approval gate (staging: optional, prod: required)
5. `az deployment group create --mode Incremental` — apply

---

## Prerequisites

```bash
az --version          # Azure CLI 2.50+
az bicep version      # Bicep CLI (installed via az bicep install)
az login
az account set --subscription <subscription-id>
```

---

## Quick start

```bash
# Validate without deploying
./infrastructure/scripts/validate.sh dev

# Deploy to dev
./infrastructure/scripts/deploy.sh dev

# What-if for prod (review before applying)
./infrastructure/scripts/validate.sh prod --what-if
```
