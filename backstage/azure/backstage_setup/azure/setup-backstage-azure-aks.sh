#!/usr/bin/env bash
set -Eeuo pipefail

# Backstage Azure/AKS POC-to-team baseline.
#
# Assumptions:
#   * Azure CLI is installed and already logged in.
#   * An existing AKS cluster is available.
#   * Your organization already has (or will configure) Application Gateway/APIM.
#   * This script creates ACR, Azure Database for PostgreSQL Flexible Server, Blob Storage,
#     a user-assigned managed identity for Workload Identity, and a Backstage namespace.
#
# Important:
#   * Cosmos DB for MongoDB remains an APPLICATION data source. Backstage itself uses PostgreSQL.
#   * For a production deployment, put PostgreSQL behind private networking/Private DNS and
#     prefer Key Vault/Workload Identity over Kubernetes plaintext secrets.
#   * The script deploys a ClusterIP service and an Ingress. Set INGRESS_CLASS to match your
#     existing Application Gateway Ingress Controller / Application Gateway for Containers setup.
#   * APIM can then front the Application Gateway hostname/path according to your enterprise pattern.

: "${AZ_SUBSCRIPTION_ID:?Set AZ_SUBSCRIPTION_ID}"
: "${AZ_RESOURCE_GROUP:?Set AZ_RESOURCE_GROUP}"
: "${AKS_CLUSTER_NAME:?Set AKS_CLUSTER_NAME}"
: "${AZ_LOCATION:?Set AZ_LOCATION}"
: "${BACKSTAGE_HOSTNAME:?Set BACKSTAGE_HOSTNAME, e.g. backstage.example.com}"
: "${GITHUB_ORG:?Set GITHUB_ORG}"

APP_NAME="${APP_NAME:-backstage}"
NAMESPACE="${NAMESPACE:-backstage}"
ACR_NAME="${ACR_NAME:-${AZ_RESOURCE_GROUP//[^a-zA-Z0-9]/}backstageacr}"
ACR_NAME="${ACR_NAME:0:50}"
PG_SERVER="${PG_SERVER:-${APP_NAME}-pg-$RANDOM}"
PG_ADMIN="${PG_ADMIN:-backstageadmin}"
PG_DB="${PG_DB:-backstage}"
PG_PASSWORD="${PG_PASSWORD:-$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 28)}"
STORAGE_NAME="${STORAGE_NAME:-${AZ_RESOURCE_GROUP//[^a-zA-Z0-9]/}bstdocs}"
STORAGE_NAME="${STORAGE_NAME,,}"
STORAGE_NAME="${STORAGE_NAME:0:24}"
TECHDOCS_CONTAINER="${TECHDOCS_CONTAINER:-techdocs}"
IDENTITY_NAME="${IDENTITY_NAME:-backstage-workload}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-backstage}"
INGRESS_CLASS="${INGRESS_CLASS:-azure-application-gateway}"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M%S)}"
BACKSTAGE_REPO="${BACKSTAGE_REPO:-$PWD/$APP_NAME}"

# Set this to true only if you want the script to create an Entra app registration.
# In many enterprises an identity team owns this step.
CONFIGURE_ENTRA="${CONFIGURE_ENTRA:-false}"
ENTRA_APP_NAME="${ENTRA_APP_NAME:-Backstage}"
ENTRA_CLIENT_SECRET="${ENTRA_CLIENT_SECRET:-}"

# Optional existing PostgreSQL. If supplied, the script does not create a server.
# Existing server must be reachable from AKS.
EXISTING_POSTGRES_HOST="${EXISTING_POSTGRES_HOST:-}"

