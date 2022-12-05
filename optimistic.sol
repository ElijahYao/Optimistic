// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface USDC {

    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

}

contract Optimistic {
    USDC public usdc_service;
    // Global
    address public owner;
    uint public epochId;
    uint initialNumber = 0;

    bool transferUSDC = false;

    // Epoch 相关变量 
    int public curEpochTotalProfit;                         // 当前 Epoch 利润

    uint curProfitEpoch;                                    // 当前 Traders 利润结算计算完成的 EpochId
    uint curSettleEpoch;                                    // 当前 LP investors 资金结算完成的 EpochId
    uint curDepositEpoch;                                   // 当前 LP investors 处理完新请求的 EpochId

    uint256 public curEpochStartTime;                       // 当前 Epoch 开始时间。
    uint256 public curEpochEndTime;                         // 当前 Epoch 结束时间。
    int256 public maxStrikePrice;                           // 当前 Epoch 售卖期权的最高的行权价格。
    int256 public minStrikePrice;                           // 当前 Epoch 售卖期权的最低的行权价格。

    // LP investors 资金池相关变量
    // 当前资金池, 新一轮存款请求, 新一轮提款请求
    mapping (address => int) public liquidityPool;          // 资金池 addr -> USDC 数量
    mapping (address => int) public investorsWithdrawPool;           // 提款池 addr -> USDC 数量
    mapping (address => int) public newDepositRequest;      // 存款请求 addr -> USDC 数量
    mapping (address => int) public newWithdraRequest;      // 提款请求 addr -> USDC 数量

    int public totalBalance;                                // 资金池 USDC 数量
    int public curRoundLockedBalance = 0;                   // 当前交易周期锁定 USDC 数量
    address[] investors;                                    // 当前交易周期 LP 列表
    address[] newDepositers;                                // 当前交易周期新存款者列表
    address[] newWithdrawers;                               // 当前交易周期新提款

    // traders 相关变量
    int256 traderPool = 0;
    struct Option {
        int strikePrice;
        uint strikeTime;
        bool optionType;
    }
    struct OptionOrder {
        Option option;
        int orderSize;
        string status;
    }

    int public immutable PRICEDEMICAL = int(1e8);
    int public immutable USDCDEMICAL = int(1e6);
    int public immutable PRICEGAP = int(1e2);

    AggregatorV3Interface internal priceFeed;
    mapping (address => mapping (uint => OptionOrder[])) public traderOptionOrders;
    mapping (address => uint) curEpochTraderOrderLength;
    mapping (address => int) traderProfitPool;

    address[] curEpochTraders;

    // Optimistic 定义变量
    uint public optimisticBalance;

    // Ends
    modifier isOwner() {
        require(msg.sender == owner, "caller is not owner");
        _;
    }

    modifier runningEpoch() {
        require (epochId == curProfitEpoch + 1 && curProfitEpoch == curSettleEpoch && curSettleEpoch == curDepositEpoch, "there is no epoch active.");
        _;
    }

    constructor() {
        owner = msg.sender;
        epochId = 0;
        totalBalance = 0;
        curSettleEpoch = 0;
        curProfitEpoch = 0;
        curDepositEpoch = 0;
        curEpochTotalProfit = 0;
        priceFeed = AggregatorV3Interface(
            0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
        );
        optimisticBalance = 0;
        usdc_service = USDC(0x07865c6E87B9F70255377e024ace6630C1Eaa37F);
        transferUSDC=false;
    }
    
    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (int) {
        // (
        //     ,
        //     /*uint80 epochId*/ int price /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
        //     ,
        //     ,

        // ) = priceFeed.latestRoundData();
        // return price;
        return 1205 * PRICEDEMICAL;
    }
    function getNow() public view returns (uint) {
        return block.timestamp;
    }

    function createRandom(uint number) public view returns(int){
        return int(uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % number);
    }

    function compareStrings(string memory a, string memory b) public view returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function curInvestorExist(address sender) public view returns (bool) {
        for (uint i = 0; i < investors.length; i++) {
            if (investors[i] == sender) {
                return true;
            }
        }
        return false;
    }

    function optimisticDeposit(int _amount) public isOwner{
        return ;
    }

    function traderWithdraw(int _amount) public {
        require (traderProfitPool[msg.sender] >= 0, "no profit");
        require (_amount * USDCDEMICAL <= traderProfitPool[msg.sender], "insufficient profit");
        if (transferUSDC) {
            bool success = usdc_service.transfer(msg.sender, uint(_amount * USDCDEMICAL));
            require(success, "error transfer usdc");
        }
        traderProfitPool[msg.sender] -= _amount * USDCDEMICAL;
    }

    function investorDeposit(int _amount) public {
        require ((epochId == curProfitEpoch + 1 && curProfitEpoch == curSettleEpoch && curSettleEpoch == curDepositEpoch) || epochId == 0, "invalid deposit time, current epoch is settling.");
        require(_amount >= 100, "invest amount less than 100 USDC.");
        _amount = _amount * USDCDEMICAL;
        uint256 balance = usdc_service.balanceOf(msg.sender);
        require(balance >= uint(_amount), "insufficient token");
        if (transferUSDC) {
            bool success = usdc_service.transferFrom(msg.sender, address(this), uint(_amount));
            require(success, "error transfer usdc");
        }
        if (newDepositRequest[msg.sender] == 0) {
            newDepositers.push(msg.sender);
        }
        newDepositRequest[msg.sender] += _amount;
        
    }

    function investorWithDraw(int _amount) public {
        require ((epochId == curProfitEpoch + 1 && curProfitEpoch == curSettleEpoch && curSettleEpoch == curDepositEpoch), " invalid withdraw time, currrent epoch is setting.");
        require (curInvestorExist(msg.sender), "invalid investor.");
        _amount = _amount * USDCDEMICAL;
        if (newWithdraRequest[msg.sender] == 0) {
            newWithdrawers.push(msg.sender);
        }
        newWithdraRequest[msg.sender] += _amount;
    }

    function investorActualWithDrawAll() public {
        require (investorsWithdrawPool[msg.sender] > 0, "insufficient funds");
        int amount = investorsWithdrawPool[msg.sender];
        if (transferUSDC) {
            bool success = usdc_service.transfer(msg.sender, uint(amount));
            require (success, "error transfer usdc");
        }
        delete investorsWithdrawPool[msg.sender];
    }

    function investorActualWithDraw(int amount) public {
        require (investorsWithdrawPool[msg.sender] >= amount * USDCDEMICAL, "insufficient funds");
        if (transferUSDC) {
            bool success = usdc_service.transfer(msg.sender, uint(amount * USDCDEMICAL));
            require (success, "error transfer usdc");
        }
        investorsWithdrawPool[msg.sender] -= amount * USDCDEMICAL;
    }

    function getOptionPrice() public view returns (int) {
        return (createRandom(96) + 5) * USDCDEMICAL / 100;
    }

    function buy(uint strikeTime, int strikePrice, bool optionType, uint produtepochId, int _amount) public runningEpoch {
        require (epochId >= 1 && epochId == produtepochId, "epochId invalid.");
        require (strikeTime >= curEpochStartTime && strikeTime <= curEpochEndTime, "strikeTime invalid.");
        require (strikeTime > getNow(), "strikeTime invalid.");
        require (strikePrice >= minStrikePrice && strikePrice <= maxStrikePrice, "strikePrice invalid.");
        require (_amount >= 50, "_amount invalid.");
        uint256 balance = usdc_service.balanceOf(msg.sender);
        require (balance >= uint(_amount * USDCDEMICAL), "insufficient funds");
        if (transferUSDC) {
            bool success = usdc_service.transferFrom(msg.sender, address(this), uint(_amount * USDCDEMICAL));
            require(success, "error transfer usdc");
        }

        traderPool += _amount * USDCDEMICAL;
        int optionPrice = getOptionPrice();

        console.log("optionPrice :", uint(optionPrice));
        console.log("_amount : ", uint(_amount * USDCDEMICAL));

        int orderSize = (_amount * USDCDEMICAL) / optionPrice;
        require (orderSize > 0, "orderSize smaller than 1.");
        require (totalBalance - curRoundLockedBalance >= orderSize * USDCDEMICAL);
        curRoundLockedBalance += orderSize * USDCDEMICAL;

        console.log("orderSize", uint(orderSize));

        Option memory option;
        option.strikePrice = strikePrice;
        option.strikeTime = strikeTime;
        option.optionType = optionType;

        OptionOrder memory optionOrder;
        optionOrder.option = option;
        optionOrder.orderSize = orderSize;
        optionOrder.status = "opened";

        traderOptionOrders[msg.sender][epochId].push(optionOrder);
        if (curEpochTraderOrderLength[msg.sender] == 0) {
            curEpochTraders.push(msg.sender);
        }
        curEpochTraderOrderLength[msg.sender] += 1;
        curEpochTotalProfit += _amount * USDCDEMICAL;

    }

    // 计算当前 EPOCH 的期权利润。
    function calculateTraderProfits() public isOwner {
        require (epochId == curProfitEpoch + 1);
        require (curProfitEpoch == curSettleEpoch && curProfitEpoch == curDepositEpoch);
        
        int settlePrice = (1105 + createRandom(200)) * PRICEDEMICAL;
        console.log("epochId:", epochId, " settlePrice:", uint(settlePrice));

        curProfitEpoch = epochId;
        for (uint i = 0; i < curEpochTraders.length; ++i) {
            address trader = curEpochTraders[i];
            uint orderNum = curEpochTraderOrderLength[trader];
            int curTraderSettledSize = 0;
            for (uint j = 0; j < orderNum; ++j) {
                string memory orderStatus = traderOptionOrders[trader][epochId][j].status;
                if (compareStrings(orderStatus, "settled")) {
                    continue;
                }
                traderOptionOrders[trader][epochId][j].status = "settled";
                bool optionType = traderOptionOrders[trader][epochId][j].option.optionType;
                int orderSize = traderOptionOrders[trader][epochId][j].orderSize;

                if (optionType == true) {
                    if (settlePrice >= traderOptionOrders[trader][epochId][j].option.strikePrice) {
                        curEpochTotalProfit -= orderSize * USDCDEMICAL;
                        curTraderSettledSize += orderSize;
                        console.log("Value=1, orderNum=", j, "strikePrice=", uint(traderOptionOrders[trader][epochId][j].option.strikePrice));
                    } else {
                        console.log("Value=0, orderNum=", j, "strikePrice=", uint(traderOptionOrders[trader][epochId][j].option.strikePrice));
                    }
                } else {
                    if (settlePrice <= traderOptionOrders[trader][epochId][j].option.strikePrice) {
                        curEpochTotalProfit -= orderSize * USDCDEMICAL;
                        curTraderSettledSize += orderSize;
                        console.log("Value=1, orderNum=", j, "strikePrice=", uint(traderOptionOrders[trader][epochId][j].option.strikePrice));
                    } else {
                        console.log("Value=0, orderNum=", j, "strikePrice=", uint(traderOptionOrders[trader][epochId][j].option.strikePrice));
                    }
                }
            }
            traderProfitPool[trader] += curTraderSettledSize * USDCDEMICAL;
            curEpochTraderOrderLength[trader] = 0;
        }
        curEpochTraders = new address[](0);
    }

    // 对当前 EPOCH 的 invesotrs 的利润进行结算。
    function handleSettlement() public isOwner {
        require (epochId == curProfitEpoch && curProfitEpoch == curSettleEpoch + 1 && curSettleEpoch == curDepositEpoch);
        int curRoundProfit = curEpochTotalProfit;
        // 根据这一轮的 Profit 计算新的 Balance 对于每个投资人。
        int newTotalBalance = 0;
        console.log("investor length:", investors.length);
        for (uint i = 0; i < investors.length; ++i) {    
            address investor = investors[i];
            console.log("investor addr:", investor);
            console.log("investor lp amount origin:", uint(liquidityPool[investor]));
            liquidityPool[investor] = liquidityPool[investor] + curRoundProfit * liquidityPool[investor] / totalBalance;
            if (liquidityPool[investor] < 0) {
                liquidityPool[investor] = 0;
            }
            console.log("investor lp amount updated:", uint(liquidityPool[investor]));
            if (newWithdraRequest[investor] > 0) {
                if (liquidityPool[investor] >= newWithdraRequest[investor]) {
                    investorsWithdrawPool[investor] += newWithdraRequest[investor];
                    liquidityPool[investor] -= newWithdraRequest[investor];
                }
                delete newWithdraRequest[investor];
            }
            newTotalBalance += liquidityPool[investor];
        }
        newWithdrawers = new address[](0);
        curSettleEpoch = curProfitEpoch;
        totalBalance = newTotalBalance;
        curRoundLockedBalance = 0;
    }

    // 当前 EPOCH 结束时, 处理新的 investors 的请求。
    function handleDepositRequest() public isOwner {
        require (epochId == curProfitEpoch && curProfitEpoch == curSettleEpoch && curSettleEpoch == curDepositEpoch + 1);
        int256 newTotalBalance = totalBalance;
        for (uint i = 0; i < newDepositers.length; ++i) {
            address depositer = newDepositers[i];
            liquidityPool[depositer] += newDepositRequest[depositer];
            newDepositRequest[depositer] = 0;
            if (curInvestorExist(depositer) == false) {
                investors.push(depositer);
            }
            newTotalBalance += liquidityPool[depositer];
            delete newDepositRequest[depositer];
        }
        newDepositers = new address[](0);
        curDepositEpoch = curSettleEpoch;
        totalBalance = newTotalBalance;
    }

    // 处理第一轮的投资请求, 计算 totalBalance, 
    function handleFirstDepositProcess() private isOwner {
        require (epochId == 0, "this is not first deposit process");
        int startingBalance = 0;
        for (uint i = 0; i < newDepositers.length; ++i) {
            address depositer = newDepositers[i];
            int256 depostAmount = newDepositRequest[depositer];
            liquidityPool[depositer] = depostAmount;
            newDepositRequest[depositer] = 0;
            startingBalance += depostAmount;
            delete newDepositRequest[depositer];
            investors.push(depositer);
        }
        newDepositers = new address[](0);
        totalBalance = startingBalance;
    }

    function startNewEpoch(uint256 period) public isOwner {
        require (epochId == curProfitEpoch && epochId == curSettleEpoch && epochId == curDepositEpoch, "invalid epochId.");
        require (period == 10 * 60);
        curEpochStartTime = getNow();
        curEpochEndTime = curEpochStartTime + period;
        int lastRoundPrice = getLatestPrice();
        maxStrikePrice = 130 * lastRoundPrice / 100;
        minStrikePrice = 70 * lastRoundPrice / 100;
        console.log("curEpoch start time:", curEpochStartTime);
        console.log("curEpoch end time:", curEpochEndTime);
        if (epochId == 0) {
            handleFirstDepositProcess();
        }
        // 获取预言机的价格, 制定期权产品。
        epochId += 1;
        curEpochTotalProfit = 0;
    }
}