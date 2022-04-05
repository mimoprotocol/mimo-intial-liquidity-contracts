mimo initial liquiidty reward contracts
===========

Smart contracts used in mimo's initial liquidity reward event.



# depoly 

## step1
set .env private key
yarn hardhat --network iotex_test deploy

## step2
set .env TOKEN=0xA9a1544E4a046CD2cdBe8b50A95694936873DCd9
yarn hardhat  run .\scripts\create_launch_event.js  --network iotex_test