log(){ printf '\n\033[1;36m[Backstage-Azure]\033[0m %s\n' "$*"; }
warn(){ printf '\n\033[1;33mWARNING:\033[0m %s\n' "$*" >&2; }
die(){ printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
trap 'die "Failed at line $LINENO. Review the command above."' ERR

need(){ command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }
need az
need docker
need kubectl
need openssl

az account set --subscription "$AZ_SUBSCRIPTION_ID"
az account show --output table
docker info >/dev/null 2>&1 || die "Docker must be running because this script builds the Backstage image."

log "Ensuring AKS OIDC issuer and Workload Identity are enabled"
az aks update -g "$AZ_RESOURCE_GROUP" -n "$AKS_CLUSTER_NAME" --enable-oidc-issuer --enable-workload-identity >/dev/null

log "Getting AKS credentials"
az aks get-credentials \
  --resource-group "$AZ_RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --overwrite-existing >/dev/null

kubectl version --short 2>/dev/null || kubectl version --client
kubectl get nodes

log "Creating resource group if needed"
az group create -n "$AZ_RESOURCE_GROUP" -l "$AZ_LOCATION" >/dev/null

log "Creating Azure Container Registry"
az acr create \
  --resource-group "$AZ_RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku Standard \
  --admin-enabled false >/dev/null

ACR_LOGIN_SERVER="$(az acr show -g "$AZ_RESOURCE_GROUP" -n "$ACR_NAME" --query loginServer -o tsv)"

log "Granting AKS permission to pull from ACR"
az aks update   --resource-group "$AZ_RESOURCE_GROUP"   --name "$AKS_CLUSTER_NAME"   --attach-acr "$ACR_NAME" >/dev/null

if [ -z "$EXISTING_POSTGRES_HOST" ]; then
  log "Creating Azure Database for PostgreSQL Flexible Server"
  if az postgres flexible-server show -g "$AZ_RESOURCE_GROUP" -n "$PG_SERVER" >/dev/null 2>&1; then
    log "PostgreSQL server already exists: $PG_SERVER"
  else
    az postgres flexible-server create \
      --resource-group "$AZ_RESOURCE_GROUP" \
      --name "$PG_SERVER" \
      --location "$AZ_LOCATION" \
      --admin-user "$PG_ADMIN" \
      --admin-password "$PG_PASSWORD" \
      --sku-name Standard_B1ms \
      --tier Burstable \
      --storage-size 32 \
      --version 18 \
      --public-access 0.0.0.0 >/dev/null
  fi
  POSTGRES_HOST="$(az postgres flexible-server show -g "$AZ_RESOURCE_GROUP" -n "$PG_SERVER" --query fullyQualifiedDomainName -o tsv)"
else
  POSTGRES_HOST="$EXISTING_POSTGRES_HOST"
  warn "Using existing PostgreSQL host: $POSTGRES_HOST"
fi

log "Creating PostgreSQL database"
if [ -z "$EXISTING_POSTGRES_HOST" ]; then
  az postgres flexible-server db create \
    --resource-group "$AZ_RESOURCE_GROUP" \
    --server-name "$PG_SERVER" \
    --database-name "$PG_DB" >/dev/null 2>&1 || true

  # Try to allow the AKS managed outbound public IPs when they are discoverable.
  # This is a POC convenience only. Production should use private access.
  OUTBOUND_IDS="$(az aks show -g "$AZ_RESOURCE_GROUP" -n "$AKS_CLUSTER_NAME" \
    --query 'networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id' -o tsv 2>/dev/null || true)"
  idx=0
  while IFS= read -r pipid; do
    [ -z "$pipid" ] && continue
    pip="$(az network public-ip show --ids "$pipid" --query ipAddress -o tsv 2>/dev/null || true)"
    if [ -n "$pip" ] && [ "$pip" != "null" ]; then
      az postgres flexible-server firewall-rule create \
        -g "$AZ_RESOURCE_GROUP" -n "$PG_SERVER" \
        --rule-name "aks-egress-$idx" \
        --start-ip-address "$pip" --end-ip-address "$pip" >/dev/null 2>&1 || true
      idx=$((idx+1))
    fi
  done <<< "$OUTBOUND_IDS"
  if [ "$idx" -eq 0 ]; then
    warn "Could not discover AKS egress IPs. PostgreSQL connectivity may fail. Prefer private networking for production."
  fi
else
  warn "You are responsible for firewall/private-network connectivity from AKS to existing PostgreSQL."
fi

log "Creating Azure Blob Storage for TechDocs"
if ! az storage account show -g "$AZ_RESOURCE_GROUP" -n "$STORAGE_NAME" >/dev/null 2>&1; then
  az storage account create \
    -g "$AZ_RESOURCE_GROUP" \
    -n "$STORAGE_NAME" \
    -l "$AZ_LOCATION" \
    --sku Standard_ZRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false >/dev/null
fi

STORAGE_ID="$(az storage account show -g "$AZ_RESOURCE_GROUP" -n "$STORAGE_NAME" --query id -o tsv)"
STORAGE_ENDPOINT="$(az storage account show -g "$AZ_RESOURCE_GROUP" -n "$STORAGE_NAME" --query primaryEndpoints.blob -o tsv)"

STORAGE_KEY="$(az storage account keys list -g "$AZ_RESOURCE_GROUP" -n "$STORAGE_NAME" --query '[0].value' -o tsv)"
az storage container create \
  --account-name "$STORAGE_NAME" \
  --account-key "$STORAGE_KEY" \
  --name "$TECHDOCS_CONTAINER" >/dev/null

log "Creating user-assigned identity and federated credential"
az identity create -g "$AZ_RESOURCE_GROUP" -n "$IDENTITY_NAME" -l "$AZ_LOCATION" >/dev/null
IDENTITY_CLIENT_ID="$(az identity show -g "$AZ_RESOURCE_GROUP" -n "$IDENTITY_NAME" --query clientId -o tsv)"
IDENTITY_PRINCIPAL_ID="$(az identity show -g "$AZ_RESOURCE_GROUP" -n "$IDENTITY_NAME" --query principalId -o tsv)"

OIDC_ISSUER="$(az aks show -g "$AZ_RESOURCE_GROUP" -n "$AKS_CLUSTER_NAME" --query oidcIssuerProfile.issuerUrl -o tsv 2>/dev/null || true)"
if [ -z "$OIDC_ISSUER" ] || [ "$OIDC_ISSUER" = "null" ]; then
  warn "AKS OIDC issuer is not enabled. Enable Workload Identity/OIDC on AKS before using the identity."
else
  FED_NAME="backstage-federated"
  az identity federated-credential create \
    --name "$FED_NAME" \
    --identity-name "$IDENTITY_NAME" \
    --resource-group "$AZ_RESOURCE_GROUP" \
    --issuer "$OIDC_ISSUER" \
    --subject "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}" \
    --audience "api://AzureADTokenExchange" >/dev/null 2>&1 || true

  az role assignment create \
    --assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Owner" \
    --scope "$STORAGE_ID" >/dev/null 2>&1 || true
fi

if [ ! -d "$BACKSTAGE_REPO" ]; then
  log "Creating a Backstage source repository locally"
  mkdir -p "$(dirname "$BACKSTAGE_REPO")"
  cd "$(dirname "$BACKSTAGE_REPO")"
  printf '%s\n' "$APP_NAME" | npx @backstage/create-app@latest
fi

cd "$BACKSTAGE_REPO"

log "Installing production dependencies"
corepack enable
corepack prepare yarn@4.4.1 --activate
yarn --cwd packages/backend add pg @backstage/plugin-auth-backend-module-microsoft-provider

# GitHub catalog discovery module.
yarn --cwd packages/backend add @backstage/plugin-catalog-backend-module-github

# Ensure backend module imports exist. New Backstage apps use packages/backend/src/index.ts.
BACKEND_INDEX="packages/backend/src/index.ts"
python3 - "$BACKEND_INDEX" <<'PY'
from pathlib import Path
p=Path(__import__('sys').argv[1])
s=p.read_text()
lines=[
"backend.add(import('@backstage/plugin-auth-backend'));",
"backend.add(import('@backstage/plugin-auth-backend-module-microsoft-provider'));",
"backend.add(import('@backstage/plugin-catalog-backend'));",
"backend.add(import('@backstage/plugin-catalog-backend-module-github'));",
]
for line in lines:
    if line not in s:
        s += "\n" + line + "\n"
p.write_text(s)
PY

# The exact generated index normally already contains the auth/catalog modules. If the
# scaffold contains them, the duplicate-add protection above avoids changing it.

if [ "$CONFIGURE_ENTRA" = "true" ]; then
  log "Creating/configuring Microsoft Entra App Registration"
  REDIRECT_URI="https://${BACKSTAGE_HOSTNAME}/api/auth/microsoft/handler/frame"

  EXISTING_ENTRA_APP_ID="$(az ad app list --display-name "$ENTRA_APP_NAME" --query '[0].appId | [0]' -o tsv 2>/dev/null || true)"
  if [ -z "$EXISTING_ENTRA_APP_ID" ] || [ "$EXISTING_ENTRA_APP_ID" = "None" ]; then
    ENTRA_CLIENT_ID="$(az ad app create       --display-name "$ENTRA_APP_NAME"       --sign-in-audience AzureADMyOrg       --web-redirect-uris "$REDIRECT_URI"       --web-home-page-url "https://${BACKSTAGE_HOSTNAME}"       --query appId -o tsv)"
    az ad sp create --id "$ENTRA_CLIENT_ID" >/dev/null 2>&1 || true
  else
    ENTRA_CLIENT_ID="$EXISTING_ENTRA_APP_ID"
    az ad app update --id "$ENTRA_CLIENT_ID" --web-redirect-uris "$REDIRECT_URI" >/dev/null
  fi

  if [ -z "$ENTRA_CLIENT_SECRET" ]; then
    ENTRA_CLIENT_SECRET="$(az ad app credential reset --id "$ENTRA_CLIENT_ID" --append --years 1 --query password -o tsv)"
  fi

  warn "Entra App Registration created/updated. Verify Microsoft Graph delegated permissions and admin consent according to your tenant policy."
  export ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET
fi

mkdir -p examples
cat > examples/backstage-catalog.yaml <<EOF
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: backstage-platform
  description: Internal Developer Portal running on AKS
  annotations:
    github.com/project-slug: ${GITHUB_ORG}/backstage
    backstage.io/techdocs-ref: dir:.
spec:
  type: service
  lifecycle: production
  owner: platform-team
  system: developer-platform
---
apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: developer-platform
  description: Enterprise developer platform
spec:
  owner: platform-team
---
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: platform-team
  description: Platform Engineering
spec:
  type: team
  profile:
    displayName: Platform Engineering
  children: []
EOF

# Production config. Secrets are supplied as environment variables in Kubernetes.
cat > app-config.production.yaml <<EOF
app:
  baseUrl: https://${BACKSTAGE_HOSTNAME}

backend:
  baseUrl: https://${BACKSTAGE_HOSTNAME}
  listen:
    host: 0.0.0.0
    port: 7007
  cors:
    origin: https://${BACKSTAGE_HOSTNAME}
  database:
    client: pg
    connection:
      host: \${POSTGRES_HOST}
      port: 5432
      user: \${POSTGRES_USER}
      password: \${POSTGRES_PASSWORD}
      database: \${POSTGRES_DB}
      ssl:
        rejectUnauthorized: false

auth:
  environment: production
  providers:
    microsoft:
      production:
        clientId: \${AZURE_CLIENT_ID}
        clientSecret: \${AZURE_CLIENT_SECRET}
        tenantId: \${AZURE_TENANT_ID}
        domainHint: \${AZURE_TENANT_ID}
        signIn:
          resolvers:
            - resolver: emailMatchingUserEntityProfileEmail

integrations:
  github:
    - host: github.com
      token: \${GITHUB_TOKEN}

catalog:
  locations:
    - type: file
      target: ./examples/backstage-catalog.yaml

techdocs:
  builder: external
  publisher:
    type: azureBlobStorage
    azureBlobStorage:
      containerName: ${TECHDOCS_CONTAINER}
      credentials:
        accountName: ${STORAGE_NAME}
EOF

# Make the generated app present Microsoft as the sign-in provider.
# This is deliberately conservative: if the scaffold already has a custom App.tsx,
# the script creates a patch file instead of guessing at arbitrary source structure.
cat > AZURE-ENTRA-FRONTEND-SNIPPET.tsx <<'EOF'
// Add these imports to packages/app/src/App.tsx:
//
// import { microsoftAuthApiRef } from '@backstage/core-plugin-api';
// import { SignInPage } from '@backstage/core-components';
//
// Then configure createApp with:
//
// components: {
//   SignInPage: props => (
//     <SignInPage
//       {...props}
//       auto
//       provider={{
//         id: 'microsoft-auth-provider',
//         title: 'Microsoft',
//         message: 'Sign in using Microsoft',
//         apiRef: microsoftAuthApiRef,
//       }}
//     />
//   ),
// },
EOF

# If the generated app uses the legacy createApp/components shape, patch automatically.
python3 <<'PY'
from pathlib import Path
p=Path("packages/app/src/App.tsx")
if p.exists():
    s=p.read_text()
    if "microsoftAuthApiRef" not in s:
        marker="import {"
        # Put imports after existing imports by prepending; valid TS/TSX.
        s = "import { microsoftAuthApiRef } from '@backstage/core-plugin-api';\nimport { SignInPage } from '@backstage/core-components';\n" + s
        if "const app = createApp({" in s and "components:" not in s:
            s=s.replace("const app = createApp({", """const app = createApp({
  components: {
    SignInPage: props => (
      <SignInPage
        {...props}
        auto
        provider={{
          id: 'microsoft-auth-provider',
          title: 'Microsoft',
          message: 'Sign in using Microsoft',
          apiRef: microsoftAuthApiRef,
        }}
      />
    ),
  },""",1)
        p.write_text(s)
PY

# Build image.
log "Building Backstage Docker image"
docker build -f packages/backend/Dockerfile -t "${ACR_LOGIN_SERVER}/${APP_NAME}:${IMAGE_TAG}" .
az acr login -n "$ACR_NAME" >/dev/null
docker push "${ACR_LOGIN_SERVER}/${APP_NAME}:${IMAGE_TAG}" >/dev/null

# Kubernetes resources.
log "Applying Kubernetes resources"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" create secret generic backstage-runtime \
  --from-literal=POSTGRES_HOST="$POSTGRES_HOST" \
  --from-literal=POSTGRES_PORT="5432" \
  --from-literal=POSTGRES_USER="$PG_ADMIN" \
  --from-literal=POSTGRES_PASSWORD="$PG_PASSWORD" \
  --from-literal=POSTGRES_DB="$PG_DB" \
  --from-literal=AZURE_TENANT_ID="$(az account show --query tenantId -o tsv)" \
  --from-literal=AZURE_CLIENT_ID="${ENTRA_CLIENT_ID:-REPLACE_ME}" \
  --from-literal=AZURE_CLIENT_SECRET="${ENTRA_CLIENT_SECRET:-REPLACE_ME}" \
  --from-literal=GITHUB_TOKEN="${GITHUB_TOKEN:-REPLACE_ME}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SERVICE_ACCOUNT}
  annotations:
    azure.workload.identity/client-id: ${IDENTITY_CLIENT_ID}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/part-of: developer-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: ${APP_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${APP_NAME}
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: ${SERVICE_ACCOUNT}
      containers:
        - name: backstage
          image: ${ACR_LOGIN_SERVER}/${APP_NAME}:${IMAGE_TAG}
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 7007
          env:
            - name: POSTGRES_HOST
              valueFrom: {secretKeyRef: {name: backstage-runtime, key: POSTGRES_HOST}}
            - name: POSTGRES_PORT
              valueFrom: {secretKeyRef: {name: backstage-runtime, key: POSTGRES_PORT}}
            - name: POSTGRES_USER
              valueFrom: {secretKeyRef: {name: backstage-runtime, key: POSTGRES_USER}}
            - name: POSTGRES_PASSWORD
              valueFrom: {secretKeyRef: {name: backstage-runtime, key: POSTGRES_PASSWORD}}
            - name: POSTGRES_DB
              valueFrom: {secretKeyRef: {name: backstage-runtime, key: POSTGRES_DB}}
            - name: AZURE_TENANT_ID
              valueFrom: {secretKeyRef: {name: backstage-runtime, key: AZURE_TENANT_ID}}
            - name: AZURE_CLIENT_ID
              valueFrom: {secretKeyRef: {name: backstage-runtime, key: AZURE_CLIENT_ID}}
            - name: AZURE_CLIENT_SECRET
              valueFrom: {secretKeyRef: {name: backstage-runtime, key: AZURE_CLIENT_SECRET}}
            - name: GITHUB_TOKEN
              valueFrom: {secretKeyRef: {name: backstage-runtime, key: GITHUB_TOKEN}}
          readinessProbe:
            httpGet:
              path: /api/catalog/entities
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /api/catalog/entities
              port: http
            initialDelaySeconds: 60
            periodSeconds: 20
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 2Gi
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: ${APP_NAME}
  ports:
    - name: http
      port: 80
      targetPort: 7007
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}
  annotations:
    kubernetes.io/ingress.class: ${INGRESS_CLASS}
