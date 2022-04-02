const { ethers } = require("hardhat");

async function getMimoFactory() {
    return await ethers.getContractAt(
        "IMimoFactory",
        "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f"
    );
}

async function getWETH() {
    return await ethers.getContractAt(
        "IWETH",
        "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
    )
}

async function deployRocketFactory(dev, penaltyCollector, machineFiNFT) {
    const weth = await getWETH();
    const router = await ethers.getContractAt(
        "IMimoV2Router02",
        "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
    );
    const factory = await getMimoFactory();
  
    // Factories for deploying our contracts.
    const RocketMimoFactoryCF = await ethers.getContractFactory(
        "RocketMimoFactory"
    );
    const LaunchEventCF = await ethers.getContractFactory("LaunchEvent");
  
    // Deploy the rocket mimo contracts.
    const LaunchEventPrototype = await LaunchEventCF.deploy();
  
    const RocketFactory = await RocketMimoFactoryCF.deploy();
    await RocketFactory.initialize(
        LaunchEventPrototype.address,
        weth.address,
        penaltyCollector.address,
        factory.address,
        machineFiNFT
    );
    return RocketFactory;
}

async function createLaunchEvent(
    RocketFactory,
    issuer,
    block,
    token,
    amount = "105",
    percent = "0.05",
    floor = "1",
    maxAllocation = "5.0"
) {
    await RocketFactory.createRMLaunchEvent(
        issuer.address, // Issuer
        block.timestamp + 60, // Start time (60 seconds from now)
        token.address, // Address of the token being auctioned
        ethers.utils.parseEther(amount), // Amount of tokens for auction
        ethers.utils.parseEther(percent), // Percent of tokens incentives
        ethers.utils.parseEther(floor), // Floor price (1 eth)
        ethers.utils.parseEther("0.5"), // Max withdraw penalty
        ethers.utils.parseEther("0.4"), // Fixed withdraw penalty
        ethers.utils.parseEther(maxAllocation), // max allocation
        60 * 60 * 24 * 7, // User timelock
        60 * 60 * 24 * 8 // Issuer timelock
    );
  
    // Get a reference to the acutal launch event contract.
    LaunchEvent = await ethers.getContractAt(
        "LaunchEvent",
        await RocketFactory.getRMLaunchEvent(token.address)
    );
    return LaunchEvent;
  }

module.exports = {
    getMimoFactory,
    getWETH,
    deployRocketFactory,
    createLaunchEvent,
};
