#!/usr/bin/env bash -v

set -eo pipefail

# bring up the network
#. $(dirname $0)/run-temp-testnet.sh
export ETH_FROM=$(seth ls --keystore $ETH_KEYSTORE | cut -f1)

# run the deploy script
#. $(dirname $0)/deploy.sh

# deploy test tokens
#. $(dirname $0)/deploy-testtoken.sh

# get the address
factory=$(jq -r '.StreamFactory' out/addresses.json)
token=$(jq -r '.TestToken' out/addresses.json)

# # Check that we are the governor
# governor=$(seth --abi-decode "governorship()(address,address,address)" $(seth call $factory 'governorship()') | head -n 1)
# echo $governor
# echo $ETH_FROM
# [[ $governor = $ETH_FROM ]] || error

# Stream start time 10 seconds in future
#starttime=$(($(seth block latest timestamp) + 3600))
#echo "Start time: $starttime"
currentTime=$(seth block latest timestamp)

# Create a stream
gas=$(seth estimate $factory \
    'createStream(address,address,uint32,uint32,uint32,uint32,bool)' \
    $token \
    $token \
    $(($currentTime + 3600)) \
    3600 \
    0 \
    0 \
    false \
    --keystore $ETH_KEYSTORE \
    --password /dev/null)

echo $gas

seth send $factory \
    'createStream(address,address,uint32,uint32,uint32,uint32,bool)' \
    $token \
    $token \
    $(($currentTime + 3600)) \
    3600 \
    0 \
    0 \
    false \
    --keystore $ETH_KEYSTORE \
    --password /dev/null \
    --gas $gas

echo "hello"

read -n 1 -s -r -p "Press any key to continue"

# # the initial greeting must be empty
# greeting=$(seth call $addr 'greeting()(string)')
# [[ $greeting = "" ]] || error

# # set it to a value
# seth send $addr \
#     'greet(string memory)' '"yo"' \
#     --keystore $TMPDIR/8545/keystore \
#     --password /dev/null

# sleep 1

# # should be set afterwards
# greeting=$(seth call $addr 'greeting()(string)')
# [[ $greeting = "yo" ]] || error

# echo "Success."
