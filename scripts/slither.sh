#!/usr/bin/env bash
# Make dependencies available
export DAPP_REMAPPINGS=$(cat remappings.txt)

export DAPP_SOLC_VERSION=0.8.11
# If you're getting an "invalid character at offset" error, comment this out.
export DAPP_LINK_TEST_LIBRARIES=0
export DAPP_TEST_VERBOSITY=1
export DAPP_TEST_SMTTIMEOUT=500000

# Optimize your contracts before deploying to reduce runtime execution costs.
# Check out the docs to learn more: https://docs.soliditylang.org/en/v0.8.9/using-the-compiler.html#optimizer-options
export DAPP_BUILD_OPTIMIZE=1
export DAPP_BUILD_OPTIMIZE_RUNS=200

# set so that we can deploy to local node w/o hosted private keys
export ETH_RPC_ACCOUNTS=true

slither . --compile-force-framework dapp --filter-path "./src/test|./lib/forge-std|./lib/solmate" --exclude timestamp