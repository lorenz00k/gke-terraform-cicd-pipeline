#!/usr/bin/env bash
#
# Sets up Workload Identity Federation (WIF) so that GitHub Actions can deploy to
# Google Cloud without a stored service account key.
#
# It creates, or updates if they already exist:
#   - a workload identity pool and an OIDC provider that only accepts tokens from one
#     GitHub repository and one branch
#   - a service account with the roles the deployment needs
#   - the permission for that repository to impersonate the service account
#
# Safe to run more than once. You need permission to manage IAM in the project
# (for example the Owner role).
#
# If you deleted a pool with the same ID in the last 30 days, Google keeps it in a deleted
# state: undelete it, or run this script with POOL_ID=<another-id>.

set -euo pipefail

POOL_ID="${POOL_ID:-github-pool}"
PROVIDER_ID="${PROVIDER_ID:-github-provider}"
SA_NAME="${SA_NAME:-github-deployer}"
ROLES=(roles/artifactregistry.writer roles/container.developer)

PROJECT_ID=""
REPO=""
BRANCH="main"
SET_VARS=false

log() { printf '==> %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 --project <project-id> --repo <owner>/<repo> [--branch <branch>] [--set-github-variables]

  --project               Google Cloud project ID
  --repo                  GitHub repository that may deploy, as owner/name
  --branch                Branch that may deploy (default: main)
  --set-github-variables  Also set WIF_PROVIDER and WIF_SERVICE_ACCOUNT as variables of the
                          GitHub repository (needs the GitHub CLI, logged in via 'gh auth login')
EOF
}

# Retries a command a few times, because new IAM objects can take a moment to become visible.
retry() {
  local attempt
  for attempt in 1 2 3 4 5 6; do
    if "$@"; then return 0; fi
    log "Not ready yet, retrying in 5 seconds (attempt ${attempt}/6)"
    sleep 5
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project|--repo|--branch)
      [[ $# -ge 2 ]] || die "$1 needs a value"
      case "$1" in
        --project) PROJECT_ID="$2" ;;
        --repo) REPO="$2" ;;
        --branch) BRANCH="$2" ;;
      esac
      shift 2
      ;;
    --set-github-variables) SET_VARS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
done

[[ -n "$PROJECT_ID" && -n "$REPO" ]] || { usage >&2; exit 1; }
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--repo must look like owner/name"

command -v gcloud >/dev/null 2>&1 || die "gcloud is not installed"
[[ -n "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')" ]] \
  || die "Not logged in to Google Cloud. Run: gcloud auth login"
gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1 \
  || die "Cannot access project '$PROJECT_ID'. Check the ID and your permissions."

if [[ "$SET_VARS" == true ]]; then
  command -v gh >/dev/null 2>&1 || die "--set-github-variables needs the GitHub CLI (gh)"
  gh auth status >/dev/null 2>&1 || die "Not logged in to GitHub. Run: gh auth login"
fi

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
MAPPING="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref"
CONDITION="assertion.repository == '${REPO}' && assertion.ref == 'refs/heads/${BRANCH}'"
ISSUER="https://token.actions.githubusercontent.com"

log "Enabling the required APIs"
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="$PROJECT_ID"

if gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$PROJECT_ID" --location=global >/dev/null 2>&1; then
  POOL_STATE="$(gcloud iam workload-identity-pools describe "$POOL_ID" \
    --project="$PROJECT_ID" --location=global --format='value(state)')"
  [[ "$POOL_STATE" != "DELETED" ]] \
    || die "Pool '$POOL_ID' was deleted recently. Undelete it or set POOL_ID to another name."
  log "Pool '$POOL_ID' already exists"
else
  log "Creating workload identity pool '$POOL_ID'"
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --project="$PROJECT_ID" --location=global \
    --display-name="GitHub Actions pool"
fi

if gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
  --project="$PROJECT_ID" --location=global \
  --workload-identity-pool="$POOL_ID" >/dev/null 2>&1; then
  log "Provider '$PROVIDER_ID' already exists, updating it to the current repository and branch"
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER_ID" \
    --project="$PROJECT_ID" --location=global \
    --workload-identity-pool="$POOL_ID" \
    --issuer-uri="$ISSUER" \
    --attribute-mapping="$MAPPING" \
    --attribute-condition="$CONDITION"
else
  log "Creating OIDC provider '$PROVIDER_ID' (only accepts ${REPO} on branch ${BRANCH})"
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --project="$PROJECT_ID" --location=global \
    --workload-identity-pool="$POOL_ID" \
    --display-name="GitHub provider" \
    --issuer-uri="$ISSUER" \
    --attribute-mapping="$MAPPING" \
    --attribute-condition="$CONDITION"
fi

if gcloud iam service-accounts describe "$SA_EMAIL" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  log "Service account '$SA_EMAIL' already exists"
else
  log "Creating service account '$SA_EMAIL'"
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" --display-name="GitHub deployer"
fi

for role in "${ROLES[@]}"; do
  log "Granting $role to the service account"
  retry gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" --role="$role" \
    --condition=None --quiet >/dev/null
done

log "Allowing ${REPO} to impersonate the service account"
retry gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT_ID" --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${REPO}" \
  --condition=None --quiet >/dev/null

PROVIDER_NAME="$(gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
  --project="$PROJECT_ID" --location=global \
  --workload-identity-pool="$POOL_ID" --format='value(name)')"

if [[ "$SET_VARS" == true ]]; then
  log "Setting the GitHub repository variables"
  gh variable set WIF_PROVIDER --body "$PROVIDER_NAME" --repo "$REPO"
  gh variable set WIF_SERVICE_ACCOUNT --body "$SA_EMAIL" --repo "$REPO"
  printf '\nDone. WIF_PROVIDER and WIF_SERVICE_ACCOUNT are set in %s.\n' "$REPO"
else
  cat <<EOF

Done. Add these as variables of the GitHub repository
(Settings > Secrets and variables > Actions > Variables):

  WIF_PROVIDER         = ${PROVIDER_NAME}
  WIF_SERVICE_ACCOUNT  = ${SA_EMAIL}
EOF
fi