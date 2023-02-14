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

contract Leverage {

    // Global
    address public owner;
    bool transferUSDC;
    USDC public USDCToken;
    AggregatorV3Interface internal priceProvider;
    bool isStarted = false; 
    bool isSettled = false;

    int public constant oraclePriceDemical = 10 ** 2;

    // Trader 
    mapping (address => int) private userBalance;
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
    mapping (address => int) public shares;
    int public totalShares = 0;

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

        console.log("tmp3", uint(currentPrice));
        if (profit > 0) {
            console.log("positive", uint(profit));
        } else {
            console.log("negative", uint(-profit));
        }

        traderPosition[trader].tokenAmount = oldTokenAmount - closeTokenAmount;
        traderPosition[trader].marginAmount = oldMarginAmount * (oldTokenAmount - closeTokenAmount) / oldTokenAmount;

        int movedMariginAmount = oldMarginAmount - traderPosition[trader].marginAmount;

        require (movedMariginAmount + profit > 0);
        userBalance[trader] += movedMariginAmount + profit;

        liquidityPoolLockedBalance -= closeTokenAmount * oldOpenPrice;
        liquidityPoolTotalBalance -= profit;
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

    function lpDeposit(int usdcAmount) public {
        require (isStarted == false);
        require (usdcAmount > 0);
        if (transferUSDC) {
            bool success = USDCToken.transferFrom(msg.sender, address(this), uint(usdcAmount));
            require (success, "Transfer USDC failed");
        }
        shares[msg.sender] += usdcAmount;
        liquidityPoolTotalBalance += usdcAmount;
        totalShares += usdcAmount;
        // 最终用结算时用 shares[msg.sender] / totalShares 算每个人的份额
    }

    function lpWithDraw() public {
        require (isSettled == true);
        int withdrawAmount = liquidityPoolTotalBalance * shares[msg.sender] / totalShares;
        if (transferUSDC) {
            bool success = USDCToken.transfer(msg.sender, uint(withdrawAmount));
            require (success, "Transfer USDC failed");
        }
        totalShares -= shares[msg.sender];
    }

    function setSettleStatus() public isAdmin {
        isSettled = true;
    }

    function setStartStatus() public isAdmin {
        isStarted = true;
    }

}
