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
}
