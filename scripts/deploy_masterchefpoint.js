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

    const chefFactory = await ethers.getContractFactory("MasterChefPoint");
    const chef = await chefFactory.deploy();
    
    console.log(`Deployed MasterChefPoint ${chef.address}`);
}
  
main()
    .then(() => process.exit(0))
    .catch((error) => { 
        console.error(error);
        process.exit(1);
    });
