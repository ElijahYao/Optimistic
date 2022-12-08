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
    uint public lastSettledEpochId;                         // 上一轮完成结算的 EpochId. 
    bool transferUSDC = false;                              // 是否交易 USDC

    uint public impliedVoltality;                           // 隐含波动率
    uint public period = 43200;                               // 一个 Epoch 交易时长

    uint initialNumber = 0;                                 // 无关变量

    // Epoch 相关变量
    int public curEpochTotalProfit;                         // 当前 Epoch 利润
    
    uint256 public curEpochStartTime;                       // 当前 Epoch 开始时间。
    uint256 public curEpochEndTime;                         // 当前 Epoch 结束时间。
    int256 public maxStrikePrice;                           // 当前 Epoch 售卖期权的最高的行权价格。
    int256 public minStrikePrice;                           // 当前 Epoch 售卖期权的最低的行权价格。

    // LP investors 资金池相关变量
    // 当前资金池, 新一轮存款请求, 新一轮提款请求
    mapping (address => int) public liquidityPool;          // 资金池 addr -> USDC 数量
    mapping (address => int) public investorsWithdrawPool;  // 提款池 addr -> USDC 数量
    mapping (address => int) public newDepositRequest;      // 存款请求 addr -> USDC 数量
    mapping (address => int) public newWithdrawRequest;     // 提款请求 addr -> USDC 数量

    int public totalBalance;                                // 资金池 USDC 数量
    int public curEpochLockedBalance = 0;                   // 当前交易周期锁定 USDC 数量
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

    int public immutable MINOPTIONPRICE = (5 * 10 ** 6 / 100);
    int public immutable MAXOPTIONPRICE = (100 * 10 ** 6 / 100);

    AggregatorV3Interface internal priceFeed;
    mapping (address => OptionOrder[]) public traderCurEpochOptionOrders;       // 当前 Epoch 交易者的 OptionOrders
    mapping (address => OptionOrder[]) public traderHistoryOptionOrders;        // 历史交易者的 OptionOrders
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
        require (epochId == lastSettledEpochId + 1, "running epoch is required.");
        _;
    }
    constructor() {
        owner = msg.sender;
        epochId = 0;
        totalBalance = 0;
        curEpochTotalProfit = 0;
        priceFeed = AggregatorV3Interface(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);
        optimisticBalance = 0;
        USDCProtocol = USDC(0x07865c6E87B9F70255377e024ace6630C1Eaa37F);
        transferUSDC = true;
        impliedVoltality = 675;
    }

    function getLatestPrice() public view returns (int) {
        return 1205 * PRICEDEMICAL;
    }

    function getHistoryOptions() public view returns (OptionOrder[] memory) {
        return traderHistoryOptionOrders[msg.sender];
    }

    function getCurOptions() public view returns (OptionOrder[] memory) {
        return traderCurEpochOptionOrders[msg.sender]; 
    }

    function getCurValues() public view returns (int) {
        return traderProfitPool[msg.sender];
    } 

    function getNow() private view returns (uint) {
        return block.timestamp;
    }

    function createRandom(uint number) private view returns(int){
        return int(uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % number);
    }

    function compareStrings(string memory a, string memory b) private view returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function curInvestorExist(address sender) private view returns (bool) {
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
        require (curInvestorExist(msg.sender), "invalid investor.");
        _amount = _amount * USDCDEMICAL;
        if (newWithdrawRequest[msg.sender] == 0) {
            newWithdrawers.push(msg.sender);
        }
        newWithdrawRequest[msg.sender] += _amount;
    }

    // function investorActualWithDrawAll() public {
    //     require (investorsWithdrawPool[msg.sender] > 0, "insufficient funds");
    //     int amount = investorsWithdrawPool[msg.sender];
    //     if (transferUSDC) {
    //         bool success = USDCProtocol.transfer(msg.sender, uint(amount));
    //         require (success, "error transfer usdc");
    //     }
    //     delete investorsWithdrawPool[msg.sender];
    // }

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

    function traderSell(uint productEpochId, uint orderIndex, int sellPrice) public {
        require (epochId == productEpochId, "invalid epochId, productEpochId != epochId.");
        require (orderIndex < traderCurEpochOptionOrders[msg.sender].length, "invalid orderIndex, no such order.");
        require (sellPrice >= MINOPTIONPRICE && sellPrice <= MAXOPTIONPRICE, "invalid sell price.");
        require (sellPrice % (10 ** 4) == 0, "invalid sell price.");
        require (compareStrings(traderCurEpochOptionOrders[msg.sender][orderIndex].status, "opened"), "current order is not opened.");

        // 赎回成功的逻辑
        int orderSize = traderCurEpochOptionOrders[msg.sender][orderIndex].orderSize;

        traderProfitPool[msg.sender] += orderSize * sellPrice;
        traderCurEpochOptionOrders[msg.sender][orderIndex].status = "closed";

        OptionOrder memory optionOrder = traderCurEpochOptionOrders[msg.sender][orderIndex];
        traderHistoryOptionOrders[msg.sender].push(optionOrder);

        curEpochLockedBalance -= orderSize * 1 * USDCDEMICAL;
        curEpochTotalProfit -= orderSize * sellPrice;
    }

    function traderBuy(uint strikeTime, int strikePrice, bool optionType, uint productEpochId, int buyPrice, int _amount) public {
        require (epochId >= 1 && epochId == productEpochId, "invalid epochId.");
        require (strikeTime >= curEpochStartTime && strikeTime <= curEpochEndTime, "invalid strikeTime.");
        require (strikeTime > getNow(), "invalid strikeTime.");
        require (strikePrice >= minStrikePrice && strikePrice <= maxStrikePrice, "invalid strikePrice.");
        require (buyPrice >= MINOPTIONPRICE && buyPrice <= MAXOPTIONPRICE, "invalid buy price.");
        require (buyPrice % (10 ** 4) == 0, "invalid buy price.");

        // 检查 orderSize & 是否支持当前的购买
        int orderSize = (_amount * USDCDEMICAL) / buyPrice; 
        require (orderSize > 0, "orderSize smaller than 1.");
        require (totalBalance - curEpochLockedBalance >= orderSize * USDCDEMICAL, "insufficient option supply.");

        if (transferUSDC) {
             // 检查用户 USDC 是否充足。
            uint balance = USDCProtocol.balanceOf(msg.sender);
            require (balance >= uint(_amount * USDCDEMICAL), "insufficient USDC funds");
            bool success = USDCProtocol.transferFrom(msg.sender, address(this), uint(_amount * USDCDEMICAL));
            require(success, "error transfer usdc");
        }

        // 购买成功的逻辑
        curEpochLockedBalance += orderSize * 1 * USDCDEMICAL;

        Option memory option;
        option.strikePrice = strikePrice;
        option.strikeTime = strikeTime;
        option.optionType = optionType;

        OptionOrder memory optionOrder;
        optionOrder.option = option;
        optionOrder.orderSize = orderSize;
        optionOrder.status = "opened";
        optionOrder.buyPrice = buyPrice;

        if (traderCurEpochOptionOrders[msg.sender].length == 0) {
            curEpochTraders.push(msg.sender);
        }
        traderCurEpochOptionOrders[msg.sender].push(optionOrder);
        curEpochTotalProfit += _amount * USDCDEMICAL;
    }

    // 计算当前 EPOCH 的期权利润。
    function calculateTraderProfits() public {
        require (epochId == lastSettledEpochId + 1);
        int settlePrice = (1105 + createRandom(200)) * PRICEDEMICAL;
        for (uint i = 0; i < curEpochTraders.length; ++i) {
            address trader = curEpochTraders[i];
            int curTraderSettledSize = 0;
            for (uint j = 0; j < traderCurEpochOptionOrders[trader].length; ++j) {
                string memory orderStatus = traderCurEpochOptionOrders[trader][j].status;
                if (compareStrings(orderStatus, "settled") || compareStrings(orderStatus, "closed")) {
                    continue;
                }
                traderCurEpochOptionOrders[trader][j].status = "settled";
                int orderSize = traderCurEpochOptionOrders[trader][j].orderSize;
                // Settle CALL
                if (traderCurEpochOptionOrders[trader][j].option.optionType == true) {
                    if (settlePrice >= traderCurEpochOptionOrders[trader][j].option.strikePrice) {
                        curEpochTotalProfit -= orderSize * USDCDEMICAL;
                        curTraderSettledSize += orderSize;
                    }
                // Settle PUT
                } else {
                    if (settlePrice <= traderCurEpochOptionOrders[trader][j].option.strikePrice) {
                        curEpochTotalProfit -= orderSize * USDCDEMICAL;
                        curTraderSettledSize += orderSize;
                    }
                }
                OptionOrder memory optionOrder = traderCurEpochOptionOrders[trader][j];
                traderHistoryOptionOrders[trader].push(optionOrder);
            }
            traderProfitPool[trader] += curTraderSettledSize * USDCDEMICAL;
            delete traderCurEpochOptionOrders[trader];
        }
        curEpochTraders = new address[](0);
    }

    // 对当前 EPOCH 的 invesotrs 的利润进行结算。
    // 根据这一轮的 Profit 计算新的 Balance 对于每个投资人。
    function handleSettlement() private {
        int lastTotalBalance = totalBalance;
        totalBalance = 0;
        if (curEpochTotalProfit > 0) {
            int optimisticBalanceEarn = curEpochTotalProfit * 5 / 100;
            optimisticBalance += optimisticBalanceEarn;
            curEpochTotalProfit -= optimisticBalanceEarn;
        }
        for (uint i = 0; i < investors.length; ++i) {
            address investor = investors[i];
            liquidityPool[investor] = liquidityPool[investor] + curEpochTotalProfit * liquidityPool[investor] / lastTotalBalance;
            if (liquidityPool[investor] <= 0) {
                liquidityPool[investor] = 0;
            }
            if (newWithdrawRequest[investor] > 0) {
                if (liquidityPool[investor] >= newWithdrawRequest[investor]) {
                    investorsWithdrawPool[investor] += newWithdrawRequest[investor];
                    liquidityPool[investor] -= newWithdrawRequest[investor];
                }
                delete newWithdrawRequest[investor];
            }
            totalBalance += liquidityPool[investor];
        }
        newWithdrawers = new address[](0);
        curEpochLockedBalance = 0;
    }

    // 当前 EPOCH 结束时, 处理新的 investors 的请求。
    function handleDepositRequest() private {
        for (uint i = 0; i < newDepositers.length; ++i) {
            address depositer = newDepositers[i];
            liquidityPool[depositer] += newDepositRequest[depositer];
            totalBalance += newDepositRequest[depositer];
            if (curInvestorExist(newDepositers[i]) == false) {
                investors.push(newDepositers[i]);
            }
            delete newDepositRequest[newDepositers[i]];
        }
        newDepositers = new address[](0);
    }

    // 处理第一轮的投资请求, 计算 totalBalance,
    function handleFirstDepositProcess() private {
        totalBalance = 0;
        for (uint i = 0; i < newDepositers.length; ++i) {
            liquidityPool[newDepositers[i]] = newDepositRequest[newDepositers[i]];
            totalBalance += newDepositRequest[newDepositers[i]];
            delete newDepositRequest[newDepositers[i]];
            investors.push(newDepositers[i]);
        }
        newDepositers = new address[](0);
    }

    // 重新开始一个新的 Epoch, 包含 3 个 step.
    function adminReloadNewEpoch() public {
        calculateTraderProfits();
        handleSettlement();
        handleDepositRequest();
        lastSettledEpochId += 1;
        adminStartNewEpoch();
    }

    // 开始第一个 Epoch
    function adminStartNewEpoch() public {
        require (epochId == lastSettledEpochId, "invalid epochId.");
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
