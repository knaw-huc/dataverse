#!/bin/bash
################################################################################
# Configure Glassfish
#
# BEWARE: As this is done for Kubernetes, we will ALWAYS start with a fresh container!
#         When moving to Glassfish/Payara 5+ the option commands are idempotent.
#         The resources are to be created by the application on deployment,
#         once Dataverse has proper refactoring, etc.
#         See upstream issue IQSS/dataverse#5292
################################################################################

# Fail on any error
set -e
# Include some sane defaults
# shellcheck disable=SC1091
. "${SCRIPT_DIR}"/default.config

# 0. Define postboot commands file to be read by Payara and clear it
DV_POSTBOOT=${PAYARA_DIR}/dataverse_postboot
echo "# Dataverse postboot configuration for Payara" > "${DV_POSTBOOT}"

# 1. Password aliases from secrets
# TODO: This is ugly and dirty. It leaves leftovers on the filesystem.
#       It should be replaced by using proper config mechanisms sooner than later,
#       like MicroProfile Config API.
for alias in rserve doi
do
  if [ -f "${SECRETS_DIR}"/$alias/password ]; then
    echo "INFO: Defining password alias for $alias"
    PASSTMP=$(mktemp)
    sed -e "s#^#AS_ADMIN_ALIASPASSWORD=#" < "${SECRETS_DIR}"/$alias/password > "${PASSTMP}"
    echo "create-password-alias ${alias}_password_alias --passwordfile ${PASSTMP}" >> "${DV_POSTBOOT}"
  else
    echo "WARNING: Could not find 'password' secret for ${alias} in ${SECRETS_DIR}. Check your Kubernetes Secrets and their mounting!"
  fi
done

# 1b. Create AWS access credentials when storage driver is set to s3
# Find all access keys
if [ -d "${SECRETS_DIR}/s3" ]; then
  S3_KEYS=$(find "${SECRETS_DIR}/s3" -readable -type f -iname '*access-key')
  S3_CRED_FILE=${HOME_DIR}/.aws/credentials
  mkdir -p "$(dirname "${S3_CRED_FILE}")"
  rm -f "${S3_CRED_FILE}"
  # Iterate keys
  while IFS= read -r S3_ACCESS_KEY; do
    echo "Loading S3 key ${S3_ACCESS_KEY}"
    # Try to find the secret key, parse for profile and add to the credentials file.
    S3_PROFILE=$(echo "${S3_ACCESS_KEY}" | sed -ne "s#.*/\(.*\)-access-key#\1#p")
    S3_SECRET_KEY=$(echo "${S3_ACCESS_KEY}" | sed -ne "s#\(.*/\|.*/.*-\)access-key#\1secret-key#p")

    if [ -r "${S3_SECRET_KEY}" ]; then
      {
        [ -z "${S3_PROFILE}" ] && echo "[default]" || echo "[${S3_PROFILE}]"
        sed -e "s#^#aws_access_key_id = #" -e "s#\$#\n#" < "${S3_ACCESS_KEY}"
        sed -e "s#^#aws_secret_access_key = #" -e "s#\$#\n#" < "${S3_SECRET_KEY}"
        echo ""
      } >> "${S3_CRED_FILE}"
    else
      echo "ERROR: Could not find or read matching \"$S3_SECRET_KEY\"."
      exit 1
    fi
  done <<< "${S3_KEYS}"
fi

# 2. Domain-spaced resources (JDBC, JMS, ...)
# TODO: This is ugly and dirty. It should be replaced with resources from
#       EE 8 code annotations or at least glassfish-resources.xml
# NOTE: postboot commands is not multi-line capable, thus spaghetti needed.

# JavaMail
echo "INFO: Defining JavaMail."
echo "create-javamail-resource --mailhost=${MAIL_SERVER} --mailuser=dataversenotify --fromaddress=${MAIL_FROMADDRESS} mail/notifyMailSession" >> "${DV_POSTBOOT}"

# 3. Domain based configuration options
# Set Dataverse environment variables
echo "INFO: Defining system properties for Dataverse configuration options."
#env | grep -Ee "^(dataverse|doi)_" | sort -fd
env -0 | grep -z -Ee "^(dataverse|doi)_" | while IFS='=' read -r -d '' k v; do
    # transform __ to -
    # shellcheck disable=SC2001
    KEY=$(echo "${k}" | sed -e "s#__#-#g")
    # transform remaining single _ to .
    KEY=$(echo "${KEY}" | tr '_' '.')

    # escape colons in values
    # shellcheck disable=SC2001
    v=$(echo "${v}" | sed -e 's/:/\\\:/g')

    echo "DEBUG: Handling ${KEY}=${v}."
    echo "create-system-properties ${KEY}=${v}" >> "${DV_POSTBOOT}"
done

# 4. Add the commands to the existing postboot file, but insert BEFORE deployment
TMPFILE=$(mktemp)
cat "${DV_POSTBOOT}" "${POSTBOOT_COMMANDS}" > "${TMPFILE}" && mv "${TMPFILE}" "${POSTBOOT_COMMANDS}"
echo "DEBUG: postboot contains the following commands:"
echo "--------------------------------------------------"
cat "${POSTBOOT_COMMANDS}"
echo "--------------------------------------------------"
