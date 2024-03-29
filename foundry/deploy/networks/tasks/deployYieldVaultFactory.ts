import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address } from "hardhat-deploy/types";

const deployYieldVaultFactory = async (
  hre: HardhatRuntimeEnvironment,
  chief: Address
) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("YieldVaultFactory", {
    from: deployer,
    args: [chief],
    log: true,
    autoMine: true,
    skipIfAlreadyDeployed: true,
    waitConfirmations: 1,
  });
};

export default deployYieldVaultFactory;
deployYieldVaultFactory.tags = ["YieldVaultFactory"];
deployYieldVaultFactory.skip = async (_env: HardhatRuntimeEnvironment) => true;
