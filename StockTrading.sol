// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./StandardStockToken.sol";

contract StockTrading is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // 地址配置
    address public feeReceiver;
    address public fundReceiver;
    address public tokenReceiver;

    // USDC代币合约地址
    IERC20 public usdcContract;

    // StockTokenFactory合约地址
    address public stockTokenFactory;

    // 手续费率（以基点表示，1个基点 = 0.01%）
    uint256 public feeRate;

    // 安全限制
    uint256 public constant MAX_ORDER_AMOUNT = 1e26; // 最大订单数量 (考虑8位小数)
    uint256 public constant MAX_PRICE = 1e12; // 最大单价 (考虑6位小数)
    uint256 public constant MIN_FEE_RATE = 1; // 最小手续费率 0.01%
    
    // 订单计数器 (用于生成安全的订单ID)
    uint256 private orderNonce;

    // 交易类型枚举
    enum OrderType { LIMIT, MARKET }
    enum OrderSide { BUY, SELL }

    // 事件 - 订单相关
    event OrderCreated(
        uint256 indexed orderId, 
        address indexed user, 
        string stockSymbol,           // 移除 indexed
        OrderType orderType, 
        OrderSide orderSide, 
        uint256 amount, 
        uint256 price,
        uint256 feeAmount,           // 新增手续费金额
        uint256 expiresAt,           // 新增过期时间
        uint256 timestamp
    );
    
    event OrderFilled(uint256 indexed orderId, uint256 timestamp);
    event OrderCancelled(uint256 indexed orderId, uint256 timestamp);
    
    // 事件 - 资金和代币转移
    event USDCTransferred(address indexed from, address indexed to, uint256 amount);
    event StockTokenTransferred(address indexed from, address indexed to, string indexed stockSymbol, uint256 amount);
    
    // 事件 - 手续费和配置
    event FeeCharged(address indexed user, uint256 amount, bool isUSDC);
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event FeesWithdrawn(address indexed receiver, uint256 amount, bool isUSDC);
    
    // 事件 - 代币铸造和销毁
    event StockTokensMinted(string indexed stockSymbol, address indexed to, uint256 amount);
    event StockTokensBurned(string indexed stockSymbol, address indexed from, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _usdcContract, address _stockTokenFactory) public initializer {
        require(_usdcContract != address(0), "Invalid USDC address");
        require(_stockTokenFactory != address(0), "Invalid factory address");
        
        __Ownable_init();
        __UUPSUpgradeable_init();
        
        usdcContract = IERC20(_usdcContract);
        stockTokenFactory = _stockTokenFactory;
        feeReceiver = msg.sender;
        fundReceiver = msg.sender;
        tokenReceiver = msg.sender;
        feeRate = 100; // 默认手续费率为1%（100个基点）
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // 设置接收地址
    function setReceivers(address _fundReceiver, address _tokenReceiver, address _feeReceiver) external onlyOwner {
        require(_fundReceiver != address(0), "Invalid fund receiver");
        require(_tokenReceiver != address(0), "Invalid token receiver");
        require(_feeReceiver != address(0), "Invalid fee receiver");
        
        fundReceiver = _fundReceiver;
        tokenReceiver = _tokenReceiver;
        feeReceiver = _feeReceiver;
    }

    // 设置手续费率
    function setFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate >= MIN_FEE_RATE, "Fee rate too low");
        require(_feeRate <= 1000, "Fee rate cannot exceed 10%");
        uint256 oldRate = feeRate;
        feeRate = _feeRate;
        emit FeeRateUpdated(oldRate, _feeRate);
    }

    // 设置Factory合约地址
    function setStockTokenFactory(address _stockTokenFactory) external onlyOwner {
        require(_stockTokenFactory != address(0), "Invalid factory address");
        stockTokenFactory = _stockTokenFactory;
    }

    // 铸造股票代币 - 只有管理员可调用
    function mintStockTokens(string calldata _stockSymbol, address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than 0");
        
        // 从Factory获取代币合约地址
        address tokenAddress = _getStockTokenAddress(_stockSymbol);
        require(tokenAddress != address(0), "Stock token does not exist");
        
        // 调用代币合约的mint功能
        StandardStockToken(tokenAddress).mint(_to, _amount);
        
        emit StockTokensMinted(_stockSymbol, _to, _amount);
    }

    // 销毁股票代币 - 只有管理员可调用
    function burnStockTokens(string calldata _stockSymbol, address _from, uint256 _amount) external onlyOwner {
        require(_from != address(0), "Invalid holder address");
        require(_amount > 0, "Amount must be greater than 0");
        
        // 从Factory获取代币合约地址
        address tokenAddress = _getStockTokenAddress(_stockSymbol);
        require(tokenAddress != address(0), "Stock token does not exist");
        
        // 调用代币合约的burn功能
        StandardStockToken(tokenAddress).burn(_from, _amount);
        
        emit StockTokensBurned(_stockSymbol, _from, _amount);
    }

    // 创建卖单 - 不存储订单，只发送事件
    function createSellOrder(
        string calldata _stockSymbol, 
        OrderType _orderType, 
        uint256 _amount, 
        uint256 _price,
        uint256 _expiresAt    // 新增过期时间参数
    ) external returns (uint256) {
        require(_amount > 0 && _amount <= MAX_ORDER_AMOUNT, "Invalid amount");
        if (_orderType == OrderType.LIMIT) {
            require(_price > 0 && _price <= MAX_PRICE, "Invalid price");
        }

        // 获取股票代币合约
        address tokenAddress = _getStockTokenAddress(_stockSymbol);
        require(tokenAddress != address(0), "Stock token does not exist");
        
        StandardStockToken stockToken = StandardStockToken(tokenAddress);

        // 计算手续费
        uint256 feeAmount = (_amount * feeRate) / 10000;
        uint256 totalAmount = _amount + feeAmount;

        // 检查余额和授权
        require(stockToken.balanceOf(msg.sender) >= totalAmount, "Insufficient stock balance");
        require(stockToken.allowance(msg.sender, address(this)) >= totalAmount, "Insufficient stock allowance");

        // 生成订单ID
        uint256 orderId = _generateOrderId(msg.sender, _stockSymbol);

        // 转移代币到接收地址
        require(stockToken.transferFrom(msg.sender, tokenReceiver, _amount), "Stock transfer failed");
        emit StockTokenTransferred(msg.sender, tokenReceiver, _stockSymbol, _amount);

        // 收取手续费
        require(stockToken.transferFrom(msg.sender, address(this), feeAmount), "Fee transfer failed");
        emit FeeCharged(msg.sender, feeAmount, false);

        // 发送订单创建事件
        emit OrderCreated(
            orderId,
            msg.sender,
            _stockSymbol,
            _orderType,
            OrderSide.SELL,
            _amount,
            _price,
            feeAmount,           // 手续费金额
            _expiresAt,         // 过期时间
            block.timestamp
        );
        
        return orderId;
    }

    // 创建买单 - 不存储订单，只发送事件
    function createBuyOrder(
        string calldata _stockSymbol, 
        OrderType _orderType, 
        uint256 _amount, 
        uint256 _price,
        uint256 _expiresAt    // 新增过期时间参数
    ) external returns (uint256) {
        require(_amount > 0 && _amount <= MAX_ORDER_AMOUNT, "Invalid amount");
        if (_orderType == OrderType.LIMIT) {
            require(_price > 0 && _price <= MAX_PRICE, "Invalid price");
        }

        // 计算所需USDC金额 - 防止溢出
        require(_amount <= type(uint256).max / _price, "Amount * price overflow");
        uint256 orderValue = (_amount * _price) / 10**8; // 除以10^8转换为USDC金额(6位小数)
        uint256 feeAmount = (orderValue * feeRate) / 10000;
        require(orderValue <= type(uint256).max - feeAmount, "Total amount overflow");
        uint256 totalAmount = orderValue + feeAmount;

        // 检查USDC余额和授权
        require(usdcContract.balanceOf(msg.sender) >= totalAmount, "Insufficient USDC balance");
        require(usdcContract.allowance(msg.sender, address(this)) >= totalAmount, "Insufficient USDC allowance");

        // 生成订单ID
        uint256 orderId = _generateOrderId(msg.sender, _stockSymbol);

        // 转移USDC到接收地址
        require(usdcContract.transferFrom(msg.sender, fundReceiver, orderValue), "USDC transfer failed");
        emit USDCTransferred(msg.sender, fundReceiver, orderValue);

        // 收取手续费
        require(usdcContract.transferFrom(msg.sender, address(this), feeAmount), "Fee transfer failed");
        emit FeeCharged(msg.sender, feeAmount, true);

        // 发送订单创建事件
        emit OrderCreated(
            orderId,
            msg.sender,
            _stockSymbol,
            _orderType,
            OrderSide.BUY,
            _amount,
            _price,
            feeAmount,           // 手续费金额
            _expiresAt,         // 过期时间
            block.timestamp
        );
        
        return orderId;
    }

    // 标记订单为已完成 - 只发送事件，由后端调用
    function markOrderFilled(uint256 _orderId) external onlyOwner {
        emit OrderFilled(_orderId, block.timestamp);
    }

    // 标记订单为已取消 - 处理退还逻辑，由后端调用
    function markOrderCancelled(
        uint256 _orderId,
        address _user,
        string calldata _stockSymbol,
        bool _isBuyOrder,
        uint256 _refundAmount,
        uint256 _feeRefundAmount
    ) external onlyOwner {
        // 1. Checks - 输入验证
        require(_user != address(0), "Invalid user address");
        require(_refundAmount > 0, "Refund amount must be greater than 0");
        
        // 预先验证授权以避免失败
        if (_isBuyOrder) {
            require(usdcContract.allowance(fundReceiver, address(this)) >= _refundAmount, 
                    "Insufficient USDC allowance for refund");
            if (_feeRefundAmount > 0) {
                require(usdcContract.balanceOf(address(this)) >= _feeRefundAmount,
                        "Insufficient contract USDC balance for fee refund");
            }
        } else {
            address tokenAddress = _getStockTokenAddress(_stockSymbol);
            require(tokenAddress != address(0), "Stock token does not exist");
            
            StandardStockToken stockToken = StandardStockToken(tokenAddress);
            require(stockToken.allowance(tokenReceiver, address(this)) >= _refundAmount,
                    "Insufficient token allowance for refund");
            if (_feeRefundAmount > 0) {
                require(stockToken.balanceOf(address(this)) >= _feeRefundAmount,
                        "Insufficient contract token balance for fee refund");
            }
        }
        
        // 2. Effects - 状态更新（发送事件）
        emit OrderCancelled(_orderId, block.timestamp);
        
        // 3. Interactions - 外部调用
        if (_isBuyOrder) {
            // 买单退还USDC - 从fundReceiver退还给用户
            require(usdcContract.transferFrom(fundReceiver, _user, _refundAmount), "USDC refund failed");
            emit USDCTransferred(fundReceiver, _user, _refundAmount);
            
            // 退还手续费（从合约余额）
            if (_feeRefundAmount > 0) {
                require(usdcContract.transfer(_user, _feeRefundAmount), "USDC fee refund failed");
                emit USDCTransferred(address(this), _user, _feeRefundAmount);
            }
        } else {
            // 卖单退还股票代币 - 从tokenReceiver退还给用户
            address tokenAddress = _getStockTokenAddress(_stockSymbol);
            StandardStockToken stockToken = StandardStockToken(tokenAddress);
            
            require(stockToken.transferFrom(tokenReceiver, _user, _refundAmount), "Stock token refund failed");
            emit StockTokenTransferred(tokenReceiver, _user, _stockSymbol, _refundAmount);
            
            // 退还手续费（从合约余额）
            if (_feeRefundAmount > 0) {
                require(stockToken.transfer(_user, _feeRefundAmount), "Stock token fee refund failed");
                emit StockTokenTransferred(address(this), _user, _stockSymbol, _feeRefundAmount);
            }
        }
    }

    // 提取手续费
    function withdrawFees(string calldata _stockSymbol, bool isUSDC) external onlyOwner {
        if (isUSDC) {
            uint256 balance = usdcContract.balanceOf(address(this));
            require(balance > 0, "No USDC fees to withdraw");
            require(usdcContract.transfer(feeReceiver, balance), "USDC withdrawal failed");
            emit FeesWithdrawn(feeReceiver, balance, true);
        } else {
            address tokenAddress = _getStockTokenAddress(_stockSymbol);
            require(tokenAddress != address(0), "Stock token does not exist");
            
            StandardStockToken stockToken = StandardStockToken(tokenAddress);
            uint256 balance = stockToken.balanceOf(address(this));
            require(balance > 0, "No stock token fees to withdraw");
            require(stockToken.transfer(feeReceiver, balance), "Stock token withdrawal failed");
            emit FeesWithdrawn(feeReceiver, balance, false);
        }
    }

    // 计算手续费
    function calculateFee(uint256 amount) public view returns (uint256) {
        return (amount * feeRate) / 10000;
    }

    // 获取股票代币合约地址
    function getStockTokenAddress(string calldata _stockSymbol) external view returns (address) {
        return _getStockTokenAddress(_stockSymbol);
    }

    // 内部函数：从Factory获取股票代币合约地址
    function _getStockTokenAddress(string calldata _stockSymbol) internal view returns (address) {
        (bool success, bytes memory data) = stockTokenFactory.staticcall(
            abi.encodeWithSignature("getStockTokenAddress(string)", _stockSymbol)
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (address));
        }
        return address(0);
    }

    // 内部函数：生成订单ID
    function _generateOrderId(address user, string memory stockSymbol) internal returns (uint256) {
        orderNonce++;
        return uint256(keccak256(abi.encodePacked(
            user, 
            stockSymbol, 
            block.timestamp,
            block.prevrandao,  // 使用新的随机源
            orderNonce,
            address(this)
        )));
    }
}