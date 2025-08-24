// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

// 模拟USDC代币合约
contract MockUSDC is IERC20 {
    // 代币名称
    string public constant name = "Mock USDC";
    // 代币符号
    string public constant symbol = "mUSDC";
    // 小数位数
    uint8 public constant decimals = 6;
    // 总供应量
    uint256 public override totalSupply;

    // 存储用户余额
    mapping(address => uint256) private _balances;
    // 存储授权信息
    mapping(address => mapping(address => uint256)) private _allowances;

    // 构造函数
    constructor() {
        // 初始铸造1000000 mUSDC给部署者
        _mint(msg.sender, 1000000 * 10 ** decimals);
    }

    // 获取余额
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    // 转账
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    // 授权转账
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    // 授权转账从
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // 获取授权额度
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    // 内部转账函数
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from the zero address");
        require(to != address(0), "Transfer to the zero address");
        require(_balances[from] >= amount, "Insufficient balance");

        _balances[from] -= amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

    // 内部授权函数
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from the zero address");
        require(spender != address(0), "Approve to the zero address");

        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    // 内部消耗授权函数
    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    // 铸造代币
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Mint to the zero address");

        totalSupply += amount;
        _balances[account] += amount;

        emit Transfer(address(0), account, amount);
    }

    // 销毁代币
    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "Burn from the zero address");
        require(_balances[account] >= amount, "Insufficient balance");

        unchecked {
            _balances[account] -= amount;
        }
        totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }
}