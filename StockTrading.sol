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
    enum OrderStatus { PENDING, FILLED, CANCELLED }

    // 订单结构体
    struct Order {
        address user;
        string stockSymbol;
        OrderType orderType;
        OrderSide orderSide;
        uint256 amount;
        uint256 price;
        uint256 timestamp;
        OrderStatus status;
        uint256 lockedAmount; // 锁定的USDC金额（买单）或股票数量（卖单）
        uint256 feeAmount;    // 已收取的手续费
    }

    // 股票凭证代币工厂合约地址
    address public stockTokenFactory;

    // 订单映射
    mapping(uint256 => Order) public orders;

    // 累积的手续费
    uint256 public accumulatedFees;

    // 事件
    event TokensMinted(address indexed user, string indexed stockSymbol, uint256 amount);
    event TokensBurnedAndUsdcTransferred(address indexed user, string indexed stockSymbol, uint256 amount, uint256 usdcAmount);
    event OrderCreated(uint256 indexed orderId, address indexed user, string stockSymbol, OrderType orderType, OrderSide orderSide, uint256 amount, uint256 price);
    event OrderCancelled(uint256 indexed orderId, address indexed user, string stockSymbol, uint256 refundAmount, uint256 feeRefundAmount);
    event FeeRateUpdated(uint256 newFeeRate);
    event USDCTransferred(address indexed from, address indexed to, uint256 amount);
    event FeeCharged(address indexed user, uint256 amount);
    event FeeWithdrawn(address indexed receiver, uint256 amount);

    // 手续费率 (basis points, 100 = 1%)
    uint256 public feeRate = 100;

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

    // 计算手续费
    function calculateFee(uint256 amount) public view returns (uint256) {
        return (amount * feeRate) / 10000;
    }

    // 生成订单ID
    function generateOrderId(address user, string memory stockSymbol) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            block.timestamp,
            user,
            stockSymbol,
            block.difficulty,
            block.number
        )));
    }

    // 提取手续费 - 仅feeReceiver可调用
    function withdrawFees() external {
        require(msg.sender == feeReceiver, "Only fee receiver can withdraw fees");
        require(accumulatedFees > 0, "No fees to withdraw");

        uint256 amount = accumulatedFees;
        accumulatedFees = 0;

        require(usdcContract.transfer(feeReceiver, amount), "Fee withdrawal failed");
        emit FeeWithdrawn(feeReceiver, amount);
    }

    // 创建买单
    function createBuyOrder(
        string calldata _stockSymbol,
        OrderType _orderType,
        uint256 _amount,
        uint256 _price,
        uint256 _expiresIn
    ) external returns (uint256) {
        require(feeReceiver != address(0) && fundReceiver != address(0), "Addresses not set");
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0 || _orderType == OrderType.MARKET, "Price required for limit order");

        // 计算总金额和手续费
        uint256 totalAmount = _amount;
        uint256 feeAmount = calculateFee(totalAmount);
        uint256 finalAmount = totalAmount + feeAmount;

        // 检查用户USDC余额
        require(usdcContract.balanceOf(msg.sender) >= finalAmount, "Insufficient USDC balance");

        // 检查授权额度
        require(usdcContract.allowance(msg.sender, address(this)) >= finalAmount, "Insufficient USDC allowance");

        // 转移USDC到资金接收地址
        require(usdcContract.transferFrom(msg.sender, fundReceiver, totalAmount), "USDC transfer failed");
        emit USDCTransferred(msg.sender, fundReceiver, totalAmount);

        // 收取手续费到合约
        require(usdcContract.transferFrom(msg.sender, address(this), feeAmount), "Fee transfer failed");
        accumulatedFees += feeAmount;
        emit FeeCharged(msg.sender, feeAmount);

        // 生成订单ID
        uint256 orderId = generateOrderId(msg.sender, _stockSymbol);

        // 保存订单信息
        orders[orderId] = Order({
            user: msg.sender,
            stockSymbol: _stockSymbol,
            orderType: _orderType,
            orderSide: OrderSide.BUY,
            amount: _amount,
            price: _price,
            timestamp: block.timestamp,
            status: OrderStatus.PENDING,
            lockedAmount: totalAmount,
            feeAmount: feeAmount
        });

        // 抛出订单创建事件
        emit OrderCreated(orderId, msg.sender, _stockSymbol, _orderType, OrderSide.BUY, _amount, _price);

        return orderId;
    }

    // 创建卖单
    function createSellOrder(
        string calldata _stockSymbol,
        OrderType _orderType,
        uint256 _amount,
        uint256 _price,
        uint256 _expiresIn
    ) external returns (uint256) {
        require(feeReceiver != address(0) && tokenReceiver != address(0), "Addresses not set");
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0 || _orderType == OrderType.MARKET, "Price required for limit order");

        // 检查用户是否有足够的股票凭证
        uint256 userBalance = stockTokenContract.balanceOf(msg.sender, _stockSymbol);
        require(userBalance >= _amount, "Insufficient stock balance");

        // 检查股票代币授权
        require(stockTokenContract.allowance(msg.sender, address(this)) >= _amount, "Insufficient stock token allowance");

        // 转移股票代币到代币接收地址
        require(stockTokenContract.transferFrom(msg.sender, tokenReceiver, _stockSymbol, _amount), "Stock token transfer failed");

        // 生成订单ID
        uint256 orderId = generateOrderId(msg.sender, _stockSymbol);

        // 保存订单信息
        orders[orderId] = Order({
            user: msg.sender,
            stockSymbol: _stockSymbol,
            orderType: _orderType,
            orderSide: OrderSide.SELL,
            amount: _amount,
            price: _price,
            timestamp: block.timestamp,
            status: OrderStatus.PENDING,
            lockedAmount: _amount,
            feeAmount: 0 // 卖单手续费在成交时收取
        });

        // 抛出订单创建事件
        emit OrderCreated(orderId, msg.sender, _stockSymbol, _orderType, OrderSide.SELL, _amount, _price);

        return orderId;
    }

    // 取消订单 - 仅管理员和 fundReceiver 可调用
    function cancelOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.user != address(0), "Order does not exist");
        require(order.status == OrderStatus.PENDING, "Order cannot be cancelled");
        require(msg.sender == owner() || msg.sender == fundReceiver, "Only owner or fundReceiver can cancel orders");

        // 更新订单状态
        order.status = OrderStatus.CANCELLED;

        if (order.orderSide == OrderSide.BUY) {
            // 买单：返还锁定的USDC和手续费
            require(usdcContract.transferFrom(fundReceiver, order.user, order.lockedAmount), "USDC refund failed");
            
            // 从合约返还手续费
            require(usdcContract.transfer(order.user, order.feeAmount), "Fee refund failed");
            accumulatedFees -= order.feeAmount;
            
            emit OrderCancelled(_orderId, order.user, order.stockSymbol, order.lockedAmount, order.feeAmount);
            emit USDCTransferred(fundReceiver, order.user, order.lockedAmount);
            emit USDCTransferred(address(this), order.user, order.feeAmount);
        } else {
            // 卖单：返还锁定的股票代币
            require(stockTokenContract.transferFrom(tokenReceiver, order.user, order.stockSymbol, order.lockedAmount), "Stock token refund failed");
            
            emit OrderCancelled(_orderId, order.user, order.stockSymbol, order.lockedAmount, 0);
        }
    }

    // 给用户 mint 股票凭证代币 - 仅管理员可调用
    function mintStockTokens(address _user, string calldata _stockSymbol, uint256 _amount) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(_amount > 0, "Amount must be greater than 0");
        require(stockTokenFactory != address(0), "Stock token factory not set");

        // 调用股票凭证代币合约的 mint 函数
        stockTokenContract.mint(_user, _stockSymbol, _amount);
        emit TokensMinted(_user, _stockSymbol, _amount);
    }

    // 销毁用户的股票凭证代币并转移 USDC - 仅管理员可调用
    function burnStockTokensAndTransferUsdc(
        address _user,
        string calldata _stockSymbol,
        uint256 _amount,
        uint256 _usdcAmount
    ) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(_amount > 0, "Amount must be greater than 0");
        require(_usdcAmount > 0, "USDC amount must be greater than 0");
        require(stockTokenFactory != address(0), "Stock token factory not set");
        require(fundReceiver != address(0), "Fund receiver not set");

        // 检查用户是否有足够的股票凭证
        uint256 userBalance = stockTokenContract.balanceOf(_user, _stockSymbol);
        require(userBalance >= _amount, "Insufficient stock balance");

        // 销毁股票凭证代币
        stockTokenContract.burn(_user, _stockSymbol, _amount);

        // 转移USDC给用户
        require(usdcContract.transferFrom(fundReceiver, _user, _usdcAmount), "USDC transfer failed");

        emit TokensBurnedAndUsdcTransferred(_user, _stockSymbol, _amount, _usdcAmount);
    }

    // 查询订单信息
    function getOrder(uint256 _orderId) external view returns (
        address user,
        string memory stockSymbol,
        OrderType orderType,
        OrderSide orderSide,
        uint256 amount,
        uint256 price,
        uint256 timestamp,
        OrderStatus status,
        uint256 lockedAmount,
        uint256 feeAmount
    ) {
        Order storage order = orders[_orderId];
        return (
            order.user,
            order.stockSymbol,
            order.orderType,
            order.orderSide,
            order.amount,
            order.price,
            order.timestamp,
            order.status,
            order.lockedAmount,
            order.feeAmount
        );
    }
}