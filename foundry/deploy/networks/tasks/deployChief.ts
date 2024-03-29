import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployChief = async (
  hre: HardhatRuntimeEnvironment,
  deployTimelock: boolean,
  deployAddrMapper: boolean
) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("Chief", {
    from: deployer,
    args: [deployTimelock, deployAddrMapper],
    log: true,
    autoMine: true,
    skipIfAlreadyDeployed: true,
    waitConfirmations: 1,
  });
};

export default deployChief;
deployChief.tags = ["Chief"];
deployChief.skip = async (_env: HardhatRuntimeEnvironment) => true;
