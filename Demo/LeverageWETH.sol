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
    int public constant wethDemical = 10 ** 18;
    int public constant gweiDemical = 10 ** 10;

    // Trader 
    mapping (address => int) public userBalance;
    struct Position {
        int openPrice;
        int tokenAmount;
        int marginAmount; 
    }

    mapping (address => Position) public traderPosition;
    address[] public traderAddress;
    
    // LP
    int public liquidityPoolTotalBalance;
    int public liquidityPoolLockedBalance;
    mapping (address => int) public tokenBalance;
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
    

    // 获取 Token 的价格, 10^6 
    function getTokenPrice() public view returns (int) {
        if (!isStarted) {
            return 1 * wethDemical * gweiDemical;
        }
        return liquidityPoolTotalBalance * wethDemical / totalTokenAmount;
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

        liquidityPoolLockedBalance -= closeTokenAmount * oldOpenPrice;
        liquidityPoolTotalBalance -= profit;
    }

    function userExplode(address trader) public isAdmin {
        traderPosition[trader].tokenAmount = 0;
        traderPosition[trader].marginAmount = 0;
        traderPosition[trader].openPrice = 0;
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
    }

    function lpDeposit(int wethAmount) public {
        require (wethAmount > 0);
        if (transferWETH) {
            bool success = WETHToken.transferFrom(msg.sender, address(this), uint(wethAmount));
            require (success, "Transfer WETH failed");
        }
        // 当第一轮 epoch 未开始的时候, 价格 = 1usdt
        int tokenPrice = getTokenPrice(); 

        // 后续使用已实现盈亏进行计算
        liquidityPoolTotalBalance += wethAmount;
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
        tokenBalance[msg.sender] -= tokenAmount;
        totalTokenAmount -= tokenAmount;
    }

    function setStartStatus() public isAdmin {
        isStarted = true;
    }
}
