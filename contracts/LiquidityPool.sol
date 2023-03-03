// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract LiquidityPool {
    address public owner;

    // LP 赞助的 Token
    mapping(address => int) public tokenBalance;
    int public totalToken;

    int public totalUSDT;
    int public lockedUSDT;

    int public totalWETH;
    int public lockedWETH;

    int public constant tokenDemical = 10 ** 6;

    constructor() {
        owner = msg.sender;
        totalToken = 0;
    }

    /*
        ETH 数量 = totalWETH / 10^9 
        ETH/USDT 价格 = _futurePrice / 10^2
        USDT 精度 = 10^6 
    */
    function getLiquidityPoolValue(int _futurePrice) public view returns (int) {
        return (totalWETH * _futurePrice) / (10 ** 5) + totalUSDT;
    }

    /*
        USDT 数量 = _usdtAmount / 10^6
        Token 价格 = _tokenAmount / 10^6 
    */
    function userDepositUSDT(int _usdtAmount, int _userTokenInc, address user) public {
        totalUSDT += _usdtAmount;
        tokenBalance[user] += _userTokenInc;
        totalToken += _userTokenInc;
    }

    /*
        WETH 数量 = _wethAmount / 10^9
    */
    function userDepositETH(int _wethAmount, int _userTokenInc, address user) public {
        totalWETH += _wethAmount;
        tokenBalance[user] += _userTokenInc;
        totalToken += _userTokenInc;
    }

    function userWithdraw(int _tokenAmount, address user) public {
        require(tokenBalance[user] >= _tokenAmount, "insufficient token balance.");
        tokenBalance[user] -= _tokenAmount;
        totalToken -= _tokenAmount;
    }

    function lockLiquidityUSDT(int _usdtAmount) public returns (bool) {
        require(totalUSDT - lockedUSDT >= _usdtAmount, "insufficient USDT liquidity.");
        lockedUSDT += _usdtAmount;
        return true;
    }

    function unlockLiquidityUSDT(int _usdtAmount) public returns (bool) {
        lockedUSDT -= _usdtAmount;
        return true;
    }

    function updatePoolUSDT(int _usdtAmount) public returns (bool) {
        totalUSDT += _usdtAmount;
        return true;
    }

    function lockLiquidityWETH(int _wethAmount) public returns (bool) {
        return true;
    }

    function unlockLiquidityWETH(int _wethAmount) public returns (bool) {}

    function updatePoolWETH(int _wethAmount) public returns (bool) {}
}
