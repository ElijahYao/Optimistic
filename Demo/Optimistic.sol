// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import "hardhat/console.sol";
import "contracts/OptionManager.sol";
import "contracts/LiquidityPoolManager.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "contracts/OptimisticUtils.sol";

interface USDC {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Optimistic  {

    USDC public USDCProtocol;
    OptionManager public immutable optionManager;
    LiquidityPoolManager public immutable liquidityPoolManager;
    

    address public owner;
    bool transferUSDC;
    bool test;
    uint public epochId;                                                       // 当前轮数

    AggregatorV3Interface internal priceProvider;

    int public curEpochLockedBalance = 0;                               // 当前交易周期锁定 USDC 数量   
    int public optimisticBalance;                                       // 平台方收益
    uint256 public curEpochEndTime;                                     // 当前 Epoch 结束时间。
    uint256 public curEpochStartTime;                                   // 当前 Epoch 开始时间。
    int256 public maxStrikePrice;                                       // 当前 Epoch 售卖期权的最高的行权价格。
    int256 public minStrikePrice;                                       // 当前 Epoch 售卖期权的最低的行权价格。

    int public immutable MINOPTIONPRICE = (5 * 10 ** 6 / 100);
    int public immutable MAXOPTIONPRICE = (100 * 10 ** 6 / 100);
    int public constant USDCDEMICAL = 10 ** 6;

    int public withdrawFeeDeno = 1000;
    int public withdrawFeeNume = 2;

    constructor() {
        owner = msg.sender;
        transferUSDC = true;
        test = true;
        USDCProtocol = USDC(0x07865c6E87B9F70255377e024ace6630C1Eaa37F);
        optionManager = OptionManager(0x7bAE5a2Ce5291645C4608995E4fB65903BbEe37f);
        liquidityPoolManager = LiquidityPoolManager(0x62948c0a68313CC8309bd3dbfE826Db7f454d148);
        priceProvider = AggregatorV3Interface(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);
    }

    modifier isOwner() {
        require(msg.sender == owner, "caller is not owner");
        _;
    }

    modifier isStarted() {
        require(epochId >= 1, "not stated.");
        _;
    }

    function setWithdrawFee(int _withdrawFeeDeno, int _withdrawFeeNume) public isOwner {
        withdrawFeeDeno = _withdrawFeeDeno;
        withdrawFeeNume = _withdrawFeeNume;
    }

    function getTraderProfitPool(address account) public view returns(int) {
        return optionManager.traderProfitPool(account);
    }

    function getLatestPrice() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceProvider.latestRoundData();
        return price;
    }

    function traderDeposit(int depositAmount) public{
        if (transferUSDC) {
            bool success = USDCProtocol.transferFrom(msg.sender, address(this), uint(depositAmount));
            require(success, "error transfer usdc.");
        }
        optionManager.traderDeposit(msg.sender, depositAmount);
    }

    // trader 购买期权。
    function traderBuy(uint strikeTime, int strikePrice, bool optionType, uint productEpochId, int buyPrice, int orderSize, uint futurePrice, uint buyPriceGenerateTime, bytes memory _signature) public isStarted {
        require (epochId == productEpochId, "invalid epochId.");
        require (strikeTime == curEpochEndTime && block.timestamp <= curEpochEndTime, "invalid strikeTime.");
        require (strikePrice >= minStrikePrice && strikePrice <= maxStrikePrice, "invalid strikePrice.");
        require (buyPrice >= MINOPTIONPRICE && buyPrice <= MAXOPTIONPRICE, "invalid buy price.");
        require (block.timestamp <= curEpochEndTime - 30 minutes, "not for sale 30 minutes before settlement");
        int totalBalance = liquidityPoolManager.getTotalBalance();
        require (orderSize * USDCDEMICAL <= totalBalance - curEpochLockedBalance, "insufficient option supply.");

        string memory option_type = optionType ? "CALL" : "PUT";
        string memory message = string.concat(Strings.toString(strikeTime), Strings.toString(uint(strikePrice)), option_type, Strings.toString(productEpochId), Strings.toString(uint(buyPrice)), Strings.toString(futurePrice), Strings.toString(buyPriceGenerateTime));
        // 价格来源通过签名验证有效性
        require (OptimisticUtils.verifyMsg(message, _signature, owner), "invalid buy price source.");
        // 价格生成时间最近，生成时间由上一步签名验证有效性
        require (block.timestamp < buyPriceGenerateTime + 3 minutes, "invalid price generate time");
        // 价格变化不能过大，防止套利
        require (OptimisticUtils.abs(getLatestPrice() - int(futurePrice)) * 100 / int(futurePrice) < 5, "buy failed, price changes too fast");
        require (orderSize >= 1);
        int traderAvaliableBalance = optionManager.getTraderAvaliableBalance(msg.sender);
        require (traderAvaliableBalance >= buyPrice * orderSize, "insufficient balance.");
        optionManager.addOption(strikeTime, strikePrice, optionType, productEpochId, buyPrice, orderSize, msg.sender);
        curEpochLockedBalance += orderSize * USDCDEMICAL;
    }

