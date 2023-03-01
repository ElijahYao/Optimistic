// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "contracts/OptimisticV3/LiquidityPool.sol";

contract LeverageShort {
    // Global
    address public owner;
    bool transferUSDC;

    LiquidityPool public immutable liquidityPool;
    int public constant oraclePriceDemical = 10 ** 2;
    int public constant usdcDemical = 10 ** 6;

    // Trader 
    struct Position {
        int openPrice;
        int tokenAmount;
        int marginAmount; 
    }

    mapping (address => Position) public traderPosition;

    int public globalTokenAmount = 0;
    int public globalTokenValue = 0;
    
    constructor() {
        owner = msg.sender;
        transferUSDC = false;
        liquidityPool = LiquidityPool(0xd9145CCE52D386f254917e481eB44e9943F39138);
    }

    modifier isAdmin() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    // 计算全局 LP 的未实现盈亏
    function getGlobalUPL(int futurePrice) public view returns (int) {
        return futurePrice * globalTokenAmount - globalTokenValue;
    }

    // 用户开空仓。
    function userOpenOrder(int marginAmount, int leverage, int futurePrice, address trader) public returns (int) {
        
        require(liquidityPool.totalUSDT() - liquidityPool.lockedUSDT() >= marginAmount * leverage, "insufficient liquidity supply.");
        int currentOpenPrice = futurePrice;
        int currentTokenAmount = marginAmount * leverage / currentOpenPrice;

        int oldOpenPrice = traderPosition[trader].openPrice;
        int oldTokenAmount = traderPosition[trader].tokenAmount;
        int oldMarginAmount = traderPosition[trader].marginAmount;

        traderPosition[trader].openPrice = (oldOpenPrice * oldTokenAmount + currentOpenPrice * currentTokenAmount) / (oldTokenAmount + currentTokenAmount);
        traderPosition[trader].tokenAmount = oldTokenAmount + currentTokenAmount;
        traderPosition[trader].marginAmount = oldMarginAmount + marginAmount;

        // 处理全局 token 数量 + 全局 open price 计算
        globalTokenAmount += currentTokenAmount;
        globalTokenValue += traderPosition[trader].openPrice * traderPosition[trader].tokenAmount - oldOpenPrice * oldTokenAmount;

        liquidityPool.lockLiquidityUSDT(traderPosition[trader].openPrice * traderPosition[trader].tokenAmount - oldOpenPrice * oldTokenAmount);

        return currentTokenAmount;
    }

    // 用户平空仓。
    function userCloseOrder(int closeTokenAmount, int futurePrice, address trader) public returns (int) {
        require (traderPosition[trader].tokenAmount >= closeTokenAmount, "invalid closeTokenAmount.");

        int oldOpenPrice = traderPosition[trader].openPrice;
        int oldTokenAmount = traderPosition[trader].tokenAmount;
        int oldMarginAmount = traderPosition[trader].marginAmount;
        
        int currentPrice = futurePrice;
        int positionProfit = (traderPosition[trader].openPrice - currentPrice) * oldTokenAmount;

        // 用户爆仓, 不需要给他的 balance 转账。
        if (positionProfit + oldMarginAmount <= 0) {

            globalTokenAmount -= oldTokenAmount;
            globalTokenValue -= oldTokenAmount * oldOpenPrice;

            liquidityPool.unlockLiquidityUSDT(oldTokenAmount * oldOpenPrice);
            liquidityPool.updatePoolUSDT(oldMarginAmount);

            resetPosition(trader);
            return 0;

        } else {

            int profit = (traderPosition[trader].openPrice - currentPrice) * closeTokenAmount;

            traderPosition[trader].tokenAmount = oldTokenAmount - closeTokenAmount;
            traderPosition[trader].marginAmount = oldMarginAmount * (oldTokenAmount - closeTokenAmount) / oldTokenAmount;

            int movedMariginAmount = oldMarginAmount - traderPosition[trader].marginAmount;

            globalTokenAmount -= closeTokenAmount;
            globalTokenValue -= closeTokenAmount * oldOpenPrice;

            liquidityPool.unlockLiquidityUSDT(closeTokenAmount * oldOpenPrice);
            liquidityPool.updatePoolUSDT(profit);

            if (traderPosition[trader].tokenAmount == 0) {
                resetPosition(trader);
            }
            return movedMariginAmount + profit;
        }
    }

    function resetPosition(address trader) private {
        traderPosition[trader].tokenAmount = 0;
        traderPosition[trader].marginAmount = 0;
        traderPosition[trader].openPrice = 0;
    }
}
