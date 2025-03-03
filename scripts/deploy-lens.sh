#!/usr/bin/env bash

set -eo pipefail

# # import the deployment helpers
# # Already imported in deploy.sh
# . $(dirname $0)/common.sh

# Deploy.
export LENS=$(deploy LockeLens LockeLens.sol)
log "LockeLens deployed at:" $LENS