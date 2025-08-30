// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 模拟股票凭证代币合约
contract MockStockToken {
    // 存储用户的股票余额
    mapping(address => mapping(string => uint256)) private _balances;
    
    // 存储授权额度
    mapping(address => mapping(address => uint256)) private _allowances;

    // 事件
    event Transfer(address indexed from, address indexed to, string indexed stockSymbol, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Mint(address indexed to, string indexed stockSymbol, uint256 amount);
    event Burn(address indexed from, string indexed stockSymbol, uint256 amount);

    // 获取余额
    function balanceOf(address account, string calldata stockSymbol) external view returns (uint256) {
        return _balances[account][stockSymbol];
    }

    // 获取授权额度
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // 授权
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // 转账
    function transfer(address to, string calldata stockSymbol, uint256 amount) external returns (bool) {
        require(to != address(0), "Invalid address");
        require(_balances[msg.sender][stockSymbol] >= amount, "Insufficient balance");

        _balances[msg.sender][stockSymbol] -= amount;
        _balances[to][stockSymbol] += amount;

        emit Transfer(msg.sender, to, stockSymbol, amount);
        return true;
    }

    // 从授权地址转账
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

    // 铸造代币
    function mint(address to, string calldata stockSymbol, uint256 amount) external {
        require(to != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than 0");

        _balances[to][stockSymbol] += amount;

        emit Mint(to, stockSymbol, amount);
    }

    // 销毁代币
    function burn(address from, string calldata stockSymbol, uint256 amount) external {
        require(from != address(0), "Invalid address");
        require(_balances[from][stockSymbol] >= amount, "Insufficient balance");

        _balances[from][stockSymbol] -= amount;

        emit Burn(from, stockSymbol, amount);
    }

    // 设置余额（仅用于测试）
    function setBalance(address account, string calldata stockSymbol, uint256 amount) external {
        _balances[account][stockSymbol] = amount;
    }
}