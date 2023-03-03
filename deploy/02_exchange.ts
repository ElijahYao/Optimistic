import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/dist/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const deployer = await hre.ethers.getNamedSigner('deployer')
    const { deploy, execute } = hre.deployments;

    await deploy("SubstanceExchange", {
        log: true,
        from: deployer.address,
        args: [
            (await hre.ethers.getContract("LiquidityPool")).address,
            (await hre.ethers.getContract("LeverageShort")).address
        ]
    });

    return true;
}

func.tags = ["exchange"];
func.id = "exchange";
func.dependencies = ["pool", "leverage"];
export default func;