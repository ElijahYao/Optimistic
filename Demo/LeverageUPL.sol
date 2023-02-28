// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


interface USDC {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract LeverageUPL {
    // Global
    address public owner;
    bool transferUSDC;
    USDC public USDCToken;
    AggregatorV3Interface internal priceProvider;
    bool isStarted;

    int public constant oraclePriceDemical = 10 ** 2;
    int public constant usdcDemical = 10 ** 6;

    // Trader 
    mapping (address => int) public userBalance;
    struct Position {
        int openPrice;
        int tokenAmount;
        int marginAmount; 
    }

    mapping (address => Position) public traderPosition;
    address[] public traderAddress;

    int public globalTokenAmount = 0;
    int public globalTokenValue = 0;
    
    // LP
    int public liquidityPoolTotalBalance;
    int public liquidityPoolLockedBalance;
    int public liquidityPoolTotalProfit = 0;
    mapping (address => int) public tokenBalance;
    mapping (address => int) public lpDepositAmount;
    int public totalTokenAmount = 0;

    constructor() {
        owner = msg.sender;
        transferUSDC = false; 
        priceProvider = AggregatorV3Interface(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);
        USDCToken = USDC(0x07865c6E87B9F70255377e024ace6630C1Eaa37F);
    }

    modifier isAdmin() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    // 计算全局的未实现盈亏
    function getGlobalUPL() public view returns (int) {
        // 所有仓位的开仓均价 
        int curFuturePrice = getFuturePrice();
        return curFuturePrice * globalTokenAmount - globalTokenValue;
    }

    function createRandom(uint number) private view returns(int){
        return int(uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % number);
    }

    // 期货价格保留两位小数
    function getFuturePrice() public view returns (int) {
        return (1450 + createRandom(50)) * (10 ** 2) + createRandom(99);
    }
    
    // 获取 Token 的价格, 10^6 
    function getTokenPrice() public view returns (int) {
        if (!isStarted) {
            return 1 * usdcDemical;
        }
        int globalUPL = getGlobalUPL();
        return (liquidityPoolTotalBalance - globalUPL) * usdcDemical / totalTokenAmount;
    }

    function getUserBalance(address user) public view returns (int) {
        require (user == msg.sender, "User is not caller");
        return userBalance[user];
    }

    // 用户充值。
    function userDeposit(int usdcAmount) public {
        require (usdcAmount >= 0, "Negative USDC amount");
        if (transferUSDC) {
            bool success = USDCToken.transferFrom(msg.sender, address(this), uint(usdcAmount));
            require (success, "Transfer USDC failed");
        }
        userBalance[msg.sender] += usdcAmount;
    }

    // 用户提款。
    function userWithdraw(int usdcAmount) public {
        require (usdcAmount >= 0, "Negative USDC amount");
        require (userBalance[msg.sender] >= usdcAmount, "Insufficient USDC balance");
        if (transferUSDC) {
            bool success = USDCToken.transfer(msg.sender, uint(usdcAmount));
            require (success, "Transfer USDC failed");
        }
        userBalance[msg.sender] -= usdcAmount;
    }

    // 用户开空仓。
    function userOpenOrder(int marginAmount, int leverage) public {
        require(marginAmount > 0, "invalid marginAmount");
        require(leverage > 0, "invalid leverage");
        require(liquidityPoolTotalBalance - liquidityPoolLockedBalance >= marginAmount * leverage, "insufficient liquidity supply.");        
        require(userBalance[msg.sender] >= marginAmount, "insufficient user balance.");

        userBalance[msg.sender] -= marginAmount;

        int currentOpenPrice = getFuturePrice();
        int currentTokenAmount = marginAmount * leverage / currentOpenPrice;

        int oldOpenPrice = traderPosition[msg.sender].openPrice;
        int oldTokenAmount = traderPosition[msg.sender].tokenAmount;
        int oldMarginAmount = traderPosition[msg.sender].marginAmount;

        traderPosition[msg.sender].openPrice = (oldOpenPrice * oldTokenAmount + currentOpenPrice * currentTokenAmount) / (oldTokenAmount + currentTokenAmount);
        traderPosition[msg.sender].tokenAmount = oldTokenAmount + currentTokenAmount;
        traderPosition[msg.sender].marginAmount = oldMarginAmount + marginAmount;

        // 处理全局 token 数量 + 全局 open price 计算
        globalTokenAmount += currentTokenAmount;
        globalTokenValue += traderPosition[msg.sender].openPrice * traderPosition[msg.sender].tokenAmount - oldOpenPrice * oldTokenAmount;

        liquidityPoolLockedBalance += traderPosition[msg.sender].openPrice * traderPosition[msg.sender].tokenAmount - oldOpenPrice * oldTokenAmount;

        traderAddress.push(msg.sender);
    }

