// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import "hardhat/console.sol";
import "contracts/OptionManager.sol";

contract Optimistic  {

    OptionManager public immutable optionManager;
    LiquidityPoolManager public immutable LiquidityPoolManager;

    bool transferUSDC;
    uint epochId;                                                       // 当前 epoch 轮数

    int public curEpochLockedBalance = 0;                               // 当前交易周期锁定 USDC 数量   

    constructor() {
        transferUSDC = false; 
        optionManager = OptionManager(0xd9145CCE52D386f254917e481eB44e9943F39138);
    }

    function getNow() public view returns (uint) {
        return block.timestamp;
    }

    function verifyPrice() private view returns (bool) {
        return true;
    }

    
    // trader 相关操作
    function traderBuy(uint strikeTime, int strikePrice, bool optionType, uint productEpochId, int buyPrice, int _amount) public returns (bool) {
        bool addSuccess = optionManager.addOption(strikeTime, strikePrice, optionType, productEpochId, buyPrice, _amount, msg.sender);
        return addSuccess;
    }

    function traderSell() public returns (bool) {

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

    // lp investor 相关操作

    function investorDeposit(int _amount) public {

    }

    function investorWithDraw(int _amount) public {
        require (curInvestorExist(msg.sender), "invalid investor.");
        _amount = _amount * USDCDEMICAL;
        if (newWithdrawRequest[msg.sender] == 0) {
            newWithdrawers.push(msg.sender);
        }
        newWithdrawRequest[msg.sender] += _amount;
    }

    function investorActualWithDraw(int amount) public {
        require (investorsWithdrawPool[msg.sender] >= amount * USDCDEMICAL, "insufficient funds");
        if (transferUSDC) {
            bool success = USDCProtocol.transfer(msg.sender, uint(amount * USDCDEMICAL));
            require (success, "error transfer usdc");
        }
        investorsWithdrawPool[msg.sender] -= amount * USDCDEMICAL;
    }


    // admin 相关操作
    function settleCurrentEpoch(int settlePrice) public returns (bool) {

        int curEpochLiquidityPoolProfit = OptionManager.calculateTraderProfit(settlePrice, epochId);
        int x = LiquidityPoolManager.settlementProcess(curEpochLiquidityPoolProfit);
        totalBalance = LiquidityPoolManager.depositProcess();

        return true;
    }

    function startNewEpoch() public returns (bool) {
        return true;
    }

    

    // 重新开始一个新的 Epoch, 包含 3 个 step.
    function adminReloadNewEpoch(int settlePrice) public {
        if (epochId != 0) {
            calculateTraderProfits(settlePrice);
            handleSettlement();
            handleDepositRequest();
            lastSettledEpochId += 1;
        }
        adminStartNewEpoch(settlePrice);
    }

    // 开始第一个 Epoch
    function adminStartNewEpoch(int settlePrice) private {
        require (epochId == lastSettledEpochId, "invalid epochId.");
        curEpochStartTime = getNow();
        curEpochEndTime = curEpochStartTime + period;
        maxStrikePrice = 130 * settlePrice / 100;
        minStrikePrice = 70 * settlePrice / 100;
        if (epochId == 0) {
            handleFirstDepositProcess();
        }
        // 获取预言机的价格, 制定期权产品。
        epochId += 1;
        curEpochTotalProfit = 0;
    }

    function optimisticWithDraw(int _amount) public isOwner {
        require (_amount * USDCDEMICAL <= optimisticBalance);
        bool success = USDCProtocol.transferFrom(address(this), owner, uint(_amount * USDCDEMICAL));
        require (success, "error transfer usdc.");
        optimisticBalance -= _amount * USDCDEMICAL;
    }
}
