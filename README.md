# ChainGuard

**Smart Contract-Based Defence Framework Against Prompt Injection Attacks on Blockchain AI Agents**

> Final Year Project — BSc (Hons) Computer Science  
> IIT Sri Lanka / University of Westminster  
> Author: Zaid Nilawfer

## Overview

ChainGuard is a novel security framework that uses on-chain smart contracts to detect and prevent prompt injection attacks targeting AI agents operating on blockchain protocols. Unlike traditional off-chain middleware filters, ChainGuard enforces policies at the smart contract layer — making them transparent, auditable, and tamper-resistant.

## Architecture

The framework consists of three layers:

1. **Off-chain AI Agent** — Python/LangChain agent + LLM (GPT-4) that interprets user prompts and proposes blockchain actions.
2. **On-chain Policy Enforcement Layer** — Three Solidity smart contracts that validate every agent action before execution:
   - `PolicyRegistry` — Stores detection rules (keywords, severity levels).
   - `PolicyEnforcer` — Validates actions against rules + optional ML classifier scores.
   - `PDRLogger` — Immutable audit log of all policy decisions.
3. **Target Protocol** — The DeFi protocol (vault, swap, token) the agent interacts with.

## Evaluation Configurations

| Config | Description |
|--------|-------------|
| **A** | No guardrails (baseline) |
| **B** | Off-chain Python middleware only |
| **C** | ChainGuard on-chain enforcement |
| **D** | ChainGuard + ML classifier (hybrid) |

## Tech Stack

- **Smart Contracts:** Solidity ^0.8.19, Hardhat, OpenZeppelin
- **Testing:** Mocha, Chai, Hardhat Gas Reporter
- **AI Agent:** Python 3.10+, LangChain, OpenAI GPT-4, Web3.py
- **ML Classifier:** Fine-tuned DistilBERT (HuggingFace, PyTorch)
- **Datasets:** Deepset prompt-injections, Fmops, BIPIA Benchmark

## Quick Start

```bash
# Install dependencies
npm install

# Compile contracts
npm run compile

# Run tests
npm test

# Run tests with gas report
npm run test:gas

# Start local Hardhat node
npm run node

# Deploy to local network
npm run deploy:local
```

## Project Structure

```
chainguard/
├── contracts/
│   ├── PolicyRegistry.sol    # Rule storage
│   ├── PolicyEnforcer.sol    # Validation engine
│   ├── PDRLogger.sol         # Audit log
│   └── mocks/
│       ├── MockVault.sol     # Simulated DeFi vault
│       ├── MockToken.sol     # ERC-20 test token
│       └── MockSwap.sol      # Simulated DEX swap
├── scripts/
│   └── deploy.js             # Deployment script
├── test/
│   └── ChainGuard.test.js    # Test suite
├── hardhat.config.js
├── package.json
└── README.md
```

## Licence

MIT
