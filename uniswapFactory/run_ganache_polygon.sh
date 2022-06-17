#!/bin/bash

# to run tests: 1) run this script 2) in a separate terminal, run "npx hardhat --network localhost test"

# fDAIx address to unlock
export testWalletAddress=0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245
export testWalletAddress2=0x876EabF441B2EE5B5b0554Fd502a8E0600950cFa

# gets all vars from .env
set -o allexport
source .env
set +o allexport

# to test on another chain, just swap the api key
ganache-cli \
--fork $POLYGON_ALCHEMY_KEY \
--unlock $testWalletAddress \
--unlock $testWalletAddress2 \
--networkId 999