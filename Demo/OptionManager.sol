// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "contracts/IOptionManager.sol";

contract OptionManager is IOptionManager{

    mapping (address => OptionOrder[]) public traderCurEpochOptionOrders;
    mapping (address => OptionOrder[]) public traderHistoryOptionOrders;
    mapping (uint => int) public settlePriceRecords;
    mapping (address => int) public traderProfitPool;
    mapping (address => bool) public permission;
    address public admin;
    
    address[] public curEpochTraders;

    // 当前 Epoch Options 售卖获得的利润
    int public immutable USDCDEMICAL = 10 ** 6;
    int public curEpochTotalProfit;

    constructor() {
        admin = msg.sender; 
    }

    modifier isAdmin() {
        require(msg.sender == admin, "caller is not admin.");
        _;
    }

    modifier isOptimistic() {
        require(permission[msg.sender] == true, "caller is not optimistic.");
        _;
    }

    function addPermission(address optmisticAddr) public isAdmin {
        permission[optmisticAddr] = true;
    }

    function getHistoryOptions() public view returns (OptionOrder[] memory) {
        return traderHistoryOptionOrders[msg.sender];
    }

    function getCurEpochOptions() public view returns (OptionOrder[] memory) {
        return traderCurEpochOptionOrders[msg.sender];
    }

    function getTraderAvaliableBalance(address trader) external view returns (int) {
        return traderProfitPool[trader];                
    }

    function resetCurEpochProfit() external isOptimistic {
        curEpochTotalProfit = 0;
    }

    function traderWithdraw(address trader, int withdrawAmount) external isOptimistic {
        traderProfitPool[trader] -= withdrawAmount;
    }

    function traderDeposit(address trader, int depositAmount) external isOptimistic {
        traderProfitPool[trader] += depositAmount;
    }

    function addOption(uint strikeTime, int strikePrice, bool optionType, uint epochId, int buyPrice, int orderSize, address trader) external isOptimistic {
        
        traderProfitPool[trader] -= orderSize * buyPrice;

        Option memory option;
        OptionOrder memory buyOptionOrder;

        option.strikePrice = strikePrice;
        option.strikeTime = strikeTime;
        option.optionType = optionType;

        buyOptionOrder.option = option;
        buyOptionOrder.orderSize = orderSize;
        buyOptionOrder.state = OptionOrderState.Opened;
        buyOptionOrder.buyPrice = buyPrice;
        buyOptionOrder.epochId = epochId;

        if (traderCurEpochOptionOrders[trader].length == 0) {
            curEpochTraders.push(trader);
        }

        traderCurEpochOptionOrders[trader].push(buyOptionOrder);
        curEpochTotalProfit += buyPrice * orderSize;
    }

    /**
     * @notice returns 这一轮平台方的盈亏
     * @param settlePrice 结算价格
     * @param epochId 当前 epoch 轮数
     **/
    function calculateTraderProfit(int settlePrice, uint epochId) external isOptimistic returns (int) {
        require (settlePrice >= 0);
        settlePriceRecords[epochId] = settlePrice;
        for (uint i = 0; i < curEpochTraders.length; ++i) {
            address trader = curEpochTraders[i];
            int curTraderSettledSize = 0;
            for (uint j = 0; j < traderCurEpochOptionOrders[trader].length; ++j) {

                // 如果已经 sell 了, 不进行结算
                if (traderCurEpochOptionOrders[trader][j].state == OptionOrderState.Selled) {
                    continue;
                }
                // 如果已经 settle 了, 不进行结算
                if (traderCurEpochOptionOrders[trader][j].state == OptionOrderState.Settled) {
                    continue;
                }
                traderCurEpochOptionOrders[trader][j].state = OptionOrderState.Settled;
                traderCurEpochOptionOrders[trader][j].settlePrice = settlePrice;
                int orderSize = traderCurEpochOptionOrders[trader][j].orderSize;
                // Settle CALL
                if (traderCurEpochOptionOrders[trader][j].option.optionType == true) {
                    if (settlePrice >= traderCurEpochOptionOrders[trader][j].option.strikePrice) {
                        curEpochTotalProfit -= orderSize * USDCDEMICAL;
                        curTraderSettledSize += orderSize;
                        traderCurEpochOptionOrders[trader][j].sellPrice = 1;
                    }
                // Settle PUT
                } else {
                    if (settlePrice <= traderCurEpochOptionOrders[trader][j].option.strikePrice) {
                        curEpochTotalProfit -= orderSize * USDCDEMICAL;
                        curTraderSettledSize += orderSize;
                        traderCurEpochOptionOrders[trader][j].sellPrice = 1;
                    }
                }
                OptionOrder memory optionOrder = traderCurEpochOptionOrders[trader][j];
                traderHistoryOptionOrders[trader].push(optionOrder);
            }
            traderProfitPool[trader] += curTraderSettledSize * USDCDEMICAL;
            delete traderCurEpochOptionOrders[trader];
        }
        curEpochTraders = new address[](0);
        return curEpochTotalProfit;
    }
}
