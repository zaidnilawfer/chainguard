// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @notice Simple ERC-20 token for testing AI-agent interactions
 *         through ChainGuard.
 */
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
