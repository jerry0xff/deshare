// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStockToken {
    function mint(address to, string calldata stockSymbol, uint256 amount) external;
    function burn(address from, string calldata stockSymbol, uint256 amount) external;
    function balanceOf(address account, string calldata stockSymbol) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, string calldata stockSymbol, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, string calldata stockSymbol, uint256 amount) external returns (bool);
    function getStockTokenAddress(string calldata stockSymbol) external view returns (address);
}