    // trader 取钱, withdrawAmount = 真实取款 USDC 数量 * 10^6。
    function traderWithdraw(int withdrawAmount) public isStarted {
        int traderAvaliableBalance = optionManager.getTraderAvaliableBalance(msg.sender);
        require (traderAvaliableBalance >= withdrawAmount, "insufficient profit.");
        int fees = withdrawAmount * withdrawFeeNume / withdrawFeeDeno;
        optimisticBalance += fees;
        if (transferUSDC) {
            bool success = USDCProtocol.transfer(msg.sender, uint(withdrawAmount - fees));
            require(success, "error transfer usdc.");
        }
        optionManager.traderWithdraw(msg.sender, withdrawAmount);
    }

    // lp investor 相关操作。
    // investor 存款。
    function investorDeposit(int investAmount) public {
        if (transferUSDC) {
            bool success = USDCProtocol.transferFrom(msg.sender, address(this), uint(investAmount));
            require(success, "error transfer usdc");
        }
        liquidityPoolManager.investorDeposit(msg.sender, investAmount);
    }

    // investor 提款请求。
    // 先从本轮存的池子取 不够再提交到下一轮申请
    function investorWithDraw(int withdrawAmount) public isStarted {
        int waitToWithdrawAmount = liquidityPoolManager.newWithdrawRequest(msg.sender);
        int curDepositAmount = liquidityPoolManager.newDepositRequest(msg.sender);
        require (waitToWithdrawAmount + withdrawAmount <= liquidityPoolManager.liquidityPool(msg.sender) + curDepositAmount);
        int nextDepositAmount = liquidityPoolManager.withdrawFromCurDeposit(msg.sender, withdrawAmount);
        if (nextDepositAmount > 0) {
            liquidityPoolManager.investorWithdrawRequest(msg.sender, withdrawAmount - curDepositAmount);
        }
    }

    // investor 实际提款。
    function investorActualWithDraw(int withdrawAmount) public {
        int withdrawPoolAmount = liquidityPoolManager.getWithdrawAmount(msg.sender);
        require (withdrawPoolAmount >= withdrawAmount, "insufficient balance.");
        int fees = withdrawAmount * withdrawFeeNume / withdrawFeeDeno;
        optimisticBalance += fees;
        if (transferUSDC) {
            bool success = USDCProtocol.transfer(msg.sender, uint(withdrawAmount - fees));
            require (success, "error transfer usdc");
        }
        liquidityPoolManager.investorActualWithdraw(msg.sender, withdrawAmount);
    }

    // admin 重新开始一个新的 epoch。
    function adminStartNewEpoch(int settlePrice, int _maxStrikePrice, int _minStrikePrice, uint256 _curEpochEndTime) public isOwner {
        // 第一个 epoch
        require(_curEpochEndTime > block.timestamp + 1800, "invalid _curEpochEndTime.");
        if (epochId != 0) {
            if (test == false) {
                require(block.timestamp > curEpochEndTime);
            }
            int curEpochLiquidityPoolProfit = optionManager.calculateTraderProfit(settlePrice, epochId);
            optionManager.resetCurEpochProfit();
            int fees = liquidityPoolManager.settlementProcess(curEpochLiquidityPoolProfit);
            optimisticBalance += fees;
        } else {
            liquidityPoolManager.firstDepositProcess();
        }
        curEpochStartTime = block.timestamp;
        curEpochEndTime = _curEpochEndTime;
        maxStrikePrice = _maxStrikePrice;
        minStrikePrice = _minStrikePrice;
        epochId += 1;
        curEpochLockedBalance = 0;
    }

    // admin 提款。
    function adminWithDraw(int withdrawAmount) public isOwner {
        require (withdrawAmount <= optimisticBalance);
        bool success = USDCProtocol.transfer(owner, uint(withdrawAmount));
        require (success, "error transfer usdc.");
        optimisticBalance -= withdrawAmount;
    }
}
