// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./StandardStockToken.sol";

contract StockTrading is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    // Address configuration
    address public feeReceiver;
    address public fundReceiver;
    address public tokenReceiver;

    // USDT token contract address
    IERC20 public usdtContract;

    // StockTokenFactory contract address
    address public stockTokenFactory;

    // Fee rate in basis points (1 basis point = 0.01%)
    uint256 public feeRate;

    // Security limits
    uint256 public constant MAX_ORDER_AMOUNT = 1e26; // Max order amount (8 decimals)
    uint256 public constant MAX_PRICE = 1e12; // Max price (6 decimals)
    uint256 public constant MIN_FEE_RATE = 1; // Min fee rate 0.01%
    
    // Order counter for secure order ID generation
    uint256 private orderNonce;

    // Minimum fee amount in USDT (6 decimals)
    uint256 public minFeeAmount;

    // Trading type enums
    enum OrderType { LIMIT, MARKET }
    enum OrderSide { BUY, SELL }

    // Events - Order related
    event OrderCreated(
        uint256 indexed orderId, 
        address indexed user, 
        string stockSymbol,           // removed indexed
        OrderType orderType, 
        OrderSide orderSide, 
        uint256 amount, 
        uint256 price,
        uint256 feeAmount,           // fee amount
        uint256 expiresAt,           // expiration time
        uint256 timestamp
    );
    
    event OrderFilled(uint256 indexed orderId, uint256 timestamp);
    event OrderCancelled(uint256 indexed orderId, uint256 timestamp);
    
    // Events - Fund and token transfers
    event USDTTransferred(address indexed from, address indexed to, uint256 amount);
    event StockTokenTransferred(address indexed from, address indexed to, string indexed stockSymbol, uint256 amount);
    
    // Events - Fee and configuration
    event FeeCharged(address indexed user, uint256 amount, bool isUSDT);
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event FeesWithdrawn(address indexed receiver, uint256 amount, bool isUSDT);
    
    // Events - Token minting and burning
    event StockTokensMinted(string indexed stockSymbol, address indexed to, uint256 amount);
    event StockTokensBurned(string indexed stockSymbol, address indexed from, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _usdtContract, address _stockTokenFactory) public initializer {
        require(_usdtContract != address(0), "Invalid USDT address");
        require(_stockTokenFactory != address(0), "Invalid factory address");
        
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        usdtContract = IERC20(_usdtContract);
        stockTokenFactory = _stockTokenFactory;
        feeReceiver = msg.sender;
        fundReceiver = msg.sender;
        tokenReceiver = msg.sender;
        feeRate = 100; // Default fee rate 1% (100 basis points)
        minFeeAmount = 500000; // 0.5 USDT
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Set receiver addresses
    function setReceivers(address _fundReceiver, address _tokenReceiver, address _feeReceiver) external onlyOwner {
        require(_fundReceiver != address(0), "Invalid fund receiver");
        require(_tokenReceiver != address(0), "Invalid token receiver");
        require(_feeReceiver != address(0), "Invalid fee receiver");
        
        fundReceiver = _fundReceiver;
        tokenReceiver = _tokenReceiver;
        feeReceiver = _feeReceiver;
    }

    // Set fee rate
    function setFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate >= MIN_FEE_RATE, "Fee rate too low");
        require(_feeRate <= 1000, "Fee rate cannot exceed 10%");
        uint256 oldRate = feeRate;
        feeRate = _feeRate;
        emit FeeRateUpdated(oldRate, _feeRate);
    }

    // Set minimum fee amount
    function setMinFeeAmount(uint256 _minFeeAmount) external onlyOwner {
        minFeeAmount = _minFeeAmount;
    }

    // Set USDT contract address
    function setUsdtContract(address _usdtContract) external onlyOwner {
        require(_usdtContract != address(0), "Invalid USDT address");
        usdtContract = IERC20(_usdtContract);
    }

    // Set factory contract address
    function setStockTokenFactory(address _stockTokenFactory) external onlyOwner {
        require(_stockTokenFactory != address(0), "Invalid factory address");
        stockTokenFactory = _stockTokenFactory;
    }

    // Mint stock tokens - owner only
    function mintStockTokens(string calldata _stockSymbol, address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than 0");
        
        // Get token contract address from Factory
        address tokenAddress = _getStockTokenAddress(_stockSymbol);
        require(tokenAddress != address(0), "Stock token does not exist");
        
        // Call token contract mint function
        StandardStockToken(tokenAddress).mint(_to, _amount);
        
        emit StockTokensMinted(_stockSymbol, _to, _amount);
    }

    // Burn stock tokens - owner only
    function burnStockTokens(string calldata _stockSymbol, address _from, uint256 _amount) external onlyOwner {
        require(_from != address(0), "Invalid holder address");
        require(_amount > 0, "Amount must be greater than 0");
        
        // Get token contract address from Factory
        address tokenAddress = _getStockTokenAddress(_stockSymbol);
        require(tokenAddress != address(0), "Stock token does not exist");
        
        // Call token contract burn function
        StandardStockToken(tokenAddress).burn(_from, _amount);
        
        emit StockTokensBurned(_stockSymbol, _from, _amount);
    }

    // Create sell order - no storage, only events
    function createSellOrder(
        string calldata _stockSymbol, 
        OrderType _orderType, 
        uint256 _amount, 
        uint256 _price,
        uint256 _expiresAt    // expiration time parameter
    ) external nonReentrant returns (uint256) {
        require(_amount > 0 && _amount <= MAX_ORDER_AMOUNT, "Invalid amount");
        if (_orderType == OrderType.LIMIT) {
            require(_price > 0 && _price <= MAX_PRICE, "Invalid price");
        }

        // Get stock token contract
        address tokenAddress = _getStockTokenAddress(_stockSymbol);
        require(tokenAddress != address(0), "Stock token does not exist");
        
        StandardStockToken stockToken = StandardStockToken(tokenAddress);

        // Enhanced math checks for sell orders
        uint256 orderValue = 0;
        uint256 feeAmount = 0;
        
        if (_price > 0) {
            // Prevent overflow in multiplication
            require(_amount <= type(uint256).max / _price, "Amount * price overflow");
            
            uint256 rawValue = _amount * _price;
            require(rawValue >= 10**8, "Value too small for conversion");
            orderValue = rawValue / 10**8; // Convert stock amount and price to USDT amount (6 decimals)
            
            // Safe fee calculation with overflow check
            if (orderValue > 0) {
                require(orderValue <= type(uint256).max / feeRate, "Fee calculation overflow");
                uint256 calculatedFee = (orderValue * feeRate) / 10000;
                feeAmount = calculatedFee > minFeeAmount ? calculatedFee : minFeeAmount;
            }
        }

        // Check stock token balance and allowance (only lock sell amount, no token fee)
        require(stockToken.balanceOf(msg.sender) >= _amount, "Insufficient stock balance");
        require(stockToken.allowance(msg.sender, address(this)) >= _amount, "Insufficient stock allowance");

        // Check USDT balance and allowance if fee required
        if (feeAmount > 0) {
            require(usdtContract.balanceOf(msg.sender) >= feeAmount, "Insufficient USDT balance for fee");
            require(usdtContract.allowance(msg.sender, address(this)) >= feeAmount, "Insufficient USDT allowance for fee");
        }

        // Generate order ID
        uint256 orderId = _generateOrderId(msg.sender, _stockSymbol);

        // Transfer tokens to receiver
        require(stockToken.transferFrom(msg.sender, tokenReceiver, _amount), "Stock transfer failed");
        emit StockTokenTransferred(msg.sender, tokenReceiver, _stockSymbol, _amount);

        // Collect USDT fee
        if (feeAmount > 0) {
            require(usdtContract.transferFrom(msg.sender, address(this), feeAmount), "USDT fee transfer failed");
            emit FeeCharged(msg.sender, feeAmount, true);
        }

        // Emit order creation event
        emit OrderCreated(
            orderId,
            msg.sender,
            _stockSymbol,
            _orderType,
            OrderSide.SELL,
            _amount,
            _price,
            feeAmount,           // fee amount
            _expiresAt,         // expiration time
            block.timestamp
        );
        
        return orderId;
    }

    // Create buy order - no storage, only events
    function createBuyOrder(
        string calldata _stockSymbol, 
        OrderType _orderType, 
        uint256 _amount, 
        uint256 _price,
        uint256 _expiresAt    // expiration time parameter
    ) external nonReentrant returns (uint256) {
        require(_amount > 0 && _amount <= MAX_ORDER_AMOUNT, "Invalid amount");
        if (_orderType == OrderType.LIMIT) {
            require(_price > 0 && _price <= MAX_PRICE, "Invalid price");
        }

        // Enhanced math checks - prevent overflow and ensure valid calculations
        require(_price > 0, "Price must be positive");
        require(_amount <= type(uint256).max / _price, "Amount * price overflow");
        
        uint256 rawValue = _amount * _price;
        require(rawValue >= 10**8, "Value too small for conversion");
        uint256 orderValue = rawValue / 10**8; // Convert to USDT amount (6 decimals)
        require(orderValue > 0, "Order value cannot be zero");
        
        // Safe fee calculation with overflow check
        require(orderValue <= type(uint256).max / feeRate, "Fee calculation overflow");
        uint256 calculatedFee = (orderValue * feeRate) / 10000;
        uint256 feeAmount = calculatedFee > minFeeAmount ? calculatedFee : minFeeAmount;
        require(orderValue <= type(uint256).max - feeAmount, "Total amount overflow");
        uint256 totalAmount = orderValue + feeAmount;

        // Check USDT balance and allowance
        require(usdtContract.balanceOf(msg.sender) >= totalAmount, "Insufficient USDT balance");
        require(usdtContract.allowance(msg.sender, address(this)) >= totalAmount, "Insufficient USDT allowance");

        // Generate order ID
        uint256 orderId = _generateOrderId(msg.sender, _stockSymbol);

        // Transfer USDT to receiver
        require(usdtContract.transferFrom(msg.sender, fundReceiver, orderValue), "USDT transfer failed");
        emit USDTTransferred(msg.sender, fundReceiver, orderValue);

        // Collect fee
        require(usdtContract.transferFrom(msg.sender, address(this), feeAmount), "Fee transfer failed");
        emit FeeCharged(msg.sender, feeAmount, true);

        // Emit order creation event
        emit OrderCreated(
            orderId,
            msg.sender,
            _stockSymbol,
            _orderType,
            OrderSide.BUY,
            _amount,
            _price,
            feeAmount,           // fee amount
            _expiresAt,         // expiration time
            block.timestamp
        );
        
        return orderId;
    }

    // Mark order as filled - only events, backend call
    function markOrderFilled(uint256 _orderId) external onlyOwner {
        emit OrderFilled(_orderId, block.timestamp);
    }

    // Mark order as cancelled - handle refund logic, backend call
    function markOrderCancelled(
        uint256 _orderId,
        address _user,
        string calldata _stockSymbol,
        bool _isBuyOrder,
        uint256 _refundAmount,
        uint256 _feeRefundAmount
    ) external onlyOwner nonReentrant {
        // 1. Checks - input validation
        require(_user != address(0), "Invalid user address");
        require(_refundAmount > 0, "Refund amount must be greater than 0");
        
        // Pre-validate allowance to avoid failure
        if (_isBuyOrder) {
            require(usdtContract.allowance(fundReceiver, address(this)) >= _refundAmount, 
                    "Insufficient USDT allowance for refund");
            if (_feeRefundAmount > 0) {
                require(usdtContract.balanceOf(address(this)) >= _feeRefundAmount,
                        "Insufficient contract USDT balance for fee refund");
            }
        } else {
            address tokenAddress = _getStockTokenAddress(_stockSymbol);
            require(tokenAddress != address(0), "Stock token does not exist");
            
            StandardStockToken stockToken = StandardStockToken(tokenAddress);
            require(stockToken.allowance(tokenReceiver, address(this)) >= _refundAmount,
                    "Insufficient token allowance for refund");
            // Sell order fee collected in USDT, check contract USDT balance for fee refund
            if (_feeRefundAmount > 0) {
                require(usdtContract.balanceOf(address(this)) >= _feeRefundAmount,
                        "Insufficient contract USDT balance for fee refund");
            }
        }
        
        // 2. Effects - state update (emit events)
        emit OrderCancelled(_orderId, block.timestamp);
        
        // 3. Interactions - external calls
        if (_isBuyOrder) {
            // Buy order refund USDT - from fundReceiver to user
            require(usdtContract.transferFrom(fundReceiver, _user, _refundAmount), "USDT refund failed");
            emit USDTTransferred(fundReceiver, _user, _refundAmount);
            
            // Refund fee (from contract balance)
            if (_feeRefundAmount > 0) {
                require(usdtContract.transfer(_user, _feeRefundAmount), "USDT fee refund failed");
                emit USDTTransferred(address(this), _user, _feeRefundAmount);
            }
        } else {
            // Sell order refund stock tokens - from tokenReceiver to user
            address tokenAddress = _getStockTokenAddress(_stockSymbol);
            StandardStockToken stockToken = StandardStockToken(tokenAddress);
            
            require(stockToken.transferFrom(tokenReceiver, _user, _refundAmount), "Stock token refund failed");
            emit StockTokenTransferred(tokenReceiver, _user, _stockSymbol, _refundAmount);
            
            // Refund fee (USDT, from contract balance)
            if (_feeRefundAmount > 0) {
                require(usdtContract.transfer(_user, _feeRefundAmount), "USDT fee refund failed");
                emit USDTTransferred(address(this), _user, _feeRefundAmount);
            }
        }
    }

    // Withdraw fees
    function withdrawFees(string calldata _stockSymbol, bool isUSDT) external onlyOwner nonReentrant {
        if (isUSDT) {
            uint256 balance = usdtContract.balanceOf(address(this));
            require(balance > 0, "No USDT fees to withdraw");
            require(usdtContract.transfer(feeReceiver, balance), "USDT withdrawal failed");
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

    // Calculate fee
    function calculateFee(uint256 amount) public view returns (uint256) {
        uint256 calculatedFee = (amount * feeRate) / 10000;
        return calculatedFee > minFeeAmount ? calculatedFee : minFeeAmount;
    }

    // Get stock token contract address
    function getStockTokenAddress(string calldata _stockSymbol) external view returns (address) {
        return _getStockTokenAddress(_stockSymbol);
    }

    // Internal function: get stock token contract address from Factory
    function _getStockTokenAddress(string calldata _stockSymbol) internal view returns (address) {
        (bool success, bytes memory data) = stockTokenFactory.staticcall(
            abi.encodeWithSignature("getStockTokenAddress(string)", _stockSymbol)
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (address));
        }
        return address(0);
    }

    // Internal function: generate order ID
    function _generateOrderId(address user, string memory stockSymbol) internal returns (uint256) {
        orderNonce++;
        return uint256(keccak256(abi.encodePacked(
            user, 
            stockSymbol, 
            block.timestamp,
            block.prevrandao,  // use new randomness source
            orderNonce,
            address(this)
        )));
    }
}