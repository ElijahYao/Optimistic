import { expect } from "chai";
import hre, { deployments } from "hardhat";
import { SubstanceExchange, IERC20 } from "../typechain";

const setup = async () => {
    await deployments.fixture(["exchange"]);
    const { deployer } = await hre.ethers.getNamedSigners();
    const exchange = await hre.ethers.getContract("SubstanceExchange") as SubstanceExchange;
    const usdc = await hre.ethers.getContract("USDC") as IERC20;

    return { deployer, exchange, usdc };
}

describe("exchange test", function () {
    it("test deposit", async () => {
        const { deployer, exchange, usdc } = await setup();

        expect(await usdc.balanceOf(deployer.address)).to.gt(0);
    });
})
