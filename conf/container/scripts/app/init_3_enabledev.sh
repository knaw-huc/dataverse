#!/bin/bash

set -euo pipefail

###### ###### ###### ###### ###### ###### ###### ###### ###### ###### ######
# This script enables different development options, like a JMX connector
# usable with VisualVM, JRebel hot-reload support and JDWP debugger service.
# Enable it by adding env vars on startup (e.g. via ConfigMap)
#
# As this script is "sourced" from entrypoint.sh, we can manipulate env vars
# for the parent shell before executing Payara.
###### ###### ###### ###### ###### ###### ###### ###### ###### ###### ######

# 0. Init variables
ENABLE_JMX=${ENABLE_JMX:-0}
ENABLE_JDWP=${ENABLE_JDWP:-0}
ENABLE_JREBEL=${ENABLE_JREBEL:-0}

# ENABLE_INTEGRATION_TESTS is not used here, but in bootstrap-job.sh for configuration bits necessary to run integration tests

DV_PREBOOT=${PAYARA_DIR}/dataverse_preboot
echo "# Dataverse preboot configuration for Payara" > "${DV_PREBOOT}"

# 1. Configure JMX (enabled by default on port 8686, but requires SSL)
# See also https://blog.payara.fish/monitoring-payara-server-with-jconsole
# To still use it, you can use a sidecar container proxying or using JMX via localhost without SSL.
if [ "${ENABLE_JMX}" = "1" ]; then
  echo "Enabling unsecured JMX on 0.0.0.0:8686. You'll need a sidecar for this, as access is allowed from same machine only (without SSL)."
  { \
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.jvm=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.connector-service=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.connector-connection-pool=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.jdbc-connection-pool=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.web-services-container=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.ejb-container=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.thread-pool=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.http-service=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.security=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.jms-service=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.jersey=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.transaction-service=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.jpa=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.web-container=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.orb=HIGH"
    echo "set configs.config.server-config.monitoring-service.module-monitoring-levels.deployment=HIGH"
    #echo "set configs.config.server-config.admin-service.jmx-connector.system.address=127.0.0.1"
    echo "set configs.config.server-config.admin-service.jmx-connector.system.security-enabled=false"
  } >> "${DV_PREBOOT}"
fi

# 2. Enable JDWP via debugging switch
if [ "${ENABLE_JDWP}" = "1" ]; then
  echo "Enabling JDWP remote debugging support via asadmin debugging switch."
  export PAYARA_ARGS="${PAYARA_ARGS} --debug=true"
fi


# 3. Enable JRebel (hot-redeploy)
if [ "${ENABLE_JREBEL}" = "1" ] && [ -s "${JREBEL_LIB}" ]; then
  echo "Enabling JRebel support with enabled remoting_plugin option."
  export JVM_ARGS="${JVM_ARGS} -agentpath:${JREBEL_LIB} -Drebel.remoting_plugin=true"
fi

# 4. Add the commands to the existing postboot file, but insert BEFORE deployment
TMP_PREBOOT=$(mktemp)
cat "${DV_PREBOOT}" "${PREBOOT_COMMANDS}" > "${TMP_PREBOOT}"
mv "${TMP_PREBOOT}" "${PREBOOT_COMMANDS}"
echo "DEBUG: preboot contains the following commands:"
echo "--------------------------------------------------"
cat "${PREBOOT_COMMANDS}"
echo "--------------------------------------------------"
