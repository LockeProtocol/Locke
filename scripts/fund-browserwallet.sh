#!/bin/bash -v

seth send $1 --value 10000000000000000000
seth send "$TOKENB" 'transfer(address,uint256)' $1 100000000000000000000