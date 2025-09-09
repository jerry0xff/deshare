// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IStockToken.sol";

contract StockToken is Ownable {
    mapping(address => mapping(string => uint256)) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    address public factory;
    
    event Transfer(address indexed from, address indexed to, string indexed stockSymbol, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Mint(address indexed to, string indexed stockSymbol, uint256 amount);
    event Burn(address indexed from, string indexed stockSymbol, uint256 amount);

    constructor() {
        factory = msg.sender;
        transferOwnership(msg.sender);
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory can call this function");
        _;
    }

    function balanceOf(address account, string calldata stockSymbol) external view returns (uint256) {
        return _balances[account][stockSymbol];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, string calldata stockSymbol, uint256 amount) external returns (bool) {
        require(to != address(0), "Invalid address");
        require(_balances[msg.sender][stockSymbol] >= amount, "Insufficient balance");

        _balances[msg.sender][stockSymbol] -= amount;
        _balances[to][stockSymbol] += amount;

        emit Transfer(msg.sender, to, stockSymbol, amount);
        return true;
    }

    function transferFrom(address from, address to, string calldata stockSymbol, uint256 amount) external returns (bool) {
        require(from != address(0), "Invalid from address");
        require(to != address(0), "Invalid to address");
        require(_balances[from][stockSymbol] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");

        _balances[from][stockSymbol] -= amount;
        _balances[to][stockSymbol] += amount;
        _allowances[from][msg.sender] -= amount;

        emit Transfer(from, to, stockSymbol, amount);
        return true;
    }

    function mint(address to, string calldata stockSymbol, uint256 amount) external onlyFactory {
        require(to != address(0), "Invalid address");
        _balances[to][stockSymbol] += amount;
        emit Mint(to, stockSymbol, amount);
    }

    function burn(address from, string calldata stockSymbol, uint256 amount) external onlyFactory {
        require(from != address(0), "Invalid address");
        require(_balances[from][stockSymbol] >= amount, "Insufficient balance");
        _balances[from][stockSymbol] -= amount;
        emit Burn(from, stockSymbol, amount);
    }
}

contract StockTokenFactory is Ownable {
    // USDC代币合约地址
    IERC20 public immutable usdcContract;
    
    // 主合约地址
    address public tradingContract;
    
    // 存储已创建的股票代币合约
    mapping(string => address) public stockTokens;
    
    // 事件
    event StockTokenCreated(string indexed stockSymbol, address tokenContract);
    event TokensTransferredToContract(string indexed stockSymbol, uint256 amount);
    event TokensBurned(string indexed stockSymbol, uint256 amount);

    constructor(address _usdcContract) {
        require(_usdcContract != address(0), "Invalid USDC address");
        usdcContract = IERC20(_usdcContract);
    }

    // 设置主合约地址
    function setTradingContract(address _tradingContract) external onlyOwner {
        require(_tradingContract != address(0), "Invalid address");
        tradingContract = _tradingContract;
    }

    // 创建新的股票代币合约
    function createStockToken(string calldata _stockSymbol) external onlyOwner {
        require(stockTokens[_stockSymbol] == address(0), "Stock token already exists");
        
        // 部署新的StockToken合约
        StockToken newToken = new StockToken();
        stockTokens[_stockSymbol] = address(newToken);
        
        emit StockTokenCreated(_stockSymbol, address(newToken));
    }

    // 为指定的股票代币铸造新代币
    function mintTokens(string calldata _stockSymbol, address _to, uint256 _amount) external onlyOwner {
        address tokenAddress = stockTokens[_stockSymbol];
        require(tokenAddress != address(0), "Stock token does not exist");
        require(_amount > 0, "Amount must be greater than 0");

        StockToken(tokenAddress).mint(_to, _stockSymbol, _amount);
    }

    // 销毁指定的股票代币
    function burnTokens(string calldata _stockSymbol, address _from, uint256 _amount) external onlyOwner {
        address tokenAddress = stockTokens[_stockSymbol];
        require(tokenAddress != address(0), "Stock token does not exist");
        require(_amount > 0, "Amount must be greater than 0");

        StockToken(tokenAddress).burn(_from, _stockSymbol, _amount);
        emit TokensBurned(_stockSymbol, _amount);
    }

    // 获取股票代币合约地址
    function getStockTokenAddress(string calldata _stockSymbol) external view returns (address) {
        return stockTokens[_stockSymbol];
    }
}