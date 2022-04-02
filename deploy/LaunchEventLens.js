module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  const rocketJoeFactoryAddress = (await deployments.get("RocketMimoFactory"))
    .address;

  await deploy("LaunchEventLens", {
    from: deployer,
    args: [rocketJoeFactoryAddress],
    log: true,
  });
};

module.exports.tags = ["LaunchEventLens"];
module.exports.dependencies = ["RocketMimoFactory"];
