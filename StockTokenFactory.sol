// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./StandardStockToken.sol";

contract StockTokenFactory is Ownable {
    // 主合约地址
    address public tradingContract;
    
    // 存储已创建的股票代币合约
    mapping(string => address) public stockTokens;
    
    // 事件
    event StockTokenCreated(string indexed stockSymbol, address tokenContract, address transferredTo);

    constructor() {}

    // 设置主合约地址
    function setTradingContract(address _tradingContract) external onlyOwner {
        require(_tradingContract != address(0), "Invalid address");
        tradingContract = _tradingContract;
    }

    // 创建新的股票代币合约
    function createStockToken(string calldata _stockSymbol, string calldata _name) external onlyOwner {
        require(stockTokens[_stockSymbol] == address(0), "Stock token already exists");
        require(tradingContract != address(0), "Trading contract not set");
        
        // 部署新的标准ERC20代币合约
        StandardStockToken newToken = new StandardStockToken(_name, _stockSymbol);
        stockTokens[_stockSymbol] = address(newToken);
        
        // 将代币合约所有权转移给StockTrading合约
        newToken.transferOwnership(tradingContract);
        
        emit StockTokenCreated(_stockSymbol, address(newToken), tradingContract);
    }

    // 获取股票代币合约地址
    function getStockTokenAddress(string calldata _stockSymbol) external view returns (address) {
        return stockTokens[_stockSymbol];
    }
}