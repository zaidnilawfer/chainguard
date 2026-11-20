"""
chainguard_agent.py — LangChain AI Agent integrated with ChainGuard
policy enforcement on a local Hardhat blockchain.

Supports both Google Gemini (free) and OpenAI GPT-4.

Usage:
  1. Start Hardhat node:   npm run node
  2. Deploy contracts:     npm run deploy:local
  3. Set GOOGLE_API_KEY in agent/.env
  4. Run:                  python agent/chainguard_agent.py
"""

import os
import hashlib
from dotenv import load_dotenv
from web3 import Web3

from langchain.agents import AgentExecutor, create_tool_calling_agent
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.tools import tool

from blockchain_tools import (
    w3,
    account,
    get_contract,
    send_tx,
    check_vault_balance,
    deposit_to_vault,
    withdraw_from_vault,
    get_eth_balance,
    get_policy_rules,
    get_recent_decisions,
)

load_dotenv()

# ── Contract addresses (from deployment) ──────────────────────────
REGISTRY_ADDR = os.getenv("POLICY_REGISTRY_ADDRESS", "")
ENFORCER_ADDR = os.getenv("POLICY_ENFORCER_ADDRESS", "")
LOGGER_ADDR   = os.getenv("PDR_LOGGER_ADDRESS", "")
VAULT_ADDR    = os.getenv("MOCK_VAULT_ADDRESS", "")


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  Policy enforcement middleware
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def enforce_policy(action_type: str, target: str, prompt: str,
                   matched_keywords: str = "", classifier_score: int = 0) -> dict:
    """
    Call PolicyEnforcer.validateAction on-chain BEFORE executing any
    blockchain action.  Returns the decision dict.
    """
    if not ENFORCER_ADDR:
        return {"decision": "ALLOW", "reason": "Enforcer not configured"}

    enforcer = get_contract("PolicyEnforcer", ENFORCER_ADDR)
    prompt_hash = Web3.keccak(text=prompt)

    receipt = send_tx(
        enforcer.functions.validateAction(
            account.address,
            action_type,
            Web3.to_checksum_address(target) if target else account.address,
            prompt_hash,
            matched_keywords,
            classifier_score,
        )
    )

    # Parse the ActionValidated event
    enforcer_contract = get_contract("PolicyEnforcer", ENFORCER_ADDR)
    logs = enforcer_contract.events.ActionValidated().process_receipt(receipt)

    if logs:
        event = logs[0]["args"]
        decision_map = {0: "ALLOW", 1: "BLOCK", 2: "WARN"}
        return {
            "decision": decision_map.get(event["decision"], "UNKNOWN"),
            "matchedRuleId": event["matchedRuleId"],
            "classifierScore": event["classifierScore"],
            "reason": event["reason"],
        }

    return {"decision": "ALLOW", "reason": "No event emitted"}


def keyword_scan(prompt: str) -> str:
    """
    Simple off-chain keyword scan — returns comma-separated matches.
    This is the pre-screening step before on-chain validation.
    """
    suspicious_keywords = [
        "ignore previous instructions",
        "disregard all prior",
        "override safety",
        "transfer all funds",
        "drain wallet",
        "send to external",
        "bypass verification",
        "execute raw transaction",
    ]
    prompt_lower = prompt.lower()
    matches = [kw for kw in suspicious_keywords if kw in prompt_lower]
    return ", ".join(matches)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  LangChain tools (wrapped with policy enforcement)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@tool
def vault_deposit(amount_eth: float) -> str:
    """Deposit ETH into the DeFi vault. Amount in ETH."""
    prompt_text = f"deposit {amount_eth} ETH to vault"
    keywords = keyword_scan(prompt_text)

    # Policy check
    result = enforce_policy("deposit", VAULT_ADDR, prompt_text, keywords)
    if result["decision"] == "BLOCK":
        return f"ACTION BLOCKED by ChainGuard: {result['reason']}"
    if result["decision"] == "WARN":
        warning = f"WARNING from ChainGuard: {result['reason']}"

    # Execute
    response = deposit_to_vault(VAULT_ADDR, amount_eth)
    prefix = f"[WARN: {result['reason']}] " if result["decision"] == "WARN" else ""
    return prefix + response


@tool
def vault_withdraw(amount_eth: float) -> str:
    """Withdraw ETH from the DeFi vault. Amount in ETH."""
    prompt_text = f"withdraw {amount_eth} ETH from vault"
    keywords = keyword_scan(prompt_text)

    result = enforce_policy("withdraw", VAULT_ADDR, prompt_text, keywords)
    if result["decision"] == "BLOCK":
        return f"ACTION BLOCKED by ChainGuard: {result['reason']}"

    response = withdraw_from_vault(VAULT_ADDR, amount_eth)
    prefix = f"[WARN: {result['reason']}] " if result["decision"] == "WARN" else ""
    return prefix + response


@tool
def vault_balance() -> str:
    """Check the agent's balance in the DeFi vault."""
    return check_vault_balance(VAULT_ADDR, account.address)


@tool
def wallet_balance() -> str:
    """Check the agent's ETH wallet balance."""
    return get_eth_balance(account.address)


@tool
def view_policy_rules() -> str:
    """View all active ChainGuard policy rules."""
    return get_policy_rules(REGISTRY_ADDR)


