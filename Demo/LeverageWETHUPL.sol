// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


interface ERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract LeverageToken {

    // Global
    address public owner;
    bool transferWETH;
    ERC20 public WETHToken;
    AggregatorV3Interface internal priceProvider;
    bool isStarted;

    int public constant oraclePriceDemical = 10 ** 2;
    int public constant gweiDemical = 10 ** 9;

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
        transferWETH = false; 
        priceProvider = AggregatorV3Interface(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);
        WETHToken = ERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);
    }

    modifier isAdmin() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    function createRandom(uint number) private view returns(int){
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


    function getGlobalUPL() public view returns (int) {

        int globalOpenPrice = globalTokenValue / globalTokenAmount;
        int currentPrice = getFuturePrice();
        console.log("globalOpenPrice ", uint(globalOpenPrice));
        int profit = globalTokenAmount * (10 ** 9) / globalOpenPrice - globalTokenAmount * (10 ** 9) / currentPrice;
        return profit;
    }
    

    // 获取 Token 的价格, 10^6 
    function getTokenPrice() public view returns (int) {
        if (!isStarted || totalTokenAmount == 0) {
            return 1 * gweiDemical;
        }
        return (liquidityPoolTotalBalance - getGlobalUPL()) * gweiDemical / totalTokenAmount;
    }

    function getUserBalance(address user) public view returns (int) {
        require (user == msg.sender, "User is not caller");
        return userBalance[user];
    }

    // 用户充值。
    function userDeposit(int wethAmount) public {
        require (wethAmount >= 0, "Negative WETH amount");
        if (transferWETH) {
            bool success = WETHToken.transferFrom(msg.sender, address(this), uint(wethAmount));
            require (success, "Transfer WETH failed");
        }
        userBalance[msg.sender] += wethAmount;
    }

    // 用户提款。
    function userWithdraw(int wethAmount) public {
        require (wethAmount >= 0, "Negative WETH amount");
        require (userBalance[msg.sender] >= wethAmount, "Insufficient WETH balance");
        if (transferWETH) {
            bool success = WETHToken.transfer(msg.sender, uint(wethAmount));
            require (success, "Transfer WETH failed");
        }
        userBalance[msg.sender] -= wethAmount;
    }

    // 用户开空仓。
    // marginAmount: ETH 数量, 单位 GWEI
    // leveage: 杠杆倍数
    // 1张面值: 0.01 USDT
    function userOpenOrder(int marginAmount, int leverage, int openPrice) public {
        require(marginAmount > 0, "invalid marginAmount");
        require(leverage > 0, "invalid leverage");
        require(liquidityPoolTotalBalance - liquidityPoolLockedBalance >= marginAmount * leverage, "insufficient liquidity supply.");        
        require(userBalance[msg.sender] >= marginAmount, "insufficient user balance.");

        userBalance[msg.sender] -= marginAmount;

        int currentOpenPrice = getFuturePrice(); 
        // int currentOpenPrice = openPrice; // for test 
        int currentTokenAmount = marginAmount * leverage * currentOpenPrice / (10 ** 9);

        console.log("currentOpenPrice ", uint(currentOpenPrice));
        console.log("currentTokenAmount", uint(currentTokenAmount));

        int oldOpenPrice = traderPosition[msg.sender].openPrice;
        int oldTokenAmount = traderPosition[msg.sender].tokenAmount;
        int oldMarginAmount = traderPosition[msg.sender].marginAmount;

        if (oldTokenAmount == 0) {
            traderPosition[msg.sender].openPrice = currentOpenPrice;
        } else {
            traderPosition[msg.sender].openPrice = (currentOpenPrice * currentTokenAmount + oldOpenPrice * oldTokenAmount) / (currentTokenAmount + oldTokenAmount);
        }

        traderPosition[msg.sender].tokenAmount = oldTokenAmount + currentTokenAmount;
        traderPosition[msg.sender].marginAmount = oldMarginAmount + marginAmount;

        int maxProfit = traderPosition[msg.sender].tokenAmount * (10 ** 9) / traderPosition[msg.sender].openPrice;


        // LP 增加的数额
        int incLockedBalance = oldTokenAmount == 0 ? maxProfit : maxProfit - oldTokenAmount * (10 ** 9) / oldOpenPrice;
        console.log("maxProfit ", uint(maxProfit));
        console.log("incLockedBalance", uint(incLockedBalance));

        globalTokenAmount += currentTokenAmount;
        globalTokenValue += traderPosition[msg.sender].openPrice * traderPosition[msg.sender].tokenAmount - oldOpenPrice * oldTokenAmount;

        // 仓位最大利润计算
        liquidityPoolLockedBalance += incLockedBalance;
    }

    // 用户平空仓。
    // closeTokenAmount: 平仓数量
    function userCloseOrder(int closeTokenAmount, int closePrice) public {
        require (closeTokenAmount > 0);
        address trader = msg.sender; 

        require (traderPosition[trader].tokenAmount >= closeTokenAmount);

        int oldOpenPrice = traderPosition[trader].openPrice;
        int oldTokenAmount = traderPosition[trader].tokenAmount;
        int oldMarginAmount = traderPosition[trader].marginAmount;
        int oldMaxProfit = oldTokenAmount * (10 ** 9) / traderPosition[msg.sender].openPrice;
        
        int currentPrice = getFuturePrice();
        // int currentPrice = closePrice;  // for test.
        int profit = traderPosition[msg.sender].tokenAmount * (10 ** 9) / traderPosition[msg.sender].openPrice - traderPosition[msg.sender].tokenAmount * (10 ** 9) / currentPrice;

        if (profit > 0) {
            console.log("Position Profit +", uint(profit));
        } else {
            console.log("Position Profit -", uint(-profit));
        }
        console.log("Position MarginAmount", uint(traderPosition[trader].marginAmount));

        // 判断是否爆仓
        if (profit + traderPosition[trader].marginAmount <= 0) {
            userExplode(trader);
            liquidityPoolLockedBalance -= oldMaxProfit;
            liquidityPoolTotalBalance += oldMarginAmount;
            liquidityPoolTotalProfit += oldMarginAmount;
            // 爆仓默认把所有仓位都平
            globalTokenAmount -= oldTokenAmount;
            globalTokenValue -= oldTokenAmount * oldOpenPrice;
        } else {
            traderPosition[trader].tokenAmount = oldTokenAmount - closeTokenAmount;
            traderPosition[trader].marginAmount = oldMarginAmount * (oldTokenAmount - closeTokenAmount) / oldTokenAmount;
            // 平仓的利润
            int value = closeTokenAmount * (10 ** 9) / traderPosition[msg.sender].openPrice - closeTokenAmount * (10 ** 9) / currentPrice;
            console.log("Close order token amount ", uint(closeTokenAmount));
            if (value >= 0) {
                console.log("Close order gain positive:  +", uint(value));
            } else {
                console.log("Close order gain negative:  -", uint(-value));
            }
            int movedMariginAmount = oldMarginAmount - traderPosition[trader].marginAmount;
            int incBalance = movedMariginAmount + value; 

            userBalance[trader] += incBalance;

            int curMaxProfit = traderPosition[trader].tokenAmount * (10 ** 9) / traderPosition[msg.sender].openPrice;

            liquidityPoolLockedBalance -= oldMaxProfit - curMaxProfit;
            liquidityPoolTotalBalance -= value;
            liquidityPoolTotalProfit -= value;

            globalTokenAmount -= closeTokenAmount;
            globalTokenValue -= closeTokenAmount * oldOpenPrice;

            if (traderPosition[trader].tokenAmount == 0) {
                traderPosition[trader].openPrice = 0;
            }
        }
    }

    function userExplode(address trader) public isAdmin {
        traderPosition[trader].tokenAmount = 0;
        traderPosition[trader].marginAmount = 0;
        traderPosition[trader].openPrice = 0;
    }

    function lpDeposit(int wethAmount) public {
        require (wethAmount > 0, "invalid weth amount");
        if (transferWETH) {
            bool success = WETHToken.transferFrom(msg.sender, address(this), uint(wethAmount));
            require (success, "Transfer WETH failed");
        }
        // 当第一轮 epoch 未开始的时候, 价格 = 1usdt
        int tokenPrice = getTokenPrice(); 

        // 后续使用已实现盈亏进行计算
        liquidityPoolTotalBalance += wethAmount;
        lpDepositAmount[msg.sender] += wethAmount;
        int userTokenInc = wethAmount * gweiDemical / tokenPrice;

        console.log("wethAmount ", uint(wethAmount));
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
        int withdrawAmount = tokenAmount * tokenPrice / gweiDemical;

        console.log("tokenPrice ", uint(tokenPrice));
        console.log("withdrawAmount ", uint(withdrawAmount));

        require (withdrawAmount <= liquidityPoolTotalBalance - liquidityPoolLockedBalance);
        if (transferWETH) {
            bool success = WETHToken.transfer(msg.sender, uint(withdrawAmount));
            require (success, "Transfer WETH failed");
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
