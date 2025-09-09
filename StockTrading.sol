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

    // 手续费率（以基点表示，1个基点 = 0.01%）
    uint256 public feeRate;

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

    // 订单映射
    mapping(uint256 => Order) public orders;

    // 事件
    event OrderCreated(uint256 orderId, address user, string stockSymbol, OrderType orderType, OrderSide orderSide, uint256 amount, uint256 price);
    event OrderFilled(uint256 orderId);
    event OrderCancelled(uint256 orderId);
    event USDCTransferred(address from, address to, uint256 amount);
    event FeeCharged(address user, uint256 amount, bool isUSDC);
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event FeesWithdrawn(address receiver, uint256 amount, bool isUSDC);

    // 构造函数
    constructor(address _stockTokenContract, address _usdcContract, address _fundReceiver) {
        stockTokenContract = IStockToken(_stockTokenContract);
        usdcContract = IERC20(_usdcContract);
        fundReceiver = _fundReceiver;
        feeReceiver = msg.sender;
        tokenReceiver = msg.sender;
        feeRate = 100; // 默认手续费率为1%（100个基点）
    }

    // 设置接收地址
    function setReceivers(address _fundReceiver, address _tokenReceiver) external onlyOwner {
        fundReceiver = _fundReceiver;
        tokenReceiver = _tokenReceiver;
    }

    // 设置手续费率
    function setFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= 1000, "Fee rate cannot exceed 10%");
        uint256 oldRate = feeRate;
        feeRate = _feeRate;
        emit FeeRateUpdated(oldRate, _feeRate);
    }

    // 创建卖单
    function createSellOrder(string calldata _stockSymbol, OrderType _orderType, uint256 _amount, uint256 _price, uint256 _expiresIn) external returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        if (_orderType == OrderType.LIMIT) {
            require(_price > 0, "Price required for limit order");
        }

        // 检查用户余额
        address tokenAddress = stockTokenContract.getStockTokenAddress(_stockSymbol);
        require(tokenAddress != address(0), "Stock token not found");
        IStockToken token = IStockToken(tokenAddress);

        // 计算手续费
        uint256 feeAmount = (_amount * feeRate) / 10000;
        uint256 totalAmount = _amount + feeAmount;

        require(token.balanceOf(msg.sender, _stockSymbol) >= totalAmount, "Insufficient stock balance");
        require(token.allowance(msg.sender, address(this)) >= totalAmount, "Insufficient stock allowance");

        // 生成订单ID
        uint256 orderId = generateOrderId(msg.sender, _stockSymbol);

        // 转移代币到接收地址
        token.transferFrom(msg.sender, tokenReceiver, _stockSymbol, _amount);
        // 收取手续费
        token.transferFrom(msg.sender, address(this), _stockSymbol, feeAmount);
        emit FeeCharged(msg.sender, feeAmount, false);

        // 创建订单
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
            feeAmount: feeAmount
        });

        emit OrderCreated(orderId, msg.sender, _stockSymbol, _orderType, OrderSide.SELL, _amount, _price);
        return orderId;
    }

    // 创建买单
    function createBuyOrder(string calldata _stockSymbol, OrderType _orderType, uint256 _amount, uint256 _price, uint256 _expiresIn) external returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        if (_orderType == OrderType.LIMIT) {
            require(_price > 0, "Price required for limit order");
        }

        // 计算所需USDC金额
        uint256 orderValue = _amount * _price;
        uint256 feeAmount = (orderValue * feeRate) / 10000;
        uint256 totalAmount = orderValue + feeAmount;

        // 检查用户余额和授权额度
        require(usdcContract.balanceOf(msg.sender) >= totalAmount, "Insufficient USDC balance");
        require(usdcContract.allowance(msg.sender, address(this)) >= totalAmount, "Insufficient USDC allowance");

        // 生成订单ID
        uint256 orderId = generateOrderId(msg.sender, _stockSymbol);

        // 转移USDC到接收地址
        usdcContract.transferFrom(msg.sender, fundReceiver, orderValue);
        emit USDCTransferred(msg.sender, fundReceiver, orderValue);

        // 收取手续费
        usdcContract.transferFrom(msg.sender, address(this), feeAmount);
        emit FeeCharged(msg.sender, feeAmount, true);

        // 创建订单
        orders[orderId] = Order({
            user: msg.sender,
            stockSymbol: _stockSymbol,
            orderType: _orderType,
            orderSide: OrderSide.BUY,
            amount: _amount,
            price: _price,
            timestamp: block.timestamp,
            status: OrderStatus.PENDING,
            lockedAmount: orderValue,
            feeAmount: feeAmount
        });

        emit OrderCreated(orderId, msg.sender, _stockSymbol, _orderType, OrderSide.BUY, _amount, _price);
        return orderId;
    }

    // 取消订单
    function cancelOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.user != address(0), "Order does not exist");
        require(order.status == OrderStatus.PENDING, "Order cannot be cancelled");
        require(msg.sender == order.user || msg.sender == owner(), "Not authorized");

        if (order.orderSide == OrderSide.SELL) {
            // 返还代币
            address tokenAddress = stockTokenContract.getStockTokenAddress(order.stockSymbol);
            require(tokenAddress != address(0), "Stock token not found");
            IStockToken token = IStockToken(tokenAddress);
            token.transferFrom(tokenReceiver, order.user, order.stockSymbol, order.lockedAmount);
            // 返还手续费
            token.transfer(order.user, order.stockSymbol, order.feeAmount);
        } else {
            // 返还USDC
            usdcContract.transferFrom(fundReceiver, order.user, order.lockedAmount);
            // 返还手续费
            usdcContract.transfer(order.user, order.feeAmount);
        }

        order.status = OrderStatus.CANCELLED;
        emit OrderCancelled(_orderId);
    }

    // 生成订单ID
    function generateOrderId(address user, string memory stockSymbol) public view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(user, stockSymbol, block.timestamp)));
    }

    // 计算手续费
    function calculateFee(uint256 amount) public view returns (uint256) {
        return (amount * feeRate) / 10000;
    }

    // 提取手续费
    function withdrawFees(bool isUSDC) external onlyOwner {
        if (isUSDC) {
            uint256 balance = usdcContract.balanceOf(address(this));
            require(balance > 0, "No USDC fees to withdraw");
            usdcContract.transfer(feeReceiver, balance);
            emit FeesWithdrawn(feeReceiver, balance, true);
        } else {
            address tokenAddress = stockTokenContract.getStockTokenAddress("AAPL");
            require(tokenAddress != address(0), "Stock token not found");
            IStockToken token = IStockToken(tokenAddress);
            uint256 balance = token.balanceOf(address(this), "AAPL");
            require(balance > 0, "No stock token fees to withdraw");
            token.transfer(feeReceiver, "AAPL", balance);
            emit FeesWithdrawn(feeReceiver, balance, false);
        }
    }
}