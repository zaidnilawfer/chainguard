// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PolicyRegistry
 * @author Zaid Nilawfer — ChainGuard Framework
 * @notice Stores prompt-injection detection rules on-chain.
 *         Each rule is a pattern (keyword / regex hint) plus a severity
 *         level.  The PolicyEnforcer reads these rules at validation time.
 */
contract PolicyRegistry is Ownable {
    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────
    enum Severity { LOW, MEDIUM, HIGH, CRITICAL }

    struct Rule {
        uint256 id;
        string  pattern;        // keyword or regex hint
        Severity severity;
        bool    active;
        uint256 createdAt;
    }

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────
    uint256 public nextRuleId;
    mapping(uint256 => Rule) public rules;
    uint256[] public ruleIds;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────
    event RuleAdded(uint256 indexed ruleId, string pattern, Severity severity);
    event RuleToggled(uint256 indexed ruleId, bool active);
    event RuleRemoved(uint256 indexed ruleId);

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────
    constructor() Ownable(msg.sender) {}

    // ──────────────────────────────────────────────
    //  Write functions
    // ──────────────────────────────────────────────

    /**
     * @notice Add a new detection rule.
     * @param _pattern  The keyword / pattern string to match against.
     * @param _severity The severity level if matched.
     * @return ruleId   The ID assigned to the new rule.
     */
    function addRule(string calldata _pattern, Severity _severity)
        external
        onlyOwner
        returns (uint256 ruleId)
    {
        ruleId = nextRuleId++;
        rules[ruleId] = Rule({
            id: ruleId,
            pattern: _pattern,
            severity: _severity,
            active: true,
            createdAt: block.timestamp
        });
        ruleIds.push(ruleId);
        emit RuleAdded(ruleId, _pattern, _severity);
    }

    /**
     * @notice Toggle a rule on or off.
     */
    function toggleRule(uint256 _ruleId, bool _active) external onlyOwner {
        require(_ruleId < nextRuleId, "Rule does not exist");
        rules[_ruleId].active = _active;
        emit RuleToggled(_ruleId, _active);
    }

    /**
     * @notice Permanently remove a rule.
     */
    function removeRule(uint256 _ruleId) external onlyOwner {
        require(_ruleId < nextRuleId, "Rule does not exist");
        delete rules[_ruleId];
        emit RuleRemoved(_ruleId);
    }

    // ──────────────────────────────────────────────
    //  Read helpers
    // ──────────────────────────────────────────────

    /**
     * @notice Return the total number of rule IDs ever created.
     */
    function getRuleCount() external view returns (uint256) {
        return ruleIds.length;
    }

    /**
     * @notice Return all *active* rules (used by PolicyEnforcer).
     */
    function getActiveRules() external view returns (Rule[] memory) {
        uint256 count;
        for (uint256 i = 0; i < ruleIds.length; i++) {
            if (rules[ruleIds[i]].active) count++;
        }

        Rule[] memory active = new Rule[](count);
        uint256 idx;
        for (uint256 i = 0; i < ruleIds.length; i++) {
            if (rules[ruleIds[i]].active) {
                active[idx++] = rules[ruleIds[i]];
            }
        }
        return active;
    }

    /**
     * @notice Return a single rule by its ID.
     */
    function getRule(uint256 _ruleId) external view returns (Rule memory) {
        require(_ruleId < nextRuleId, "Rule does not exist");
        return rules[_ruleId];
    }
}
