#!/bin/bash
cd uniswapFactory
npx hardhat compile 
npx hardhat run --network rinkeby scripts/deploy.js
cd ..
cd superApp
npx hardhat compile 
npx hardhat run --network rinkeby scripts/deploy.js