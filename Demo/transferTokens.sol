// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract transferTokens {

    address public owner;
    ERC20 public WETH;
    ERC20 public USDC;

    uint public transfer_eth_amount = 5 * 10 ** 16;
    uint public transfer_weth_amount = 5 * 10 ** 16;
    uint public transfer_usdc_amount = 1000 * 10 ** 6;

    constructor() {
        owner = msg.sender; 
        USDC = ERC20(0x07865c6E87B9F70255377e024ace6630C1Eaa37F);
        WETH = ERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);
    }

    modifier isOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    receive() external payable {
    }

    function set_transfer_eth_amount(uint eth_amount) public isOwner {
        transfer_eth_amount = eth_amount;
    }

    function set_transfer_weth_amount(uint weth_amount) public isOwner {
        transfer_weth_amount = weth_amount;
    }

    function set_transfer_usdc_amount(uint usdc_amount) public isOwner {
        transfer_usdc_amount = usdc_amount;
    }

    function get_eth_balance() public view returns(uint) {
        return address(this).balance;
    }

    function get_weth_balance() public view returns(uint) {
        return WETH.balanceOf(address(this));
    }

    function get_usdc_balance() public view returns(uint) {
        return USDC.balanceOf(address(this));
    }

    function transfer(address payable recipient) public isOwner {
        WETH.transfer(recipient, transfer_weth_amount);
        USDC.transfer(recipient, transfer_usdc_amount);
        recipient.transfer(transfer_eth_amount);
    }

    function emergencyWithdraw() public isOwner {
        uint eth_balance = get_eth_balance();
        uint weth_balance = get_weth_balance();
        uint usdc_balance = get_usdc_balance();
        address payable recipient = payable(owner);
        WETH.transfer(recipient, weth_balance);
        USDC.transfer(recipient, usdc_balance);
        recipient.transfer(eth_balance);
    }


}
