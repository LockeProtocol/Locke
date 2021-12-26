#!/usr/bin/env bash

set -eo pipefail

# # import the deployment helpers
# # Already imported in deploy.sh
# . $(dirname $0)/common.sh

# Deploy.
export DTA=$(deploy DevTokenA DevTokenA.sol)
log "DevTokenA deployed at:" $DTA

export DTB=$(deploy DevTokenB DevTokenB.sol)
log "DevTokenB deployed at:" $DTB
