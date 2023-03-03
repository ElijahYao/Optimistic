// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface ILiquidityPool {
    function totalUSDT() external view returns (int);

    function lockedUSDT() external view returns (int);

    function totalToken() external view returns (int);

    function lockLiquidityUSDT(int _usdtAmount) external returns (bool);

    function unlockLiquidityUSDT(int _usdtAmount) external returns (bool);

    function updatePoolUSDT(int _usdtAmount) external returns (bool);

    function getLiquidityPoolValue(int _futurePrice) external view returns (int);

    function userDepositUSDT(int _usdtAmount, int _userTokenInc, address user) external;
}
