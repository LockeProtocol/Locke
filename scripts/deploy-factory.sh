#!/usr/bin/env bash

set -eo pipefail

# import the deployment helpers
. $(dirname $0)/common.sh

# Deploy.

DateTime=$(deploy DateTime LockeERC20.sol)
log "DateTime deployed at: " $DateTime

export DAPP_LIBRARIES=" src/LockeERC20.sol:DateTime:$DateTime"

dapp build

StreamCreation=$(deploy StreamCreation LockeFactory.sol)
log "StreamCreation deployed at: " $StreamCreation

MerkleStreamCreation=$(deploy MerkleStreamCreation LockeFactory.sol)
log "MerkleStreamCreation deployed at: " $MerkleStreamCreation

StreamFactoryAddr=$(deploy StreamFactory LockeFactory.sol $ETH_FROM $ETH_FROM $StreamCreation $MerkleStreamCreation)
log "StreamFactory deployed at:" $StreamFactoryAddr