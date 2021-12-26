#!/usr/bin/env bash

set -eo pipefail

# import the deployment helpers
. $(dirname $0)/common.sh

# Deploy.
StreamFactoryAddr=$(deploy StreamFactory Locke.sol $ETH_FROM $ETH_FROM)
log "StreamFactory deployed at:" $StreamFactoryAddr
