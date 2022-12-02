// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Optimistic {

    address public owner;
    uint initialNumber = 0;

    // LP investors related
    // 当前资金池
    mapping (address => int) public LiquidityPool;
    int public totalBalance;
    int public curRoundLockedBalance = 0;
    address[] investors;

    // 新一轮存款请求
    mapping (address => int) public newDepositAmount;
    address[] newDepositers;

    // 新一轮提款请求
    mapping (address => int) public newWithdraAmount;
    address[] newWithdrawers;

    uint public roundId;
    int public profit;

    uint curProfitRound;
    uint curSettleRound;
    uint curDepositRound;

    uint256 curEpochStartTime;
    uint256 curEpochEndTime;
    int256 public maxStrikePrice;
    int256 public minStrikePrice;

    // Traders related
    int256 traderPool = 0;
    struct Option {
        int strikePrice;
        uint strikeTime;
        bool optionType;
    }

    struct OptionOrder {
        Option option;
        int orderSize;
        int settlevalue;
        string status;
    }

    int public immutable PRICEDEMICAL = int256(1e8);
    int public immutable PRICEGAP = int256(1e2);

    AggregatorV3Interface internal priceFeed;
    mapping (uint => Option[]) public opitonProducts;
    mapping (address => mapping (uint => OptionOrder[])) public traderOptionOrders;

    mapping (address => uint) curEpochTraderOrderLength;
    address[] curEpochTraders;

    // Ends
    modifier isOwner() {
        require(msg.sender == owner, "caller is not owner");
        _;
    }

    modifier runningEpoch() {
        require (roundId == curProfitRound + 1 && curProfitRound == curSettleRound && curSettleRound == curDepositRound, "there is no epoch active.");
        _;
    }

    constructor() {
        owner = msg.sender;
        roundId = 0;
        totalBalance = 0;
        curSettleRound = 0;
        curProfitRound = 0;
        curDepositRound = 0;
        profit = 0;
        priceFeed = AggregatorV3Interface(
            0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
        );
    }
    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (int) {
        // (
        //     ,
        //     /*uint80 roundID*/ int price /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
        //     ,
        //     ,

        // ) = priceFeed.latestRoundData();
        // return price;
        return 1205 * PRICEDEMICAL;
    }

    function getNow() public view returns (uint256) {
        return block.timestamp;
    }

    function createRandom(uint number) public view returns(int){
        return int(uint(keccak256(abi.encodePacked(block.timestamp,block.difficulty,  
        msg.sender))) % number);
    }

    function curInvestorExist(address sender) public view returns (bool) {
        for (uint i = 0; i < investors.length; i++) {
            if (investors[i] == sender) {
                return true;
            }
        }
        return false;
    }

    function deposit(int _amount) public{
        require (roundId == curProfitRound + 1 || roundId == 0, "invalid deposit time");
        require(_amount >= 100, "greater then 100 USDC.");

        _amount = _amount * PRICEDEMICAL;
        if (newDepositAmount[msg.sender] == 0) {
            newDepositers.push(msg.sender);
        }
        newDepositAmount[msg.sender] += _amount;
    }

    function withdraw(int _amount) public {
        require (roundId == curProfitRound + 1, " invalid withdraw time.");
        _amount = _amount * PRICEDEMICAL;
        if (newWithdraAmount[msg.sender] == 0) {
            newWithdrawers.push(msg.sender);
        }
        newWithdraAmount[msg.sender] += _amount;
    }

    function getOptionPrice() public view returns (int) {
        return (createRandom(96) + 5) * PRICEDEMICAL / 100;
    }

    function buy(uint strikeTime, int strikePrice, bool optionType, uint produtRoundId, int _amount) public runningEpoch {
        require (roundId >= 1 && roundId == produtRoundId, "roundId invalid.");
        require (strikeTime >= curEpochStartTime && strikeTime <= curEpochEndTime, "strikeTime invalid.");
        require (strikeTime > getNow(), "strikeTime invalid.");
        require (strikePrice >= minStrikePrice && strikePrice <= maxStrikePrice, "strikePrice invalid.");
        require (_amount >= 50, "_amount invalid.");
        traderPool += _amount * PRICEDEMICAL;
        int optionPrice = getOptionPrice();

        console.log("optionPrice :", uint(optionPrice));
        console.log("_amount : ", uint(_amount * PRICEDEMICAL));

        int orderSize = (_amount * PRICEDEMICAL) / optionPrice;
        require (orderSize > 0, "orderSize smaller than 1.");
        require (totalBalance - curRoundLockedBalance >= orderSize * PRICEDEMICAL);
        curRoundLockedBalance += orderSize * PRICEDEMICAL;

        console.log("orderSize", uint(orderSize));

        Option memory option;
        option.strikePrice = strikePrice;
        option.strikeTime = strikeTime;
        option.optionType = optionType;

        OptionOrder memory optionOrder;
        optionOrder.option = option;
        optionOrder.orderSize = orderSize;
        optionOrder.status = "opened";

        traderOptionOrders[msg.sender][roundId].push(optionOrder);
        if (curEpochTraderOrderLength[msg.sender] == 0) {
            curEpochTraders.push(msg.sender);
        }
        curEpochTraderOrderLength[msg.sender] += 1;
        profit += _amount * PRICEDEMICAL;
    }

    // 计算当前 EPOCH 的期权利润。
    function calculateTraderProfits() public isOwner {
        require (roundId == curProfitRound + 1);
        require (curProfitRound == curSettleRound && curProfitRound == curDepositRound);
        
        int settlePrice = (1105 + createRandom(200)) * PRICEDEMICAL;
        console.log("roundId:", roundId, " settlePrice:", uint(settlePrice));

        curProfitRound = roundId;
        for (uint i = 0; i < curEpochTraders.length; ++i) {
            address trader = curEpochTraders[i];
            uint orderNum = curEpochTraderOrderLength[trader];
            for (uint j = 0; j < orderNum; ++j) {
            
                traderOptionOrders[trader][roundId][j].status = "settled";

                bool optionType = traderOptionOrders[trader][roundId][j].option.optionType;
                int orderSize = traderOptionOrders[trader][roundId][j].orderSize;

                if (optionType == true) {
                    if (settlePrice >= traderOptionOrders[trader][roundId][j].option.strikePrice) {
                        profit -= orderSize * PRICEDEMICAL;
                        console.log("Value=1, orderNum=", j, "strikePrice=", uint(traderOptionOrders[trader][roundId][j].option.strikePrice));
                    } else {
                        console.log("Value=0, orderNum=", j, "strikePrice=", uint(traderOptionOrders[trader][roundId][j].option.strikePrice));
                    }
                } else {
                    if (settlePrice <= traderOptionOrders[trader][roundId][j].option.strikePrice) {
                        profit -= orderSize * PRICEDEMICAL;
                        console.log("Value=1, orderNum=", j, "strikePrice=", uint(traderOptionOrders[trader][roundId][j].option.strikePrice));
                    } else {
                        console.log("Value=0, orderNum=", j, "strikePrice=", uint(traderOptionOrders[trader][roundId][j].option.strikePrice));
                    }
                }
            }
            curEpochTraderOrderLength[trader] = 0;
        }
        curEpochTraders = new address[](0);
    }

    // 对当前 EPOCH 的 invesotrs 的利润进行结算。
    function handleSettlement() public isOwner {
        require (roundId == curProfitRound && curProfitRound == curSettleRound + 1 && curSettleRound == curDepositRound);
        int curRoundProfit = profit;
        // 根据这一轮的 Profit 计算新的 Balance 对于每个投资人。
        int newTotalBalance = 0;
        console.log("investor length:", investors.length);
        for (uint i = 0; i < investors.length; ++i) {    
            address investor = investors[i];
            console.log("investor addr:", investor);
            console.log("investor lp amount origin:", uint(LiquidityPool[investor]));
            LiquidityPool[investor] = LiquidityPool[investor] + curRoundProfit * LiquidityPool[investor] / totalBalance;
            if (LiquidityPool[investor] < 0) {
                LiquidityPool[investor] = 0;
            }
            console.log("investor lp amount updated:", uint(LiquidityPool[investor]));
            if (newWithdraAmount[investor] > 0) {
                if (LiquidityPool[investor] >= newWithdraAmount[investor]) {
                    LiquidityPool[investor] -= newWithdraAmount[investor];
                }
                delete newWithdraAmount[investor];
            }
            newTotalBalance += LiquidityPool[investor];
        }
        newWithdrawers = new address[](0);
        curSettleRound = curProfitRound;
        totalBalance = newTotalBalance;
        curRoundLockedBalance = 0;
    }

    // 当前 EPOCH 结束时, 处理新的 investors 的请求。
    function handleDepositRequest() public isOwner {
        require (roundId == curProfitRound && curProfitRound == curSettleRound && curSettleRound == curDepositRound + 1);
        int256 newTotalBalance = totalBalance;
        for (uint i = 0; i < newDepositers.length; ++i) {
            address depositer = newDepositers[i];
            LiquidityPool[depositer] += newDepositAmount[depositer];
            newDepositAmount[depositer] = 0;
            if (curInvestorExist(depositer) == false) {
                investors.push(depositer);
            }
            newTotalBalance += LiquidityPool[depositer];
            delete newDepositAmount[depositer];
        }
        newDepositers = new address[](0);
        curDepositRound = curSettleRound;
        totalBalance = newTotalBalance;
    }

    // 处理第一轮的投资请求, 计算 totalBalance, 
    function handleFirstDepositProcess() private isOwner {
        require (roundId == 0, "this is not first deposit process");
        int startingBalance = 0;
        for (uint i = 0; i < newDepositers.length; ++i) {
            address depositer = newDepositers[i];
            int256 depostAmount = newDepositAmount[depositer];
            LiquidityPool[depositer] = depostAmount;
            newDepositAmount[depositer] = 0;
            startingBalance += depostAmount;
            delete newDepositAmount[depositer];
            investors.push(depositer);
        }
        newDepositers = new address[](0);
        totalBalance = startingBalance;
    }

    function startNewEpoch(uint256 period) public isOwner {
        require (roundId == curProfitRound && roundId == curSettleRound && roundId == curDepositRound, "invalid roundId.");
        require (period == 10 * 60);
        curEpochStartTime = getNow();
        curEpochEndTime = curEpochStartTime + period;
        int lastRoundPrice = getLatestPrice();
        maxStrikePrice = 130 * lastRoundPrice / 100;
        minStrikePrice = 70 * lastRoundPrice / 100;
        console.log("curEpoch start time:", curEpochStartTime);
        console.log("curEpoch end time:", curEpochEndTime);
        if (roundId == 0) {
            handleFirstDepositProcess();
        }
        // 获取预言机的价格, 制定期权产品。
        roundId += 1;
        profit = 0;
    }
}
