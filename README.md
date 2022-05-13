# Super App
This repository holds the contract code that will receive Superfluid streams from our frontend application and process them as needed. This will include unwrapping the incoming super tokens and interacting with Uniswap liquidity provider positions.

## Steps to setup Chain Link Keeper
1. Deploy contract with deploy script
2. Fund your wallet with LINK using the faucet: https://faucets.chain.link/mumbai
3. Follow these steps: https://docs.chain.link/docs/chainlink-keepers/register-upkeep/
4. Set the gas limit to 800,000 (we'll need to figure out the exact value for this later on)
( if the performUpkeep() function requires more gas than the limit, nothing will run and chain link won't display any errors )

## Testing:
1. After registering the UpKeep, start a DAIx stream to the contract
2. Roughly every 10 seconds, the contract should downgrade all DAIx to DAI
3. You can check this by going to the DAI and DAIx addresses on polygonscan and searching the contract address:
DAIx: https://mumbai.polygonscan.com/token/0x5d8b4c2554aeb7e86f387b4d6c00ac33499ed01f
DAI: https://mumbai.polygonscan.com/token/0x15f0ca26781c3852f8166ed2ebce5d18265cceb7
