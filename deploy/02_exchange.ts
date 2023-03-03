import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/dist/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const deployer = await hre.ethers.getNamedSigner('deployer')
    const { deploy, execute } = hre.deployments;

    let usdc = hre.ethers.constants.AddressZero;
    if (hre.network.name == "hardhat") {
        usdc = (await deploy("USDC", {
            contract: "MockERC20",
            from: deployer.address,
            log: true,
            args: ["MockUSDC", "USDC"]
        })).address;
    }


    await deploy("SubstanceExchange", {
        log: true,
        from: deployer.address,
        args: [
            (await hre.ethers.getContract("LiquidityPool")).address,
            (await hre.ethers.getContract("LeverageShort")).address,
            usdc
        ]
    });

    return true;
}

func.tags = ["exchange"];
func.id = "exchange";
func.dependencies = ["pool", "leverage"];
export default func;