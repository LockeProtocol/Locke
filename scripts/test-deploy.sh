#!/usr/bin/env bash

set -eo pipefail

# bring up the network
. $(dirname $0)/run-temp-testnet.sh

# run the deploy script
. $(dirname $0)/deploy.sh

# deploy test tokens
. $(dirname $0)/deploy-testtoken.sh

# get the address
factory=$(jq -r '.StreamFactory' out/addresses.json)
tokenA=$(jq -r '.DevTokenA' out/addresses.json)
tokenB=$(jq -r '.DevTokenB' out/addresses.json)

# Check that we are the governor
governor=$(seth --abi-decode "governorship()(address,address,address)" $(seth call $factory 'governorship()') | head -n 1)
[[ $governor = $ETH_FROM ]] || error

# Stream start time 100 seconds in future
startTime=$(($(seth block latest timestamp) + 100))

# Create a stream
gas=$(seth estimate $factory \
    'createStream(address,address,uint32,uint32,uint32,uint32,bool)' \
    $tokenA \
    $tokenB \
    $startTime \
    604800 \
    0 \
    0 \
    true \
    --keystore $TMPDIR/8545/keystore \
    --password /dev/null)

tx=$(seth send $factory \
    'createStream(address,address,uint32,uint32,uint32,uint32,bool)' \
    $tokenA \
    $tokenB \
    $startTime \
    86400 \
    0 \
    0 \
    false \
    --keystore $TMPDIR/8545/keystore \
    --password /dev/null \
    --gas $gas \
    2>&1 \
    | tee /dev/stderr | grep '^seth-send: 0x' | head -n 1 | cut -d " " -f 2)

stream=$(seth --abi-decode 'noop()(address)' $(seth receipt $tx logs | jq -r '.[0].data' ))
log "Stream Address: " $stream

amount=1000000000000000000000000

seth send $tokenA \
    'approve(address,uint256)' \
    $stream \
    $amount \
    --keystore $TMPDIR/8545/keystore \
    --password /dev/null

log "Approved $stream to spend $amount of DevTokenA"

tx=$(seth send $stream \
    'fundStream(uint112)' \
    $amount \
    --keystore $TMPDIR/8545/keystore \
    --password /dev/null)

log "Funded stream with $amount DevTokenA"

echo "export ETH_FROM=$ETH_FROM"
echo "export ETH_KEYSTORE=$TMPDIR/8545/keystore"
echo "export TOKENA=$tokenA"
echo "export TOKENB=$tokenB"
echo "export STREAM=$stream"
echo "export FACTORY=$factory"


echo "Press CTRL+C to exit"

while :
do
	sleep 1
done
