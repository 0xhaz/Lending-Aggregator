import { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address, Deployment } from "hardhat-deploy/types";

const deployBorrowingVaultFactory = async (
  hre: HardhatRuntimeEnvironment,
  chief: Address
) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy("BorrowingVaultFactory", {
    from: deployer,
    args: [chief],
    log: true,
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    skipIfAlreadyDeployed: true,
    waitConfirmations: 1,
  });
};

export const deployBorrowingVault = async (
  hre: HardhatRuntimeEnvironment,
  asset: Address,
  debtAsset: Address,
  oracle: Address,
  _providers: Address[]
) => {
  const { deployments, getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();
  const abiCoder = ethers.utils.defaultAbiCoder;

  const vaultFactory: Deployment = await deployments.get(
    "BorrowingVaultFactory"
  );

  const vaultData = abiCoder.encode(
    ["address", "address", "address"],
    [asset, debtAsset, oracle]
  );

  await deployments.execute(
    "Chief",
    {
      from: deployer,
      log: true,
      autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
      waitConfirmations: 1,
    },
    "deployVault",
    vaultFactory.address,
    vaultData
  );
};

export default deployBorrowingVaultFactory;
deployBorrowingVaultFactory.tags = ["BorrowingVaultFactory"];
deployBorrowingVaultFactory.skip = async (_env: HardhatRuntimeEnvironment) =>
  true;
