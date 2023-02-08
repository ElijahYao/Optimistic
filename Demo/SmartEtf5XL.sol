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

contract SmartETF {

    address public owner;
    bool isStarted;

    RebalanceRecords[] public rebalanceRecords;
    mapping (address => int) private traderPositions;
    mapping (address => int) private userBalance;

    USDC public USDCToken;

    int public lastIndexPrice; 
    int public lastETFPrice;
    int public totalTransactionFee; 

    int multiplier;
    bool transferUSDC;

    AggregatorV3Interface internal priceProvider;

    int private immutable ratioPricesion = 10 ** 6; 
    int private immutable minimumETFPrice = 8 * (10 ** 2);
    int private immutable initETFPrice = 10 ** 6;

    struct RebalanceRecords {
        uint timestamp;
        int indexPrice;
        int ETFPrice; 
    }

    constructor(int _multiplier) {
        require(_multiplier >= 3, "Invalid multiplier");
        owner = msg.sender;
        isStarted = false;
        transferUSDC = false;
        multiplier = _multiplier; 
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

    function getFuturePrice() public view returns (int) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceProvider.latestRoundData();
        // If the round is not complete yet, timestamp is 0
        require(timeStamp > 0, "Round not complete");
        return price;
        // return 1200 + createRandom(50);
    }

    // public funcs
    function getUserBalance(address user) public view returns (int) {
        require (user == msg.sender, "User is not caller");
        return userBalance[user];
    }

    function getUserPosition(address user) public view returns (int) {
        require (user == msg.sender, "User is not caller");
        return traderPositions[user];
    }

    function getCurrentETFPrice() public view returns (int) {

        int futurePrice = getFuturePrice();

        // 价格涨幅, 按照 10^6 精度计算, 
        int priceChangeRatio = futurePrice * ratioPricesion / lastIndexPrice - ratioPricesion;

        // currentETFPrice = lastETFPrice * (1 + multiplier * priceChangeRatio / ratioPricesion)
        int currentETFPrice = lastETFPrice + lastETFPrice * multiplier * priceChangeRatio / ratioPricesion;
        if (currentETFPrice <= 0) {
            currentETFPrice = minimumETFPrice;
        }
        // console.log("futurePrice=", uint(futurePrice));
        // if (priceChangeRatio >= 0) {
        //     console.log("Positive priceChangeRatio", uint(priceChangeRatio));
        // } else {
        //     console.log("Negative priceChangeRatio", uint(-priceChangeRatio));
        // }
        // console.log("currentETFPrice=", uint(currentETFPrice));
        return currentETFPrice;
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

    // 用户购买 ETF。
    function userBuy(int usdcAmount) public {
        int currentETFPrice = getCurrentETFPrice();
        require (userBalance[msg.sender] >= usdcAmount, "Insufficient USDC balance");
        require (usdcAmount >= currentETFPrice, "Insuffcient USDC");
        int etfAmount = usdcAmount / currentETFPrice;
        traderPositions[msg.sender] += etfAmount;
        userBalance[msg.sender] -= etfAmount * currentETFPrice;
    }

    // 用户赎回 ETF。
    function userSell(int etfAmount) public {
        require (etfAmount > 0, "Negative ETF amount");
        int currentETFPrice = getCurrentETFPrice();
        require (traderPositions[msg.sender] >= etfAmount, "Insufficient ETF position");
        traderPositions[msg.sender] -= etfAmount;
        int transactionFee = etfAmount * currentETFPrice * 5 / 1000;
        totalTransactionFee += transactionFee;
        userBalance[msg.sender] += etfAmount * currentETFPrice - transactionFee;
    }

    // 记录新的锚定价格, 当前的锚定价格对应的 ETF 价格。
    function reBalance() public isAdmin {

        RebalanceRecords memory r;
        r.timestamp = block.timestamp;
        r.indexPrice = lastIndexPrice;
        r.ETFPrice = lastETFPrice;

        lastETFPrice = getCurrentETFPrice();
        lastIndexPrice = getFuturePrice();
        
        rebalanceRecords.push(r);
    }

    // 开始做市
    function startMarketing() public isAdmin {
        isStarted = true;
        lastETFPrice = initETFPrice;
        lastIndexPrice = getFuturePrice();
    }
}
