#!/usr/bin/env bash
#
# ============================================================================
#  Backstage.io — AZURE / AKS PRODUCTION-STYLE SETUP
# ============================================================================
#  Assumptions:
#    - You already have an AKS cluster (set AKS_CLUSTER / AKS_RESOURCE_GROUP)
#    - You already have (or this script creates) an Azure Container Registry
#      attached to that AKS cluster
#    - Ingress into AKS goes through Azure Application Gateway (AGIC) and/or
#      is fronted by Azure APIM — this script wires the K8s side; APIM front-
#      door configuration is a separate one-time portal/CLI step documented
#      in the accompanying guide (APIM policies vary too much per org to
#      safely script blindly).
#    - Auth: Microsoft Entra ID (Azure AD) app registration for SSO.
#
#  IMPORTANT DB NOTE:
#    Backstage's own catalog database ONLY supports PostgreSQL (or SQLite).
#    It does NOT support MongoDB/Cosmos DB (Mongo API) as its backend.
#    This script provisions Azure Database for PostgreSQL Flexible Server
#    for Backstage itself. Your existing Cosmos Mongo DB stays exactly
#    where it is — it can be referenced by Backstage as an external
#    resource entity (documentation only) or read from a custom plugin,
#    but it cannot replace Postgres for the core catalog.
#
#  Usage:
#    export AZ_SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#    export RESOURCE_GROUP="rg-backstage"
#    export LOCATION="eastus"
#    export ACR_NAME="acrbackstageshared"          # must be globally unique
#    export AKS_CLUSTER="my-existing-aks"
#    export AKS_RESOURCE_GROUP="rg-aks"
#    export PG_SERVER_NAME="psql-backstage"        # must be globally unique
#    export PG_ADMIN_USER="backstageadmin"
#    export GITHUB_TOKEN="ghp_xxx"
#    export AAD_CLIENT_ID="xxxx"                   # from your app registration
#    export AAD_CLIENT_SECRET="xxxx"
#    export AAD_TENANT_ID="xxxx"
#
#    chmod +x 02-azure-aks-setup.sh
#    ./02-azure-aks-setup.sh
# ============================================================================

set -euo pipefail

log()  { echo -e "\033[1;36m[azure-setup]\033[0m $1"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $1"; }
err()  { echo -e "\033[1;31m[error]\033[0m $1"; }
require_var() { if [ -z "${!1:-}" ]; then err "Required env var '$1' is not set."; exit 1; fi; }

# ----------------------------------------------------------------------------
# 0. Validate inputs & tools
# ----------------------------------------------------------------------------
for v in AZ_SUBSCRIPTION_ID RESOURCE_GROUP LOCATION ACR_NAME AKS_CLUSTER AKS_RESOURCE_GROUP \
         PG_SERVER_NAME PG_ADMIN_USER GITHUB_TOKEN; do
  require_var "$v"
done

for cmd in az kubectl docker; do
  command -v "$cmd" >/dev/null 2>&1 || { err "$cmd is required but not installed."; exit 1; }
done

NAMESPACE="backstage"
PG_DB_NAME="backstage"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-$(openssl rand -base64 24)}"
BACKEND_SECRET="${BACKEND_SECRET:-$(openssl rand -hex 32)}"
IMAGE_NAME="backstage"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d%H%M%S)}"

log "Logging into Azure (device code if not already logged in)..."
az account show >/dev/null 2>&1 || az login
az account set --subscription "$AZ_SUBSCRIPTION_ID"

# ----------------------------------------------------------------------------
# 1. Resource group (idempotent)
# ----------------------------------------------------------------------------
log "Ensuring resource group '$RESOURCE_GROUP' exists..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null

# ----------------------------------------------------------------------------
# 2. Azure Container Registry (idempotent) + attach to AKS
# ----------------------------------------------------------------------------
if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  log "Creating ACR '$ACR_NAME'..."
  az acr create --resource-group "$RESOURCE_GROUP" --name "$ACR_NAME" --sku Standard >/dev/null
else
  log "ACR '$ACR_NAME' already exists."
fi

log "Attaching ACR to existing AKS cluster '$AKS_CLUSTER' (grants AcrPull)..."
az aks update \
  --name "$AKS_CLUSTER" \
  --resource-group "$AKS_RESOURCE_GROUP" \
  --attach-acr "$ACR_NAME" >/dev/null

# ----------------------------------------------------------------------------
# 3. Azure Database for PostgreSQL Flexible Server (the Backstage catalog DB)
# ----------------------------------------------------------------------------
if ! az postgres flexible-server show --name "$PG_SERVER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  log "Creating Postgres Flexible Server '$PG_SERVER_NAME' (this takes several minutes)..."
  az postgres flexible-server create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PG_SERVER_NAME" \
    --location "$LOCATION" \
    --admin-user "$PG_ADMIN_USER" \
    --admin-password "$PG_ADMIN_PASSWORD" \
    --sku-name Standard_B2s \
    --tier Burstable \
    --storage-size 32 \
    --version 16 \
    --public-access 0.0.0.0-255.255.255.255 \
    --yes >/dev/null
  # NOTE: --public-access above is broad for demo speed. In production,
  # use --vnet / --subnet to place it on AKS's private network instead,
  # and remove public access entirely.
