#!/bin/bash

echo "Starting service"

. set-environment

export GATEWAY_IP=$(ip route | grep default | cut -d ' ' -f 3)
export STATSD_HOST=${STATSD_HOST:-$GATEWAY_IP}

/usr/local/bin/set-environment

set -x
kafka-to-s3 \
  ${KAFKA_BROKER+                     --kafka-broker                      "${KAFKA_BROKER}"                     } \
  ${KAFKA_GROUP_ID+                   --kafka-group-id                    "${KAFKA_GROUP_ID}"                   } \
  ${KAFKA_SCHEMA_REGISTRY+            --kafka-schema-registry             "${KAFKA_SCHEMA_REGISTRY}"            } \
  ${KAFKA_POLL_TIMEOUT_MS+            --kafka-poll-timeout-ms             "${KAFKA_POLL_TIMEOUT_MS}"            } \
  ${KAFKA_QUEUED_MAX_MESSAGES_KBYTES+ --kafka-queued-max-messages-kbytes  "${KAFKA_QUEUED_MAX_MESSAGES_KBYTES}" } \
  ${KAFKA_DEBUG_ENABLE+               --kafka-debug-enable                "${KAFKA_DEBUG_ENABLE}"               } \
  ${KAFKA_CONSUMER_COMMIT_PERIOD_SEC+ --kafka-consumer-commit-period-sec  "${KAFKA_CONSUMER_COMMIT_PERIOD_SEC}" } \
  ${INPUT_TOPIC_IN+                   --topic                             "${INPUT_TOPIC_IN}"                   } \
  ${OUTPUT_BUCKET_OUT+                --output-bucket                     "${OUTPUT_BUCKET_OUT}"                } \
  ${STAGING_DIRECTORY+                --staging-directory                 "${STAGING_DIRECTORY}"                } \
  ${STATSD_HOST+                      --statsd-host                       "${STATSD_HOST}"                      } \
  ${STATSD_SAMPLE_RATE+               --statsd-sample-rate                "${STATSD_SAMPLE_RATE}"               } \
  ${STATSD_TAGS+                      --statsd-tags                       "${STATSD_TAGS}"                      } \
  ${LOG_LEVEL+                        --log-level                         "${LOG_LEVEL}"                        }
