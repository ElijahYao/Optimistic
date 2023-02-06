// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import "hardhat/console.sol";

contract LiquidityPoolManager{

    mapping (address => int) public liquidityPool;          // 资金池 addr -> USDC 数量
    mapping (address => int) public investorsWithdrawPool;  // 提款池 addr -> USDC 数量
    mapping (address => int) public newDepositRequest;      // 存款请求 addr -> USDC 数量
    mapping (address => int) public newWithdrawRequest;     // 提款请求 addr -> USDC 数量

    int public totalBalance = 0;                            // 资金池 USDC 数量
    int public curEpochLockedBalance = 0;                   // 当前交易周期锁定 USDC 数量

    address[] investors;                                    // 当前交易周期 LP 列表
    address[] newDepositors;                                // 当前交易周期新存款者列表
    address[] newWithdrawers;                               // 当前交易周期新提款

    // permission control start.
    mapping (address => bool) public permission;
    address public admin;

    constructor() {
        admin = msg.sender; 
        permission[admin] = true;
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
    // permission control end.

    function investorExist(address investor) private view returns (bool) {
        for (uint i = 0; i < investors.length; i++) {
            if (investors[i] == investor) {
                return true;
            }
        }
        return false;
    }

    function getTotalBalance() public view returns (int) {
        return totalBalance;
    }

    function getWithdrawAmount(address investor) public view returns (int) {
        return investorsWithdrawPool[investor];
    }

    function investorDeposit(address investor, int investAmount) external isOptimistic {
        if (newDepositRequest[investor] == 0) {
            newDepositors.push(investor);
        }
        newDepositRequest[investor] += investAmount;
    }

    function investorWithdrawRequest(address investor, int withdrawAmount) external isOptimistic {
        require(investorExist(investor), "invalid investor.");
        if (newWithdrawRequest[investor] == 0) {
            newWithdrawers.push(investor); 
        }
        newWithdrawRequest[investor] += withdrawAmount;
    }

    function investorActualWithdraw(address investor, int withdrawAmount) external isOptimistic {
        investorsWithdrawPool[investor] -= withdrawAmount;
    }

    function depositProcess() private {
        for (uint i = 0; i < newDepositors.length; ++i) {
            address depositor = newDepositors[i];
            liquidityPool[depositor] += newDepositRequest[depositor];
            totalBalance += newDepositRequest[depositor];
            if (investorExist(newDepositors[i]) == false) {
                investors.push(newDepositors[i]);
            }
            delete newDepositRequest[newDepositors[i]];
        }
        newDepositors = new address[](0);
    }

    function firstDepositProcess() external isOptimistic {
        depositProcess();
    }

    function settlementProcess(int liquidityPoolProfit) external isOptimistic {
        int curEpochTotalProfit = liquidityPoolProfit;
        int lastTotalBalance = totalBalance; 
        totalBalance = 0;
        console.log(uint(curEpochTotalProfit));
        for (uint i = 0; i < investors.length; ++i) {
            address investor = investors[i];
            if (liquidityPool[investor] == 0) {
                continue;
            }
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
        depositProcess();
    }
}
