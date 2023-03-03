// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ILeverageShort.sol";
import "../interfaces/ILiquidityPool.sol";

import "hardhat/console.sol";


contract SubstanceExchange {
    using SafeERC20 for IERC20;

    mapping(address => int) public traderUSDTBalance;
    ILeverageShort public immutable leverageShort;
    ILiquidityPool public immutable liquidityPool;

    IERC20 public USDCToken;

    bool transferUSDC;

    int public constant usdcDemical = 10 ** 6;

    constructor(ILiquidityPool pool_, ILeverageShort short_, IERC20 usdc_) {
        liquidityPool = pool_;
        leverageShort = short_;
        USDCToken = usdc_;
        transferUSDC = false;
    }

    event openShortOrder(address indexed _trader, int _openPrice, int _marginAmount, int _leverage, int _size);
    event closeShortOrder(address indexed _trader, int _closePrice, int _tokenAmount);

    function getTokenPrice() public view returns (int) {
        if (liquidityPool.totalToken() == 0) {
            return 1 * usdcDemical;
        }
        int futurePrice = getFuturePrice();
        int lpValue = liquidityPool.getLiquidityPoolValue(futurePrice);
        int leverageShortUPL = leverageShort.getGlobalUPL(futurePrice);
        return ((lpValue + leverageShortUPL) * usdcDemical) / liquidityPool.totalToken();
    }

    // 用户充值。
    function traderDeposit(int usdcAmount) public {
        require(usdcAmount >= 0, "Negative USDC amount");
        if (transferUSDC) {
            bool success = USDCToken.transferFrom(msg.sender, address(this), uint(usdcAmount));
            require(success, "Transfer USDC failed");
        }
        traderUSDTBalance[msg.sender] += usdcAmount;
    }

    // 用户提款。
    function traderWithdraw(int usdcAmount) public {
        require(usdcAmount >= 0, "Negative USDC amount");
        require(traderUSDTBalance[msg.sender] >= usdcAmount, "Insufficient USDC balance");
        if (transferUSDC) {
            bool success = USDCToken.transfer(msg.sender, uint(usdcAmount));
            require(success, "Transfer USDC failed");
        }
        traderUSDTBalance[msg.sender] -= usdcAmount;
    }

    function lpDepositUSDT(int _usdcAmount) public {
        int tokenPrice = getTokenPrice();
        int tokenInc = (_usdcAmount * usdcDemical) / tokenPrice;
        liquidityPool.userDepositUSDT(_usdcAmount, tokenInc, msg.sender);
    }

    function createRandom(uint number) private view returns (int) {
        return int(uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % number);
    }

    // 期货价格保留两位小数
    function getFuturePrice() public view returns (int) {
        // (
        //     ,
        //     int price,
        //     ,
        //     uint timeStamp,
        // ) = priceProvider.latestRoundData();
        // // If the round is not complete yet, timestamp is 0
        // require(timeStamp > 0, "Round not complete");
        //return price;
        return (1450 + createRandom(50)) * (10 ** 2) + createRandom(99);
    }

    function traderOpenShortOrder(int marginAmount, int leverage) public {
        require(marginAmount > 0, "invalid marginAmount");
        require(leverage > 0, "invalid leverage");
        require(traderUSDTBalance[msg.sender] >= marginAmount, "insufficient user balance.");

        int futurePrice = getFuturePrice();
        int openOrderSize = leverageShort.userOpenOrder(marginAmount, leverage, futurePrice, msg.sender);
        emit openShortOrder(msg.sender, futurePrice, marginAmount, leverage, openOrderSize);
    }

    function traderCloseShortOrder(int closeTokenAmount) public {
        require(closeTokenAmount > 0, "invalid closeTokenAmount");
        int futurePrice = getFuturePrice();
        int profit = leverageShort.userCloseOrder(closeTokenAmount, futurePrice, msg.sender);
        emit closeShortOrder(msg.sender, futurePrice, profit);
    }
}
