// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev 简化版Ownable合约
 */
contract Ownable {
    address private _owner;

    /**
     * @dev 当合约部署时，设置调用者为所有者
     */
    constructor() {
        _owner = msg.sender;
    }

    /**
     * @dev 返回合约所有者地址
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev 修饰器，限制只有所有者可以调用函数
     */
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev 转移合约所有权
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _owner = newOwner;
    }
}