@tool
def view_decision_log() -> str:
    """View the last 5 policy enforcement decisions."""
    return get_recent_decisions(LOGGER_ADDR, 5)


@tool
def execute_raw_action(action_description: str) -> str:
    """
    Execute any described blockchain action. The description is
    passed through ChainGuard policy enforcement first.
    """
    keywords = keyword_scan(action_description)
    target = VAULT_ADDR if VAULT_ADDR else account.address

    result = enforce_policy("custom", target, action_description, keywords)
    if result["decision"] == "BLOCK":
        return f"ACTION BLOCKED by ChainGuard: {result['reason']}"
    if result["decision"] == "WARN":
        return f"ACTION ALLOWED WITH WARNING: {result['reason']}. Description: {action_description}"

    return f"Action validated and allowed: {action_description}"


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  LangChain Agent setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SYSTEM_PROMPT = """You are a DeFi AI assistant that helps users interact with
blockchain protocols. You can deposit/withdraw ETH from a vault, check balances,
and view security policy rules.

IMPORTANT: All your actions are monitored by the ChainGuard security framework.
Any suspicious or potentially malicious instructions will be detected and blocked
by on-chain smart contract policies.

Available actions:
- Deposit ETH to vault
- Withdraw ETH from vault
- Check vault balance
- Check wallet balance
- View active security policy rules
- View recent policy decisions
- Execute custom blockchain actions

Always confirm the action with the user before executing transactions."""

tools = [
    vault_deposit,
    vault_withdraw,
    vault_balance,
    wallet_balance,
    view_policy_rules,
    view_decision_log,
    execute_raw_action,
]

prompt = ChatPromptTemplate.from_messages([
    ("system", SYSTEM_PROMPT),
    MessagesPlaceholder("chat_history", optional=True),
    ("human", "{input}"),
    MessagesPlaceholder("agent_scratchpad"),
])


def get_llm():
    """
    Create the LLM instance.
    Priority: Groq (free) → Google Gemini (free) → OpenAI GPT-4 (paid)
    """
    groq_key = os.getenv("GROQ_API_KEY")
    google_key = os.getenv("GOOGLE_API_KEY")
    openai_key = os.getenv("OPENAI_API_KEY")

    if groq_key:
        from langchain_groq import ChatGroq
        print("[LLM] Using Groq (Llama 3.1 70B - free tier)")
        return ChatGroq(
            model="llama-3.1-70b-versatile",
            api_key=groq_key,
            temperature=0,
        )
    elif google_key:
        from langchain_google_genai import ChatGoogleGenerativeAI
        print("[LLM] Using Google Gemini (free tier)")
        return ChatGoogleGenerativeAI(
            model="gemini-1.5-flash",
            google_api_key=google_key,
            temperature=0,
            convert_system_message_to_human=True,
        )
    elif openai_key:
        from langchain_openai import ChatOpenAI
        print("[LLM] Using OpenAI GPT-4")
        return ChatOpenAI(
            model="gpt-4",
            temperature=0,
            openai_api_key=openai_key,
        )
    else:
        raise ValueError(
            "No API key found!\n"
            "Set GROQ_API_KEY (free, recommended) or GOOGLE_API_KEY or OPENAI_API_KEY in agent/.env\n"
            "Get a free Groq key at: https://console.groq.com"
        )


def create_agent():
    """Create and return the LangChain agent executor."""
    llm = get_llm()
    agent = create_tool_calling_agent(llm, tools, prompt)
    return AgentExecutor(
        agent=agent,
        tools=tools,
        verbose=True,
        handle_parsing_errors=True,
    )


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  Interactive CLI
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def main():
    print("=" * 60)
    print("  ChainGuard AI Agent — LangChain + On-chain Policy")
    print("=" * 60)
    print()

    if not os.getenv("GOOGLE_API_KEY") and not os.getenv("OPENAI_API_KEY"):
        print("ERROR: No API key found!")
        print("  Option 1 (FREE): Get a Gemini key at https://aistudio.google.com/apikey")
        print("                    Set GOOGLE_API_KEY in agent/.env")
        print("  Option 2 (PAID): Set OPENAI_API_KEY in agent/.env")
        return

    if not ENFORCER_ADDR:
        print("WARNING: Contract addresses not set. Deploy first:")
        print("  npm run node        (terminal 1)")
        print("  npm run deploy:local (terminal 2)")
        print("  Copy addresses to agent/.env")
        print()

    agent_executor = create_agent()
    chat_history = []

    print("\nType your commands (or 'quit' to exit):")
    print("-" * 60)

    while True:
        try:
            user_input = input("\nYou: ").strip()
            if not user_input:
                continue
            if user_input.lower() in ("quit", "exit", "q"):
                print("Goodbye!")
                break

            response = agent_executor.invoke({
                "input": user_input,
                "chat_history": chat_history,
            })

            print(f"\nAgent: {response['output']}")

            # Keep chat history
            from langchain_core.messages import HumanMessage, AIMessage
            chat_history.append(HumanMessage(content=user_input))
            chat_history.append(AIMessage(content=response["output"]))

        except KeyboardInterrupt:
            print("\nGoodbye!")
            break
        except Exception as e:
            print(f"\nError: {e}")


if __name__ == "__main__":
    main()
