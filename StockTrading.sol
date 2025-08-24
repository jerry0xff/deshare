// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";

import "./IStockToken.sol";

contract StockTrading is Ownable {
    // 地址配置
    address public feeReceiver;
    address public fundReceiver;
    address public tokenReceiver;

    // 股票凭证代币合约地址
    IStockToken public stockTokenContract;

    // USDC代币合约地址
    IERC20 public usdcContract;

    // 交易类型枚举
    enum OrderType { LIMIT, MARKET }
    enum OrderSide { BUY, SELL }

    // 股票凭证代币工厂合约地址
    address public stockTokenFactory;

    // 事件
    event TokensMinted(address indexed user, string indexed stockSymbol, uint256 amount);
    event TokensBurnedAndUsdcTransferred(address indexed user, string indexed stockSymbol, uint256 amount, uint256 usdcAmount);

    // 手续费率 (basis points, 100 = 1%)
    uint256 public feeRate = 100;

    // 事件
    event OrderCreated(uint256 indexed orderId, address indexed user, string stockSymbol, OrderType orderType, OrderSide orderSide, uint256 amount, uint256 price);
    event FeeRateUpdated(uint256 newFeeRate);

    // 构造函数
    constructor(address _stockTokenContract, address _usdcContract, address _stockTokenFactory) {
        stockTokenContract = IStockToken(_stockTokenContract);
        usdcContract = IERC20(_usdcContract);
        stockTokenFactory = _stockTokenFactory;
    }

    // 设置手续费接收地址
    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        require(_feeReceiver != address(0), "Invalid address");
        feeReceiver = _feeReceiver;
    }

    // 设置交易资金接收地址
    function setFundReceiver(address _fundReceiver) external onlyOwner {
        require(_fundReceiver != address(0), "Invalid address");
        fundReceiver = _fundReceiver;
    }

    // 设置股票凭证代币接收地址
    function setTokenReceiver(address _tokenReceiver) external onlyOwner {
        require(_tokenReceiver != address(0), "Invalid address");
        tokenReceiver = _tokenReceiver;
    }

    // 设置股票凭证代币工厂合约地址
    function setStockTokenFactory(address _stockTokenFactory) external onlyOwner {
        require(_stockTokenFactory != address(0), "Invalid address");
        stockTokenFactory = _stockTokenFactory;
    }

    // 设置手续费率 (basis points)
    function setFeeRate(uint256 _newFeeRate) external onlyOwner {
        require(_newFeeRate <= 1000, "Fee rate too high (max 10%)");
        feeRate = _newFeeRate;
        emit FeeRateUpdated(_newFeeRate);
    }

    // 创建买单 - 仅抛出事件
    function createBuyOrder(
        string calldata _stockSymbol,
        OrderType _orderType,
        uint256 _amount,
        uint256 _price,
        uint256 _expiresIn
    ) external {
        require(feeReceiver != address(0) && fundReceiver != address(0), "Addresses not set");
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0 || _orderType == OrderType.MARKET, "Price required for limit order");

        // 生成唯一订单ID (使用时间戳和发送者地址)
        uint256 orderId = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, _stockSymbol)));

        // 抛出订单创建事件
        emit OrderCreated(orderId, msg.sender, _stockSymbol, _orderType, OrderSide.BUY, _amount, _price);
    }

    // 创建卖单 - 仅抛出事件
    function createSellOrder(
        string calldata _stockSymbol,
        OrderType _orderType,
        uint256 _amount,
        uint256 _price,
        uint256 _expiresIn
    ) external {
        require(feeReceiver != address(0) && tokenReceiver != address(0), "Addresses not set");
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0 || _orderType == OrderType.MARKET, "Price required for limit order");

        // 检查用户是否有足够的股票凭证
        uint256 userBalance = stockTokenContract.balanceOf(msg.sender, _stockSymbol);
        require(userBalance >= _amount, "Insufficient stock balance");

        // 生成唯一订单ID (使用时间戳和发送者地址)
        uint256 orderId = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, _stockSymbol)));

        // 抛出订单创建事件
        emit OrderCreated(orderId, msg.sender, _stockSymbol, _orderType, OrderSide.SELL, _amount, _price);
    }

    // 给用户 mint 股票凭证代币 - 仅管理员可调用
    function mintStockTokens(address _user, string calldata _stockSymbol, uint256 _amount) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(_amount > 0, "Amount must be greater than 0");
        require(stockTokenFactory != address(0), "Stock token factory not set");

        // 在实际应用中，这里应该调用股票凭证代币合约的 mint 函数
        // 由于我们没有完整实现股票凭证代币合约，这里仅抛出事件
        emit TokensMinted(_user, _stockSymbol, _amount);
    }

    // 销毁用户的股票凭证代币并转移 USDC - 仅管理员可调用
    function burnStockTokensAndTransferUsdc(address _user, string calldata _stockSymbol, uint256 _amount, uint256 _usdcAmount) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(_amount > 0, "Amount must be greater than 0");
        require(_usdcAmount > 0, "USDC amount must be greater than 0");
        require(stockTokenFactory != address(0), "Stock token factory not set");
        require(fundReceiver != address(0), "Fund receiver not set");

        // 检查用户是否有足够的股票凭证
        uint256 userBalance = stockTokenContract.balanceOf(_user, _stockSymbol);
        require(userBalance >= _amount, "Insufficient stock balance");

        // 在实际应用中，这里应该调用股票凭证代币合约的 burn 函数
        // 以及 USDC 合约的 transfer 函数
        // 由于我们没有完整实现这些合约，这里仅抛出事件
        emit TokensBurnedAndUsdcTransferred(_user, _stockSymbol, _amount, _usdcAmount);
    }
}