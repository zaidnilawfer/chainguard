// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title MockVault
 * @notice Simulates a DeFi vault that an AI agent might interact with.
 *         Used for testing ChainGuard policy enforcement.
 */
contract MockVault {
    mapping(address => uint256) public balances;
    uint256 public totalDeposits;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "Must deposit > 0");
        balances[msg.sender] += msg.value;
        totalDeposits += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount) external {
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        balances[msg.sender] -= _amount;
        totalDeposits -= _amount;
        payable(msg.sender).transfer(_amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function getBalance(address _user) external view returns (uint256) {
        return balances[_user];
    }
}