    // 用户平空仓。
    function userCloseOrder(int closeTokenAmount) public {
        require (closeTokenAmount > 0);
        address trader = msg.sender; 

        require (traderPosition[trader].tokenAmount >= closeTokenAmount);

        int oldOpenPrice = traderPosition[trader].openPrice;
        int oldTokenAmount = traderPosition[trader].tokenAmount;
        int oldMarginAmount = traderPosition[trader].marginAmount;
        
        int currentPrice = getFuturePrice();
        int profit = (traderPosition[trader].openPrice - currentPrice) * closeTokenAmount / oraclePriceDemical;

        traderPosition[trader].tokenAmount = oldTokenAmount - closeTokenAmount;
        traderPosition[trader].marginAmount = oldMarginAmount * (oldTokenAmount - closeTokenAmount) / oldTokenAmount;

        int movedMariginAmount = oldMarginAmount - traderPosition[trader].marginAmount;

        require (movedMariginAmount + profit > 0);
        userBalance[trader] += movedMariginAmount + profit;

        globalTokenAmount -= closeTokenAmount;
        globalTokenValue -= closeTokenAmount * oldOpenPrice;

        liquidityPoolLockedBalance -= closeTokenAmount * oldOpenPrice;
        liquidityPoolTotalBalance -= profit;
        liquidityPoolTotalProfit -= profit;
    }

    // 用户增加保证金。
    function userAdjustMarginAmount(int marginAmount, bool inc) public {
        require (marginAmount > 0, "invalid margin amount");
        require (traderPosition[msg.sender].tokenAmount > 0, "invalid user position");
        if (inc) {
            require (userBalance[msg.sender] >= marginAmount);
            userBalance[msg.sender] -= marginAmount;
            traderPosition[msg.sender].marginAmount += marginAmount;
        } else {
            require (traderPosition[msg.sender].marginAmount >= 0);
            traderPosition[msg.sender].marginAmount -= marginAmount;
            userBalance[msg.sender] += marginAmount;
        }
    }

    function userExplode(address trader) public isAdmin {
        traderPosition[trader].tokenAmount = 0;
        traderPosition[trader].marginAmount = 0;
        traderPosition[trader].openPrice = 0;

        globalTokenAmount -= traderPosition[trader].tokenAmount;
        globalTokenValue -= traderPosition[trader].tokenAmount * traderPosition[trader].openPrice;
    }

    // 平台强制平仓。
    function userForceCloseOrder(int closeTokenAmount, int finalPrice, address trader) public isAdmin {
        require (closeTokenAmount > 0);
        require (traderPosition[trader].tokenAmount >= closeTokenAmount);

        int oldOpenPrice = traderPosition[trader].openPrice;
        int oldTokenAmount = traderPosition[trader].tokenAmount;
        int oldMarginAmount = traderPosition[trader].marginAmount;
        
        int currentPrice = finalPrice;
        int profit = (traderPosition[trader].openPrice - currentPrice) * closeTokenAmount;

        traderPosition[trader].tokenAmount = oldTokenAmount - closeTokenAmount;
        traderPosition[trader].marginAmount = oldMarginAmount * (oldTokenAmount - closeTokenAmount) / oldTokenAmount;

        int movedMariginAmount = oldMarginAmount - traderPosition[trader].marginAmount;

        require (movedMariginAmount + profit > 0);
        userBalance[trader] += movedMariginAmount + profit;

        liquidityPoolLockedBalance -= closeTokenAmount * oldOpenPrice;
        liquidityPoolTotalBalance -= profit;
        liquidityPoolTotalProfit -= profit;
    }

    function lpDeposit(int usdcAmount) public {
        require (usdcAmount > 0);
        if (transferUSDC) {
            bool success = USDCToken.transferFrom(msg.sender, address(this), uint(usdcAmount));
            require (success, "Transfer USDC failed");
        }
        // 当第一轮 epoch 未开始的时候, 价格 = 1usdt
        int tokenPrice = getTokenPrice(); 

        // 后续使用已实现盈亏进行计算
        liquidityPoolTotalBalance += usdcAmount;
        lpDepositAmount[msg.sender] += usdcAmount;
        int userTokenInc = usdcAmount * usdcDemical / tokenPrice;

        console.log("usdcAmount ", uint(usdcAmount));
        console.log("tokenPrice ", uint(tokenPrice));
        console.log("userTokenInc ", uint(userTokenInc));

        tokenBalance[msg.sender] += userTokenInc;
        totalTokenAmount += userTokenInc;
    }

    function lpWithDraw(int tokenAmount) public {
        require (isStarted == true); 
        require (tokenAmount > 0);
        require (tokenBalance[msg.sender] >= tokenAmount);
        
        int tokenPrice = getTokenPrice();
        int withdrawAmount = tokenAmount * tokenPrice / usdcDemical;

        console.log("tokenPrice ", uint(tokenPrice));
        console.log("withdrawAmount ", uint(withdrawAmount));

        require (withdrawAmount <= liquidityPoolTotalBalance - liquidityPoolLockedBalance);
        if (transferUSDC) {
            bool success = USDCToken.transfer(msg.sender, uint(withdrawAmount));
            require (success, "Transfer USDC failed");
        }
        liquidityPoolTotalBalance -= withdrawAmount;
        lpDepositAmount[msg.sender] -= withdrawAmount;
        tokenBalance[msg.sender] -= tokenAmount;
        totalTokenAmount -= tokenAmount;
    }

    function setStartStatus() public isAdmin {
        isStarted = true;
    }
}
