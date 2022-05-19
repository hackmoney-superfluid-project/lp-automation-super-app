#!/bin/bash
cd uniswapFactory
npx hardhat compile 
npx hardhat run --network mumbai scripts/deploy.js