// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";

import "./IStockToken.sol";

contract StockTokenFactory is Ownable {
    // 股票凭证代币合约地址
    IStockToken public stockTokenContract;

    // USDC代币合约地址
    IERC20 public usdcContract;

    // 主合约地址
    address public tradingContract;

    // 事件
    event StockTokenCreated(string indexed stockSymbol);
    event TokensTransferredToContract(string indexed stockSymbol, uint256 amount);
    event TokensBurned(string indexed stockSymbol, uint256 amount);

    // 构造函数
    constructor(address _stockTokenContract, address _usdcContract) {
        stockTokenContract = IStockToken(_stockTokenContract);
        usdcContract = IERC20(_usdcContract);
    }

    // 设置主合约地址
    function setTradingContract(address _tradingContract) external onlyOwner {
        require(_tradingContract != address(0), "Invalid address");
        tradingContract = _tradingContract;
    }

    // 创建股票凭证代币 - 管理员专用
    function createStockToken(string calldata _stockSymbol) external onlyOwner {
        // 实际应用中可能需要初始化代币的相关参数
        // 这里我们简单地记录创建事件
        emit StockTokenCreated(_stockSymbol);
    }

    // 转移代币到主合约
    function transferTokensToContract(string calldata _stockSymbol, uint256 _amount) external onlyOwner {
        require(tradingContract != address(0), "Trading contract not set");
        require(_amount > 0, "Amount must be greater than 0");

        // 从工厂合约转移代币到主合约
        bool success = stockTokenContract.transfer(tradingContract, _stockSymbol, _amount);
        require(success, "Transfer failed");

        emit TokensTransferredToContract(_stockSymbol, _amount);
    }

    // 销毁代币
    function burnTokens(string calldata _stockSymbol, uint256 _amount) external onlyOwner {
        require(_amount > 0, "Amount must be greater than 0");

        // 销毁工厂合约中的代币
        stockTokenContract.burn(address(this), _stockSymbol, _amount);

        emit TokensBurned(_stockSymbol, _amount);
    }
}