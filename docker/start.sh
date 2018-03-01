#!/bin/bash

echo "Starting service"

. set-environment

export GATEWAY_IP=$(ip route | grep default | cut -d ' ' -f 3)
export STATSD_HOST=${STATSD_HOST:-$GATEWAY_IP}

set -x
topictap "$@"