else
  log "Postgres server '$PG_SERVER_NAME' already exists."
fi

log "Ensuring database '$PG_DB_NAME' exists on the server..."
az postgres flexible-server db create \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$PG_SERVER_NAME" \
  --database-name "$PG_DB_NAME" >/dev/null 2>&1 || true

PG_HOST=$(az postgres flexible-server show \
  --name "$PG_SERVER_NAME" --resource-group "$RESOURCE_GROUP" \
  --query "fullyQualifiedDomainName" -o tsv)

# ----------------------------------------------------------------------------
# 4. Build & push the Backstage backend image to ACR
#    (assumes you run this script from inside your Backstage app repo,
#     i.e. the folder created by 01-local-mac-setup.sh / create-app)
# ----------------------------------------------------------------------------
if [ ! -f "package.json" ] || [ ! -d "packages/backend" ]; then
  err "This doesn't look like a Backstage app root (no packages/backend)."
  err "cd into your Backstage app directory before running this script."
  exit 1
fi

if [ ! -f "packages/backend/Dockerfile" ]; then
  warn "No Dockerfile found at packages/backend/Dockerfile — writing the standard Backstage one."
  mkdir -p packages/backend
  cat > packages/backend/Dockerfile <<'EOF'
FROM node:20-bookworm-slim AS build
WORKDIR /app
COPY . .
RUN yarn install --immutable
RUN yarn tsc
RUN yarn build:backend --config app-config.yaml --config app-config.production.yaml

FROM node:20-bookworm-slim
WORKDIR /app
COPY --from=build /app/packages/backend/dist/bundle.tar.gz .
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz
COPY --from=build /app/app-config.yaml ./
COPY --from=build /app/app-config.production.yaml ./
ENV NODE_ENV=production
CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
EOF
fi

log "Logging Docker into ACR..."
az acr login --name "$ACR_NAME"

FULL_IMAGE="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
log "Building image ${FULL_IMAGE} (build context: repo root, using packages/backend/Dockerfile)..."
docker build -f packages/backend/Dockerfile -t "$FULL_IMAGE" .

log "Pushing image to ACR..."
docker push "$FULL_IMAGE"

# ----------------------------------------------------------------------------
# 5. Connect kubectl to the AKS cluster
# ----------------------------------------------------------------------------
log "Fetching AKS credentials..."
az aks get-credentials --resource-group "$AKS_RESOURCE_GROUP" --name "$AKS_CLUSTER" --overwrite-existing

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ----------------------------------------------------------------------------
# 6. Create/refresh the K8s secret with DB + GitHub + Entra ID + backend secret
# ----------------------------------------------------------------------------
log "Creating Kubernetes secret 'backstage-secrets' in namespace '$NAMESPACE'..."
kubectl -n "$NAMESPACE" create secret generic backstage-secrets \
  --from-literal=POSTGRES_HOST="$PG_HOST" \
  --from-literal=POSTGRES_PORT="5432" \
  --from-literal=POSTGRES_USER="$PG_ADMIN_USER" \
  --from-literal=POSTGRES_PASSWORD="$PG_ADMIN_PASSWORD" \
  --from-literal=GITHUB_TOKEN="$GITHUB_TOKEN" \
  --from-literal=AAD_CLIENT_ID="${AAD_CLIENT_ID:-}" \
  --from-literal=AAD_CLIENT_SECRET="${AAD_CLIENT_SECRET:-}" \
  --from-literal=AAD_TENANT_ID="${AAD_TENANT_ID:-}" \
  --from-literal=BACKEND_SECRET="$BACKEND_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

# ----------------------------------------------------------------------------
# 7. Apply K8s manifests (deployment, service, ingress)
#    See 03-k8s-manifests.yaml — this substitutes the image tag and applies it.
# ----------------------------------------------------------------------------
if [ -f "../03-k8s-manifests.yaml" ]; then
  MANIFEST_PATH="../03-k8s-manifests.yaml"
elif [ -f "03-k8s-manifests.yaml" ]; then
  MANIFEST_PATH="03-k8s-manifests.yaml"
else
  err "03-k8s-manifests.yaml not found alongside this script. Download it from the same delivery and re-run."
  exit 1
fi

log "Applying Kubernetes manifests from ${MANIFEST_PATH}..."
sed "s|__IMAGE__|${FULL_IMAGE}|g" "$MANIFEST_PATH" | kubectl apply -n "$NAMESPACE" -f -

# ----------------------------------------------------------------------------
# 8. Wait for rollout & report
# ----------------------------------------------------------------------------
log "Waiting for deployment rollout..."
kubectl -n "$NAMESPACE" rollout status deployment/backstage --timeout=300s

echo ""
log "Done. Summary:"
echo "  Image pushed      : ${FULL_IMAGE}"
echo "  Postgres server    : ${PG_HOST}"
echo "  Namespace          : ${NAMESPACE}"
echo "  Ingress host       : check 'kubectl -n ${NAMESPACE} get ingress' (fronted by App Gateway/AGIC)"
echo "  Next               : point Azure APIM at the Application Gateway backend / ingress hostname"
echo "                        (see 02-azure-aks-setup-GUIDE.md, section 'APIM + App Gateway')"
