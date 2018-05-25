#!/bin/bash

set -e

export CLUB_NAME=${CLUB_NAME:-$USER}
export KAFKA_HOST=${KAFKA_HOST:-localhost}

exe=$(cat $(basename $PWD).cabal | grep executable | head -n 1 | cut -d' ' -f2)
echo "Running: $exe"

stack build
path=$(stack path --local-install-root)

${path}/bin/${exe} service \
  --kafka-broker ${KAFKA_HOST}:9092 \
  --kafka-group-id ${CLUB_NAME}--topictap-${USER} \
  --kafka-schema-registry http://${KAFKA_HOST}:8081 \
  --topic ${CLUB_NAME}--topictap-input-1 \
  --topic ${CLUB_NAME}--topictap-input-2 \
  --output-bucket ${CLUB_NAME}--kafka-backup-2oh2hnw \
  --staging-directory /tmp/staging-files \
  --kafka-poll-timeout-ms 10000 \
  --kafka-debug-enable "broker,protocol" \
  --log-level LevelInfo