spec:
  rules:
    - host: ${BACKSTAGE_HOSTNAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${APP_NAME}
                port:
                  number: 80
EOF

# If AKS workload identity is not enabled, keep deployment usable but warn.
AKS_WI="$(az aks show -g "$AZ_RESOURCE_GROUP" -n "$AKS_CLUSTER_NAME" --query 'securityProfile.workloadIdentity.enabled' -o tsv 2>/dev/null || true)"
if [ "$AKS_WI" != "true" ]; then
  warn "AKS Workload Identity is not enabled. Storage access through the identity may not work until enabled."
fi

kubectl -n "$NAMESPACE" rollout status deployment/"$APP_NAME" --timeout=10m || {
  kubectl -n "$NAMESPACE" get pods -o wide
  kubectl -n "$NAMESPACE" describe deployment "$APP_NAME" || true
  kubectl -n "$NAMESPACE" logs deployment/"$APP_NAME" --tail=200 || true
  exit 1
}

log "AZURE/AKS BACKSTAGE BASELINE READY"
echo "Namespace:       $NAMESPACE"
echo "Image:           ${ACR_LOGIN_SERVER}/${APP_NAME}:${IMAGE_TAG}"
echo "PostgreSQL:      $POSTGRES_HOST"
echo "TechDocs storage: $STORAGE_NAME/$TECHDOCS_CONTAINER"
echo "Ingress host:    https://${BACKSTAGE_HOSTNAME}"
echo
echo "IMPORTANT NEXT STEPS:"
echo "1) Create/configure the Entra App Registration with redirect URI:"
echo "   https://${BACKSTAGE_HOSTNAME}/api/auth/microsoft/handler/frame"
echo "2) Put the real AZURE_CLIENT_ID/AZURE_CLIENT_SECRET and GITHUB_TOKEN into the Kubernetes secret."
echo "3) Ensure a User entity exists in the Catalog with matching spec.profile.email for each allowed user."
echo "4) Configure your existing Application Gateway/Ingress TLS certificate and routing."
echo "5) Configure APIM to front the App Gateway according to your enterprise API gateway pattern."
echo "6) Move PostgreSQL to private networking and move runtime secrets to Key Vault/CSI or another secret manager."
echo "7) Configure GitHub App rather than a long-lived PAT for production."
echo "8) Use external TechDocs publishing from GitHub Actions to Azure Blob; this deployment is already configured read-only."
