module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const launchEventAddress = (await deployments.get("LaunchEvent")).address;

  const chainId = await getChainId();

  let wethAddress, routerAddress, factoryAddress;
  if (chainId == 4) {
    // rinkeby contract addresses
    wethAddress = ethers.utils.getAddress(
      "0xc778417e063141139fce010982780140aa0cd5ab"
    ); // wrapped ETH ethers.utils.getAddress
    routerAddress = ethers.utils.getAddress(
      "0x7E2528476b14507f003aE9D123334977F5Ad7B14"
    );
    factoryAddress = ethers.utils.getAddress(
      "0x86f83be9770894d8e46301b12E88e14AdC6cdb5F"
    );
  } else if (chainId == 4690) {
    // iotex testnet
    wethAddress = ethers.utils.getAddress(
      "0xff5fae9fe685b90841275e32c348dc4426190db0"
    );
    routerAddress = ethers.utils.getAddress(
      "0xF0CF2cDbED5836C3Aa3f68649e359422991743Fd"
    );
    factoryAddress = ethers.utils.getAddress(
      "0xda257cBe968202Dea212bBB65aB49f174Da58b9D"
    );
  }
  machineFiNFT = process.env.MACHINE_FI_NFT;

  const factory = await deploy("RocketMimoFactory", {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            launchEventAddress,
            wethAddress,
            deployer,
            factoryAddress,
            machineFiNFT,
          ],
        },
      },
    },
    log: true,
  });
};

module.exports.tags = ["RocketMimoFactory"];
module.exports.dependencies = ["LaunchEvent"];
