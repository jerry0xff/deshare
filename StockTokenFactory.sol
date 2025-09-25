// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./StandardStockToken.sol";

contract StockTokenFactory is Ownable {
    // Main trading contract address
    address public tradingContract;
    
    // Store created stock token contracts
    mapping(string => address) public stockTokens;
    
    // Events
    event StockTokenCreated(string indexed stockSymbol, address tokenContract, address transferredTo);

    constructor() {}

    // Set main trading contract address
    function setTradingContract(address _tradingContract) external onlyOwner {
        require(_tradingContract != address(0), "Invalid address");
        tradingContract = _tradingContract;
    }

    // Create new stock token contract
    function createStockToken(string calldata _stockSymbol, string calldata _name) external onlyOwner {
        require(stockTokens[_stockSymbol] == address(0), "Stock token already exists");
        require(tradingContract != address(0), "Trading contract not set");
        
        // Deploy new standard ERC20 token contract
        StandardStockToken newToken = new StandardStockToken(_name, _stockSymbol);
        stockTokens[_stockSymbol] = address(newToken);
        
        // Transfer token contract ownership to StockTrading contract
        newToken.transferOwnership(tradingContract);
        
        emit StockTokenCreated(_stockSymbol, address(newToken), tradingContract);
    }

    // Get stock token contract address
    function getStockTokenAddress(string calldata _stockSymbol) external view returns (address) {
        return stockTokens[_stockSymbol];
    }
}