import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/dist/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const deployer = await hre.ethers.getNamedSigner('deployer')
    const { deploy, execute } = hre.deployments;

    await deploy("LeverageShort", {
        log: true,
        from: deployer.address,
        args: [
            (await hre.ethers.getContract("LiquidityPool")).address
        ]
    });

    return true;
}

func.tags = ["leverage", "short"];
func.id = "leverage-short";
func.dependencies = ["pool"];
export default func;