import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployProvider = async (
  hre: HardhatRuntimeEnvironment,
  providerName: string
) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy(providerName, {
    from: deployer,
    args: [],
    log: true,
    autoMine: true,
    skipIfAlreadyDeployed: true,
    waitConfirmations: 1,
  });
};

export default deployProvider;
deployProvider.tags = ["Provider"];
deployProvider.skip = async (_env: HardhatRuntimeEnvironment) => true;
