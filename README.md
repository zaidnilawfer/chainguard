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
- **AI Agent:** Python 3.10+, LangChain, Web3.py
- **LLM Providers:** Google Gemini (default), Groq (Llama 3.1 70B), OpenAI GPT-4
- **Frontend:** Streamlit web dashboard
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

# Set up Python agent
cd agent
pip install -r requirements.txt

# Add your API key to agent/.env (Gemini is default)
# GOOGLE_API_KEY=your-key-here

# Run CLI agent
python chainguard_agent.py

# Or run the web dashboard
streamlit run dashboard.py
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
├── agent/
│   ├── chainguard_agent.py   # LangChain AI agent (CLI)
│   ├── dashboard.py          # Streamlit web dashboard
│   ├── blockchain_tools.py   # Web3 contract helpers
│   ├── requirements.txt      # Python dependencies
│   └── .env.example          # Environment template
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
