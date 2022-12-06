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
    // Global
    USDC public USDCProtocol;
    address public owner;
    uint public epochId;
    uint initialNumber = 0;
    bool transferUSDC = false;                              // 是否交易 USDC

    uint public impliedVoltality ;

    // Epoch 相关变量
    int public curEpochTotalProfit;                         // 当前 Epoch 利润

    uint curProfitEpochId;                                  // 当前 Traders 利润结算计算完成的 EpochId
    uint curSettleEpochId;                                  // 当前 LP investors 资金结算完成的 EpochId
    uint curDepositEpochId;                                 // 当前 LP investors 处理完新请求的 EpochId

    uint256 public curEpochStartTime;                       // 当前 Epoch 开始时间。
    uint256 public curEpochEndTime;                         // 当前 Epoch 结束时间。
    int256 public maxStrikePrice;                           // 当前 Epoch 售卖期权的最高的行权价格。
    int256 public minStrikePrice;                           // 当前 Epoch 售卖期权的最低的行权价格。

    // LP investors 资金池相关变量
    // 当前资金池, 新一轮存款请求, 新一轮提款请求
    mapping (address => int) public liquidityPool;          // 资金池 addr -> USDC 数量
    mapping (address => int) public investorsWithdrawPool;  // 提款池 addr -> USDC 数量
    mapping (address => int) public newDepositRequest;      // 存款请求 addr -> USDC 数量
    mapping (address => int) public newWithdraRequest;      // 提款请求 addr -> USDC 数量

    int public totalBalance;                                // 资金池 USDC 数量
    int public curRoundLockedBalance = 0;                   // 当前交易周期锁定 USDC 数量
    address[] investors;                                    // 当前交易周期 LP 列表
    address[] newDepositers;                                // 当前交易周期新存款者列表
    address[] newWithdrawers;                               // 当前交易周期新提款

    // traders 相关变量
    struct Option {
        int strikePrice;
        uint strikeTime;
        bool optionType;
    }
    struct OptionOrder {
        Option option;
        int orderSize;
        string status;
        int buyPrice;
    }
    int public immutable PRICEDEMICAL = 10 ** 8;
    int public immutable USDCDEMICAL = 10 ** 6;
    int public immutable PRICEGAP = 10 ** 2;

    int public immutable MINSELLPRICE = (5 * 10 ** 6 / 100);
    int public immutable MAXSELLPRICE = (100 * 10 ** 6 / 100);
    int public immutable MINBUYPRICE = (5 * 10 ** 6 / 100);
    int public immutable MAXBUYPRICE = (100 * 10 ** 6 / 100);


    AggregatorV3Interface internal priceFeed;
    mapping (address => mapping (uint => OptionOrder[])) public traderOptionOrders;
    mapping (address => uint) curEpochTraderOrderLength;
    mapping (address => int) traderProfitPool;

    address[] curEpochTraders;

    // Optimistic 定义变量
    int public optimisticBalance;

    // Ends
    modifier isOwner() {
        require(msg.sender == owner, "caller is not owner");
        _;
    }

    modifier runningEpoch() {
        require (epochId == curProfitEpochId + 1 && curProfitEpochId == curSettleEpochId && curSettleEpochId == curDepositEpochId, "there is no epoch active.");
        _;
    }

    constructor() {
        owner = msg.sender;
        epochId = 0;
        totalBalance = 0;
        curSettleEpochId = 0;
        curProfitEpochId = 0;
        curDepositEpochId = 0;
        curEpochTotalProfit = 0;
        priceFeed = AggregatorV3Interface(
            0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
        );
        optimisticBalance = 0;
        USDCProtocol = USDC(0x07865c6E87B9F70255377e024ace6630C1Eaa37F);
        transferUSDC = false;
        impliedVoltality = 675;
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

    function getHistoryOptions() public view returns (OptionOrder[] memory) {
        uint historyLength = 0;
        for (uint k = 0; k < epochId; ++k) {
            historyLength += traderOptionOrders[msg.sender][k].length;
        }
        OptionOrder[] memory result = new OptionOrder[](historyLength);
        uint i = 0;
        for (uint k = 0; k < epochId; ++k) {
            for (uint j = 0 ; j < traderOptionOrders[msg.sender][k].length; ++j) {
                result[i++] = traderOptionOrders[msg.sender][k][j];
            }
        }
        return result;
    }

    function getCurOptions() public view returns  (OptionOrder[] memory) {
        uint curLength = traderOptionOrders[msg.sender][epochId].length;
        OptionOrder[] memory result = new OptionOrder[](curLength);

        uint i = 0;
        for (uint j = 0 ; j < traderOptionOrders[msg.sender][epochId].length; ++j) {
            result[i++] = traderOptionOrders[msg.sender][epochId][j];
        }
        return result;
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

    function optimisticWithDraw(int _amount) public isOwner {
        require (_amount * USDCDEMICAL <= optimisticBalance);
        bool success = USDCProtocol.transferFrom(address(this), owner, uint(_amount * USDCDEMICAL));
        require (success, "error transfer usdc.");
        optimisticBalance -= _amount * USDCDEMICAL;
    }

    function traderWithdraw(int _amount) public {
        require (traderProfitPool[msg.sender] >= 0, "no profit.");
        require (_amount * USDCDEMICAL <= traderProfitPool[msg.sender], "insufficient profit.");
        if (transferUSDC) {
            bool success = USDCProtocol.transfer(msg.sender, uint(_amount * USDCDEMICAL));
            require(success, "error transfer usdc.");
        }
        traderProfitPool[msg.sender] -= _amount * USDCDEMICAL;
    }

    function investorDeposit(int _amount) public {
        require ((epochId == curProfitEpochId + 1 && curProfitEpochId == curSettleEpochId && curSettleEpochId == curDepositEpochId) || epochId == 0, "invalid deposit time, current epoch is settling.");
        require(_amount >= 10, "invest amount less than 100 USDC.");
        _amount = _amount * USDCDEMICAL;
        if (transferUSDC) {
            uint256 balance = USDCProtocol.balanceOf(msg.sender);
            require(balance >= uint(_amount), "insufficient token");
            bool success = USDCProtocol.transferFrom(msg.sender, address(this), uint(_amount));
            require(success, "error transfer usdc");
        }
        if (newDepositRequest[msg.sender] == 0) {
            newDepositers.push(msg.sender);
        }
        newDepositRequest[msg.sender] += _amount;

    }

    function investorWithDraw(int _amount) public {
        require ((epochId == curProfitEpochId + 1 && curProfitEpochId == curSettleEpochId && curSettleEpochId == curDepositEpochId), "invalid withdraw time, currrent epoch is setting.");
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
            bool success = USDCProtocol.transfer(msg.sender, uint(amount));
            require (success, "error transfer usdc");
        }
        delete investorsWithdrawPool[msg.sender];
    }

    function investorActualWithDraw(int amount) public {
        require (investorsWithdrawPool[msg.sender] >= amount * USDCDEMICAL, "insufficient funds");
        if (transferUSDC) {
            bool success = USDCProtocol.transfer(msg.sender, uint(amount * USDCDEMICAL));
            require (success, "error transfer usdc");
        }
        investorsWithdrawPool[msg.sender] -= amount * USDCDEMICAL;
    }

    function getOptionPrice() public view returns (int) {
        return (createRandom(96) + 5) * USDCDEMICAL / 100;
    }

    function sell(uint productEpochId, uint orderIndex, int sellPrice) public runningEpoch {
        require (epochId == productEpochId, "invalid epochId, productEpochId != epochId.");
        require (orderIndex < curEpochTraderOrderLength[msg.sender], "invalid orderIndex, no such order.");
        require (sellPrice >= MINSELLPRICE && sellPrice <= MAXSELLPRICE, "invalid sell price.");
        require (sellPrice % (10 ** 4) == 0, "invalid sell price.");

        string memory orderStatus = traderOptionOrders[msg.sender][epochId][orderIndex].status;
        require (compareStrings(orderStatus, "opened"), "current order is not opened.");

        // 赎回成功的逻辑
        int orderSize = traderOptionOrders[msg.sender][epochId][orderIndex].orderSize;

        traderProfitPool[msg.sender] += orderSize * sellPrice;
        traderOptionOrders[msg.sender][epochId][orderIndex].status = "closed";
        curRoundLockedBalance -= orderSize * 1 * USDCDEMICAL;
        curEpochTotalProfit -= orderSize * sellPrice;
    }

    function buy(uint strikeTime, int strikePrice, bool optionType, uint productEpochId, int buyPrice, int _amount) public runningEpoch {
        require (epochId >= 1 && epochId == productEpochId, "invalid epochId.");
        require (strikeTime >= curEpochStartTime && strikeTime <= curEpochEndTime, "invalid strikeTime.");
        require (strikeTime > getNow(), "invalid strikeTime.");
        require (strikePrice >= minStrikePrice && strikePrice <= maxStrikePrice, "invalid strikePrice.");
        require (_amount >= 10, "invalid _amount.");
        require (buyPrice >= MINBUYPRICE && buyPrice <= MAXBUYPRICE, "invalid buy price.");
        require (buyPrice % (10 ** 4) == 0, "invalid buy price.");

        // 检查 orderSize & 是否支持当前的购买
        int orderSize = (_amount * USDCDEMICAL) / buyPrice; 
        require (orderSize > 0, "orderSize smaller than 1.");
        require (totalBalance - curRoundLockedBalance >= orderSize * USDCDEMICAL, "insufficient option supply.");

        if (transferUSDC) {

             // 检查用户 USDC 是否充足。
            uint balance = USDCProtocol.balanceOf(msg.sender);
            require (balance >= uint(_amount * USDCDEMICAL), "insufficient USDC funds");
            bool success = USDCProtocol.transferFrom(msg.sender, address(this), uint(_amount * USDCDEMICAL));
            require(success, "error transfer usdc");
        }

        // 购买成功的逻辑
        curRoundLockedBalance += orderSize * 1 * USDCDEMICAL;

        Option memory option;
        option.strikePrice = strikePrice;
        option.strikeTime = strikeTime;
        option.optionType = optionType;

        OptionOrder memory optionOrder;
        optionOrder.option = option;
        optionOrder.orderSize = orderSize;
        optionOrder.status = "opened";
        optionOrder.buyPrice = buyPrice;

        traderOptionOrders[msg.sender][epochId].push(optionOrder);
        if (curEpochTraderOrderLength[msg.sender] == 0) {
            curEpochTraders.push(msg.sender);
        }
        curEpochTraderOrderLength[msg.sender] += 1;
        curEpochTotalProfit += _amount * USDCDEMICAL;
    }

    // 计算当前 EPOCH 的期权利润。
    function calculateTraderProfits() public {
        require (epochId == curProfitEpochId + 1);
        require (curProfitEpochId == curSettleEpochId && curProfitEpochId == curDepositEpochId);

        int settlePrice = (1105 + createRandom(200)) * PRICEDEMICAL;
        console.log("epochId:", epochId, " settlePrice:", uint(settlePrice));

        curProfitEpochId = epochId;
        for (uint i = 0; i < curEpochTraders.length; ++i) {
            address trader = curEpochTraders[i];
            uint orderNum = curEpochTraderOrderLength[trader];
            int curTraderSettledSize = 0;
            for (uint j = 0; j < orderNum; ++j) {
                string memory orderStatus = traderOptionOrders[trader][epochId][j].status;
                if (compareStrings(orderStatus, "settled")) {
                    continue;
                }
                if (compareStrings(orderStatus, "closed")) {
                    continue;
                }
                traderOptionOrders[trader][epochId][j].status = "settled";
                bool optionType = traderOptionOrders[trader][epochId][j].option.optionType;
                int orderSize = traderOptionOrders[trader][epochId][j].orderSize;

                if (optionType == true) {
                    if (settlePrice >= traderOptionOrders[trader][epochId][j].option.strikePrice) {
                        curEpochTotalProfit -= orderSize * USDCDEMICAL;
                        curTraderSettledSize += orderSize;
                    }
                } else {
                    if (settlePrice <= traderOptionOrders[trader][epochId][j].option.strikePrice) {
                        curEpochTotalProfit -= orderSize * USDCDEMICAL;
                        curTraderSettledSize += orderSize;
                    }
                }
            }
            traderProfitPool[trader] += curTraderSettledSize * USDCDEMICAL;
            curEpochTraderOrderLength[trader] = 0;
        }
        curEpochTraders = new address[](0);
    }

    // 对当前 EPOCH 的 invesotrs 的利润进行结算。
    function handleSettlement() public {
        require (epochId == curProfitEpochId && curProfitEpochId == curSettleEpochId + 1 && curSettleEpochId == curDepositEpochId);
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
        curSettleEpochId = curProfitEpochId;
        totalBalance = newTotalBalance;
        curRoundLockedBalance = 0;
    }

    // 当前 EPOCH 结束时, 处理新的 investors 的请求。
    function handleDepositRequest() public {
        require (epochId == curProfitEpochId && curProfitEpochId == curSettleEpochId && curSettleEpochId == curDepositEpochId + 1);
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
        curDepositEpochId = curSettleEpochId;
        totalBalance = newTotalBalance;
    }

    // 处理第一轮的投资请求, 计算 totalBalance,
    function handleFirstDepositProcess() private {
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

    function reloadNewEpoch() public {
        calculateTraderProfits();
        handleSettlement();
        handleDepositRequest();
        startNewEpoch();
    }

    function startNewEpoch() public {
        require (epochId == curProfitEpochId && epochId == curSettleEpochId && epochId == curDepositEpochId, "invalid epochId.");
        uint period = 600;
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
