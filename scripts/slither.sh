#!/usr/bin/env bash

slither . --compile-force-framework dapp --filter-path "./src/test|./lib/forge-std|./lib/solmate" --exclude timestamp