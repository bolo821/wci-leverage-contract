// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IWCIContract {
    function totalSupply() external view returns (uint256);
    function decimals() external pure returns (uint8);
    function symbol() external pure returns (string memory);
    function name() external pure returns (string memory);
    function getOwner() external view returns (address);
    function maxBuyTxTokens() external view returns (uint256);
    function maxSellTxTokens() external view returns (uint256);
    function maxWalletTokens() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address holder, address spender) external view returns (uint256);

    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}