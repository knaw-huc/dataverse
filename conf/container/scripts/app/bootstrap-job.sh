#!/bin/bash
################################################################################
# This script is used to bootstrap a Dataverse installation.
#
# It runs all necessary database foo that cannot be done from EclipseLink.
# It initializes the most basic settings and
# creates root dataverse and admin account.
################################################################################

# Fail on any error
set -euo pipefail
# Include some sane defaults
# shellcheck disable=SC1091
. "${SCRIPT_DIR}"/default.config
DATAVERSE_SERVICE_HOST=${DATAVERSE_SERVICE_HOST:-"dataverse"}
DATAVERSE_SERVICE_PORT_HTTP=${DATAVERSE_SERVICE_PORT_HTTP:-"8080"}
DATAVERSE_URL=${DATAVERSE_URL:-"http://${DATAVERSE_SERVICE_HOST}:${DATAVERSE_SERVICE_PORT_HTTP}"}
# The Solr Service IP is always available under its name within the same namespace.
# If people want to use a different Solr than we normally deploy, they have the
# option to override.
SOLR_K8S_HOST=${SOLR_K8S_HOST:-"solr"}

# Check API key secret is available
if [ ! -s "${SECRETS_DIR}/api/key" ]; then
  echo "No API key present. Failing."
  exit 126
fi

# Load dataverseAdmin password if present
if [ -s "${SECRETS_DIR}/admin/password" ]; then
  echo "Loading admin password from secret file."
  ADMIN_PASSWORD=$(cat "${SECRETS_DIR}"/admin/password)
fi

# 2) Initialize common data structures to make Dataverse usable
cd "${DEPLOY_DIR}"/dataverse/supplements
# 2a) Patch load scripts with k8s based URL
sed -i -e "s#localhost:8080#${DATAVERSE_SERVICE_HOST}:${DATAVERSE_SERVICE_PORT_HTTP}#" setup-*.sh
# 2b) Patch user and root dataverse JSON with contact email
sed -i -e "s#root@mailinator.com#${CONTACT_MAIL}#" data/dv-root.json
sed -i -e "s#dataverse@mailinator.com#${CONTACT_MAIL}#" data/user-admin.json
# 2c) Use script(s) to bootstrap the instance.
# Hint: writing to stdout but redact apiToken from logs. Save to tempfile to extract token for later use
SETUP_LOG=$(mktemp)
./setup-all.sh --insecure -p="${ADMIN_PASSWORD:-admin}" | tee "${SETUP_LOG}" | sed -e 's#"apiToken":".*"#"apiToken":"****"#'
# 2d) Extract dataverseAdmin API token and cleanup
ADMIN_API_TOKEN=$(grep "apiToken" "${SETUP_LOG}" | jq -r .data.apiToken)
rm "${SETUP_LOG}"

# 4.) Configure Solr location
curl -sS -w '\n' -X PUT -d "${SOLR_K8S_HOST}:8983" "${DATAVERSE_URL}/api/admin/settings/:SolrHostColonPort"

# 5.) Provision builtin users key to enable creation of more builtin users
#     Hint: if we want to enable IT tests, let's stick the default from setup-all.sh (burrito).
#     Otherwise: no secret present means disable builtin users by deleting the key.
if [ "${ENABLE_INTEGRATION_TESTS}" = "0" ]; then
  if [ -s "${SECRETS_DIR}/api/userskey" ]; then
    curl -sS -w '\n' -X PUT -d "$(cat "${SECRETS_DIR}"/api/userskey)" "${DATAVERSE_URL}/api/admin/settings/BuiltinUsers.KEY"
  else
    curl -sS -w '\n' -X DELETE "${DATAVERSE_URL}/api/admin/settings/BuiltinUsers.KEY"
  fi
fi

# 6.) Block access to the API endpoints, but allow for request with key from secret
if [ "${ENABLE_INTEGRATION_TESTS}" = "0" ]; then
  curl -sS -w '\n' -X PUT -d "$(cat "${SECRETS_DIR}"/api/key)" "${DATAVERSE_URL}/api/admin/settings/:BlockedApiKey"
  curl -sS -w '\n' -X PUT -d unblock-key "${DATAVERSE_URL}/api/admin/settings/:BlockedApiPolicy"
  curl -sS -w '\n' -X PUT -d admin,test "${DATAVERSE_URL}/api/admin/settings/:BlockedApiEndpoints"
fi

# 7.) Preparation steps for integration testing
# NOTE: One day this might be better included in Java tests or even a self-bootstrapping instance
if [ "${ENABLE_INTEGRATION_TESTS}" = "1" ] || [ "${ENABLE_INTEGRATION_TESTS}" = "true" ]; then
  echo "Running in Integration Testing Mode"
  # Enable fullContributor role on root dataverse collection for all authenticated users
  echo "Enable authenticated users full contributore role on root Dataverse collection"
  curl -sS -w '\n' -X POST -H "X-Dataverse-key:$ADMIN_API_TOKEN" -H "Content-type:application/json" -d "{\"assignee\": \":authenticated-users\",\"role\": \"fullContributor\"}" "${DATAVERSE_URL}/api/dataverses/root/assignments"
  # Publish root dataverse collection
  echo "Publishing root Dataverse collection"
  curl -sS -w '\n' -X POST -H "X-Dataverse-key:$ADMIN_API_TOKEN" "${DATAVERSE_URL}/api/dataverses/root/actions/:publish"
fi

# Initial configuration of Dataverse
exec "${SCRIPT_DIR}"/config-job.sh
