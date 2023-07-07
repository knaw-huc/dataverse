# Copyright 2019 Forschungszentrum Jülich GmbH
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0

# Retrieve target solr version from build arg
ARG SOLR_VERSION

FROM solr:$SOLR_VERSION
# Repeat because of scope (https://docs.docker.com/engine/reference/builder/#scope)
ARG SOLR_VERSION

ENV SOLR_OPTS="-Dsolr.jetty.request.header.size=102400" \
    COLLECTION="collection1" \
    CONFIGSET="dataverse" \
    CONFIGSETS_DIR="/opt/solr-${SOLR_VERSION}/server/solr/configsets"

USER root
# Create the Dataverse configset for Solr
# 1) Copy the default configset
# 2) Modify with config files from build context
RUN true && \
    cp -a ${CONFIGSETS_DIR}/_default ${CONFIGSETS_DIR}/${CONFIGSET} && \
    rm ${CONFIGSETS_DIR}/${CONFIGSET}/conf/managed-schema
COPY --chown=root:root maven/config/*.xml ${CONFIGSETS_DIR}/${CONFIGSET}/conf/

USER ${SOLR_USER}
# Make the precreate script build our collection on startup (can change the env vars to use different)
CMD ["sh", "-c", "solr-precreate ${COLLECTION} ${CONFIGSETS_DIR}/${CONFIGSET}"]

LABEL org.opencontainers.image.created="@git.build.time@" \
      org.opencontainers.image.authors="Research Data Management at FZJ <forschungsdaten@fz-juelich.de>" \
      org.opencontainers.image.url="https://k8s-docs.gdcc.io" \
      org.opencontainers.image.documentation="https://k8s-docs.gdcc.io" \
      org.opencontainers.image.source="https://github.com/gdcc/dataverse/tree/develop%2Bct/conf/solr" \
      org.opencontainers.image.version="@project.version@" \
      org.opencontainers.image.revision="@git.commit.id.abbrev@" \
      org.opencontainers.image.vendor="Global Dataverse Community Consortium" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.title="solr-k8s :: Dataverse-ready Solr" \
      org.opencontainers.image.description="This container image provides a Dataverse-ready Solr Search Index."
