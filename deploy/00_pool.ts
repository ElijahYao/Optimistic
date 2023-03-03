import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/dist/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const deployer = await hre.ethers.getNamedSigner('deployer')
    const { deploy, execute } = hre.deployments;

    await deploy("LiquidityPool", {
        log: true,
        from: deployer.address
    });

    return true;
}

func.tags = ["pool"];
func.id = "pool";
export default func;