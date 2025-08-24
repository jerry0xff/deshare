// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev 简化版IERC20接口
 */
interface IERC20 {
    /**
     * @dev 返回代币的总供应量
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev 返回账户的代币余额
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev 从调用者账户向接收者转账代币
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev 返回允许spender从owner账户中转账的代币数量
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev 允许spender从调用者账户中转账代币
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev 从owner账户向recipient账户转账代币
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /**
     * @dev 当代币被转账时触发
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev 当授权被设置时触发
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}