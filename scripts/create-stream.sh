#!/usr/bin/env bash

set -eo pipefail

# import the deployment helpers
. $(dirname $0)/common.sh

startTime=$(($(seth block latest timestamp) + 1800))

# Create a stream
gas=$(seth estimate $FACTORY \
    'createStream(address,address,uint32,uint32,uint32,uint32,bool)' \
    $TOKENA \
    $TOKENB \
    $startTime \
    3600 \
    0 \
    0 \
    true \
    --keystore $ETH_KEYSTORE \
    --password /dev/null)

tx=$(seth send $FACTORY \
    'createStream(address,address,uint32,uint32,uint32,uint32,bool)' \
    $TOKENA \
    $TOKENB \
    $startTime \
    3600 \
    0 \
    0 \
    true \
    --keystore $ETH_KEYSTORE \
    --password /dev/null \
    --gas $gas \
    2>&1 \
    | tee /dev/stderr | grep '^seth-send: 0x' | head -n 1 | cut -d " " -f 2)

stream=$(seth --abi-decode 'noop()(address)' $(seth receipt $tx logs | jq -r '.[0].data' ))
log "Stream Address: " $stream

amount=5000000000000000000000

seth send $TOKENA \
    'approve(address,uint256)' \
    $stream \
    $amount \
    --keystore $ETH_KEYSTORE \
    --password /dev/null

log "Approved $stream to spend $amount of DevTokenA"

tx=$(seth send $stream \
    'fundStream(uint112)' \
    $amount \
    --keystore $ETH_KEYSTORE \
    --password /dev/null)

log "Funded stream with $amount DevTokenA"