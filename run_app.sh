#!/bin/bash
cd superApp
npx hardhat compile 
npx hardhat run --network mumbai scripts/deploy.js