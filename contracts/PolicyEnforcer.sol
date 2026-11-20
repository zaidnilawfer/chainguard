// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./PolicyRegistry.sol";
import "./PDRLogger.sol";

/**
 * @title PolicyEnforcer
 * @author Zaid Nilawfer — ChainGuard Framework
 * @notice Validates AI-agent actions against the on-chain PolicyRegistry
 *         before they reach the target DeFi protocol.  Actions that match
 *         a HIGH or CRITICAL rule are blocked; others are allowed with a
 *         warning logged.
 *
 *         In Config D (Hybrid) the off-chain ML classifier pre-screens
 *         prompts and passes a `classifierScore` (0-100) alongside the
 *         action.  A score >= mlThreshold also triggers a block.
 */
contract PolicyEnforcer is Ownable {
    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────
    enum Decision { ALLOW, BLOCK, WARN }

    struct ValidationResult {
        Decision decision;
        uint256  matchedRuleId;   // 0 if none
        uint256  classifierScore; // 0 if not used
        string   reason;
    }

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────
    PolicyRegistry public registry;
    PDRLogger      public logger;

    uint256 public mlThreshold;        // classifier score threshold (0-100)
    bool    public mlEnabled;          // Config D toggle

    uint256 public totalChecks;
    uint256 public totalBlocks;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────
    event ActionValidated(
        address indexed agent,
        Decision decision,
        uint256 matchedRuleId,
        uint256 classifierScore,
        string  reason
    );

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────
    constructor(
        address _registry,
        address _logger,
        uint256 _mlThreshold
    ) Ownable(msg.sender) {
        registry    = PolicyRegistry(_registry);
        logger      = PDRLogger(_logger);
        mlThreshold = _mlThreshold;
        mlEnabled   = false;
    }

    // ──────────────────────────────────────────────
    //  Config setters
    // ──────────────────────────────────────────────

    function setMLThreshold(uint256 _t) external onlyOwner {
        require(_t <= 100, "Threshold must be 0-100");
        mlThreshold = _t;
    }

    function toggleML(bool _enabled) external onlyOwner {
        mlEnabled = _enabled;
    }

    // ──────────────────────────────────────────────
    //  Core validation
    // ──────────────────────────────────────────────

    /**
     * @notice Validate an AI-agent action before execution.
     * @param _agent           Address of the AI agent.
     * @param _actionType      Human-readable action (e.g. "swap", "transfer").
     * @param _target          Target contract address.
     * @param _promptHash      Keccak-256 hash of the original prompt.
     * @param _matchedKeywords Comma-separated keywords found off-chain.
     * @param _classifierScore ML classifier confidence (0-100), 0 if unused.
     * @return result           The validation decision.
     */
    function validateAction(
        address _agent,
        string  calldata _actionType,
        address _target,
        bytes32 _promptHash,
        string  calldata _matchedKeywords,
        uint256 _classifierScore
    ) external returns (ValidationResult memory result) {
        totalChecks++;

        // ── 1. ML classifier check (Config D) ──
        if (mlEnabled && _classifierScore >= mlThreshold) {
            totalBlocks++;
            result = ValidationResult({
                decision: Decision.BLOCK,
                matchedRuleId: 0,
                classifierScore: _classifierScore,
                reason: "ML classifier flagged prompt as injection"
            });

            _logAndEmit(_agent, result, _actionType, _target, _promptHash);
            return result;
        }

        // ── 2. On-chain keyword / pattern rules ──
        PolicyRegistry.Rule[] memory activeRules = registry.getActiveRules();

        for (uint256 i = 0; i < activeRules.length; i++) {
            if (_containsKeyword(_matchedKeywords, activeRules[i].pattern)) {
                if (
                    activeRules[i].severity == PolicyRegistry.Severity.HIGH ||
                    activeRules[i].severity == PolicyRegistry.Severity.CRITICAL
                ) {
                    totalBlocks++;
                    result = ValidationResult({
                        decision: Decision.BLOCK,
                        matchedRuleId: activeRules[i].id,
                        classifierScore: _classifierScore,
                        reason: string(
                            abi.encodePacked(
                                "Blocked by rule: ",
                                activeRules[i].pattern
                            )
                        )
                    });

                    _logAndEmit(_agent, result, _actionType, _target, _promptHash);
                    return result;
                }

                // LOW / MEDIUM → warn but allow
                result = ValidationResult({
                    decision: Decision.WARN,
                    matchedRuleId: activeRules[i].id,
                    classifierScore: _classifierScore,
                    reason: string(
                        abi.encodePacked(
                            "Warning - matched rule: ",
                            activeRules[i].pattern
                        )
                    )
                });

                _logAndEmit(_agent, result, _actionType, _target, _promptHash);
                return result;
            }
        }

        // ── 3. No match → allow ──
        result = ValidationResult({
            decision: Decision.ALLOW,
            matchedRuleId: 0,
            classifierScore: _classifierScore,
            reason: "No policy violation detected"
        });

        _logAndEmit(_agent, result, _actionType, _target, _promptHash);
        return result;
    }

    // ──────────────────────────────────────────────
    //  Internal helpers
    // ──────────────────────────────────────────────

    function _logAndEmit(
        address _agent,
        ValidationResult memory _result,
        string calldata _actionType,
        address _target,
        bytes32 _promptHash
    ) internal {
        // Log to PDRLogger
        logger.logDecision(
            _agent,
            _actionType,
            _target,
            _promptHash,
            uint8(_result.decision),
            _result.matchedRuleId,
            _result.classifierScore,
            _result.reason
        );

        emit ActionValidated(
            _agent,
            _result.decision,
            _result.matchedRuleId,
            _result.classifierScore,
            _result.reason
        );
    }

    /**
     * @dev Simple substring check — the off-chain agent sends a
     *      comma-separated string of keywords it detected.  We check
     *      whether `_keyword` appears in that string.
     */
    function _containsKeyword(
        string memory _haystack,
        string memory _needle
    ) internal pure returns (bool) {
        bytes memory h = bytes(_haystack);
        bytes memory n = bytes(_needle);
        if (n.length == 0 || n.length > h.length) return false;

        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
