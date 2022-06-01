#!/bin/bash

# to run tests: 1) run this script 2) in a separate terminal, run "npx hardhat --network localhost test"

# fDAIx address to unlock
export testWalletAddress=0xFc25b7BE2945Dd578799D15EC5834Baf34BA28e1

# gets all vars from .env
set -o allexport
source .env
set +o allexport

# to test on another chain, just swap the api key
ganache-cli \
--fork $RINKEBY_ALCHEMY_KEY \
--unlock $testWalletAddress \
--networkId 999