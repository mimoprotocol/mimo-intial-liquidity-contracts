const { ethers, deployments } = require("hardhat");

async function main() {
    // This is just a convenience check
    if (network.name === "hardhat") {
        console.warn(
            "You are trying to deploy a contract to the Hardhat Network, which" +
            "gets automatically created and destroyed every time. Use the Hardhat" +
            " option '--network localhost'"
        );
    }
  
    // ethers is available in the global scope
    const [deployer] = await ethers.getSigners();
    console.log(
        "Deploying the contracts with the account:",
        await deployer.getAddress()
    );
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const tokenFactory = await ethers.getContractFactory("ERC20Token");
    const token = tokenFactory.attach(process.env.TOKEN);

    const amount = ethers.utils.parseEther("105");
    const factoryAddress = (await deployments.get("RocketMimoFactory")).address;
    const approveTokenTx = await token.approve(factoryAddress, amount);
    await approveTokenTx.wait();
    console.log(`Approved ${amount.toString()} ${await token.symbol()} to ${factoryAddress}`);

    const factoryFactory = await ethers.getContractFactory("RocketMimoFactory");
    const factory = factoryFactory.attach(factoryAddress);
    const createTx = await factory.createRMLaunchEvent(
        deployer.address, // issuer
        (await ethers.provider.getBlock()).timestamp + 60,
        token.address,
        amount,
        ethers.utils.parseEther("0.05"), // percent
        ethers.utils.parseEther("1"), // Floor price (1 eth)
        ethers.utils.parseEther("0.5"), // Max withdraw penalty
        ethers.utils.parseEther("0.4"), // Fixed withdraw penalty
        ethers.utils.parseEther("10"), // max allocation
        // TODO change to 7 days
        60 * 60 * 1, // User timelock
        60 * 60 * 2 // Issuer timelock
    );
    await createTx.wait();
    
    const eventAddress = await factory.getRMLaunchEvent(token.address);
    console.log(`Token ${token.address} launch event is ${eventAddress}`);
}
  
main()
    .then(() => process.exit(0))
    .catch((error) => { 
        console.error(error);
        process.exit(1);
    });
