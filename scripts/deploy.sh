#!/usr/bin/env bash

set -eo pipefail

# import the deployment helpers
. $(dirname $0)/common.sh

# Deploy.

StreamCreation=$(deploy StreamCreation LockeFactory.sol)
log "StreamCreation deployed at: " $StreamCreation

MerkleStreamCreation=$(deploy MerkleStreamCreation LockeFactory.sol)
log "MerkleStreamCreation deployed at: " $MerkleStreamCreation

StreamFactoryAddr=$(deploy StreamFactory LockeFactory.sol $ETH_FROM $ETH_FROM $StreamCreation $MerkleStreamCreation)
log "StreamFactory deployed at:" $StreamFactoryAddr