// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

interface IOptionManager {

    enum OptionOrderState {Opened, Selled, Settled}

    struct Option {
        int strikePrice;
        uint strikeTime;
        bool optionType;
    }

    struct OptionOrder {

        Option option;
        OptionOrderState state;

        uint epochId;
        
        int orderSize;
        int buyPrice;
        int sellPrice;
        int settlePrice;
    }

    function addOption(uint strikeTime, int strikePrice, bool optionType, uint epochId, int buyPrice, int orderSize, address buyer) external returns (bool);
}
