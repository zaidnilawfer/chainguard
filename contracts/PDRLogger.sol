// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PDRLogger  (Policy Decision Record Logger)
 * @author Zaid Nilawfer — ChainGuard Framework
 * @notice Immutable, append-only audit log of every policy-enforcement
 *         decision.  Each record stores the agent, action, target,
 *         prompt hash, decision, matched rule, classifier score, and a
 *         human-readable reason.
 *
 *         Only authorised callers (the PolicyEnforcer contract) may
 *         write records.
 */
contract PDRLogger is Ownable {
    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────
    struct PDR {
        uint256 id;
        address agent;
        string  actionType;
        address target;
        bytes32 promptHash;
        uint8   decision;        // 0 = ALLOW, 1 = BLOCK, 2 = WARN
        uint256 matchedRuleId;
        uint256 classifierScore;
        string  reason;
        uint256 timestamp;
        uint256 blockNumber;
    }

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────
    PDR[] public records;
    mapping(address => bool) public authorisedCallers;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────
    event DecisionLogged(
        uint256 indexed recordId,
        address indexed agent,
        uint8   decision,
        string  reason
    );
    event CallerAuthorised(address indexed caller);
    event CallerRevoked(address indexed caller);

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────
    modifier onlyAuthorised() {
        require(authorisedCallers[msg.sender], "PDRLogger: not authorised");
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────
    constructor() Ownable(msg.sender) {}

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    function authoriseCaller(address _caller) external onlyOwner {
        authorisedCallers[_caller] = true;
        emit CallerAuthorised(_caller);
    }

    function revokeCaller(address _caller) external onlyOwner {
        authorisedCallers[_caller] = false;
        emit CallerRevoked(_caller);
    }

    // ──────────────────────────────────────────────
    //  Logging
    // ──────────────────────────────────────────────

    /**
     * @notice Append a Policy Decision Record.
     */
    function logDecision(
        address _agent,
        string calldata _actionType,
        address _target,
        bytes32 _promptHash,
        uint8   _decision,
        uint256 _matchedRuleId,
        uint256 _classifierScore,
        string calldata _reason
    ) external onlyAuthorised returns (uint256 recordId) {
        recordId = records.length;
        records.push(PDR({
            id: recordId,
            agent: _agent,
            actionType: _actionType,
            target: _target,
            promptHash: _promptHash,
            decision: _decision,
            matchedRuleId: _matchedRuleId,
            classifierScore: _classifierScore,
            reason: _reason,
            timestamp: block.timestamp,
            blockNumber: block.number
        }));

        emit DecisionLogged(recordId, _agent, _decision, _reason);
    }

    // ──────────────────────────────────────────────
    //  Read helpers
    // ──────────────────────────────────────────────

    function getRecordCount() external view returns (uint256) {
        return records.length;
    }

    function getRecord(uint256 _id) external view returns (PDR memory) {
        require(_id < records.length, "Record does not exist");
        return records[_id];
    }

    /**
     * @notice Return the last N records (most-recent-first).
     */
    function getRecentRecords(uint256 _count)
        external
        view
        returns (PDR[] memory)
    {
        uint256 total = records.length;
        if (_count > total) _count = total;

        PDR[] memory recent = new PDR[](_count);
        for (uint256 i = 0; i < _count; i++) {
            recent[i] = records[total - 1 - i];
        }
        return recent;
    }
}
