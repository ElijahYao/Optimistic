// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import "hardhat/console.sol";
import "contracts/OptionManager.sol";
import "contracts/LiquidityPoolManager.sol";

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
    uint epochId;                                                       // 当前轮数

    int public curEpochLockedBalance = 0;                               // 当前交易周期锁定 USDC 数量   
    int public optimisticBalance;                                       // 平台方收益
    uint256 public curEpochEndTime;                                     // 当前 Epoch 结束时间。
    int256 public maxStrikePrice;                                       // 当前 Epoch 售卖期权的最高的行权价格。
    int256 public minStrikePrice;                                       // 当前 Epoch 售卖期权的最低的行权价格。

    constructor() {
        transferUSDC = false; 
        optionManager = OptionManager(0xd9145CCE52D386f254917e481eB44e9943F39138);
        liquidityPoolManager = LiquidityPoolManager(0xd9145CCE52D386f254917e481eB44e9943F39138);
    }

    // trader 购买期权。
    function traderBuy(uint strikeTime, int strikePrice, bool optionType, uint productEpochId, int buyPrice, int orderSize) public returns (bool) {
        if (transferUSDC) {
            bool success = USDCProtocol.transfer(msg.sender, uint(buyPrice * orderSize));
            require(success, "error transfer usdc.");
        }
        bool addSuccess = optionManager.addOption(strikeTime, strikePrice, optionType, productEpochId, buyPrice, orderSize, msg.sender);
        return addSuccess;
    }

    // trader 取钱, withdrawAmount = 真实取款 USDC 数量 * 10^6。
    function traderWithdraw(int withdrawAmount) public {
        int traderProfit = optionManager.getTraderProfit(msg.sender);
        require (traderProfit >= withdrawAmount, "insufficient profit.");
        if (transferUSDC) {
            bool success = USDCProtocol.transfer(msg.sender, uint(withdrawAmount));
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
    function investorWithDraw(int withdrawAmount) public {
        liquidityPoolManager.investorWithdrawRequest(msg.sender, withdrawAmount);
    }

    // investor 实际提款。
    function investorActualWithDraw(int withdrawAmount) public {
        int withdrawPoolAmount = liquidityPoolManager.getWithdrawAmount(msg.sender);
        require (withdrawPoolAmount >= withdrawAmount, "insufficient balance.");
        if (transferUSDC) {
            bool success = USDCProtocol.transfer(msg.sender, uint(withdrawAmount));
            require (success, "error transfer usdc");
        }
        liquidityPoolManager.investorActualWithdraw(msg.sender, withdrawAmount);
    }

    // admin 重新开始一个新的 epoch。
    function adminStartNewEpoch(int settlePrice, int _maxStrikePrice, int _minStrikePrice, uint256 _curEpochEndTime) public {
        // 第一次
        if (epochId != 0) {
            int curEpochLiquidityPoolProfit = optionManager.calculateTraderProfit(settlePrice, epochId);
            liquidityPoolManager.settlementProcess(curEpochLiquidityPoolProfit);
        } else {
            liquidityPoolManager.firstDepositProcess();
        }
        curEpochEndTime = _curEpochEndTime;
        maxStrikePrice = _maxStrikePrice;
        minStrikePrice = _minStrikePrice;
        epochId += 1;
        curEpochLockedBalance = 0;
    }

    // admin 提款。
    function adminWithDraw(int withdrawAmount) public {
        require (withdrawAmount <= optimisticBalance);
        bool success = USDCProtocol.transferFrom(address(this), owner, uint(withdrawAmount));
        require (success, "error transfer usdc.");
        optimisticBalance -= withdrawAmount;
    }
}
