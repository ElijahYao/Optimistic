// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface ILeverageShort {
    function getGlobalUPL(int futurePrice) external view returns (int);

    function userOpenOrder(int marginAmount, int leverage, int futurePrice, address trader) external returns (int);

    function userCloseOrder(int closeTokenAmount, int futurePrice, address trader) external returns (int);
}
