#!/usr/bin/env bash

set -eo pipefail

# run the deploy script
. $(dirname $0)/deploy-factory.sh

# deploy test tokens
. $(dirname $0)/deploy-testtoken.sh

# deploy the locke lens
. $(dirname $0)/deploy-lens.sh

# get the address
factory=$(jq -r '.StreamFactory' out/addresses.json)
tokenA=$(jq -r '.DevTokenA' out/addresses.json)
tokenB=$(jq -r '.DevTokenB' out/addresses.json)
lens=$(jq -r '.LockeLens' out/addresses.json)

# Set minStreamStartDelay to 1 minute
tx=$(seth send $factory \
    0x6256cd2d0000000000000000000000000000000000000000000000000000000001e133800000000000000000000000000000000000000000000000000000000001e133800000000000000000000000000000000000000000000000000000000000093a800000000000000000000000000000000000000000000000000000000000000e10000000000000000000000000000000000000000000000000000000000000003c\
    --keystore $ETH_KEYSTORE \
    --password /dev/null)

log "Updated factory GovernableStreamParams"

echo "export ETH_FROM=$ETH_FROM"
echo "export ETH_KEYSTORE=$ETH_KEYSTORE"
echo "export TOKENA=$tokenA"
echo "export TOKENB=$tokenB"
echo "export FACTORY=$factory"
echo "export LENS=$lens"



