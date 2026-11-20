"""
blockchain_tools.py — Web3-based tools the LangChain agent can call
to interact with the ChainGuard contracts and mock DeFi protocols.
"""

import json
import os
from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

# ── Web3 setup ────────────────────────────────────────────────────
w3 = Web3(Web3.HTTPProvider(os.getenv("RPC_URL", "http://127.0.0.1:8545")))
account = w3.eth.account.from_key(os.getenv("PRIVATE_KEY"))


def _load_abi(contract_name: str) -> list:
    """Load ABI from Hardhat artifacts."""
    artifact_path = os.path.join(
        os.path.dirname(__file__),
        "..",
        "artifacts",
        "contracts",
        f"{contract_name}.sol" if "/" not in contract_name
        else contract_name.rsplit("/", 1)[0] + f"/{contract_name.rsplit('/', 1)[1]}.sol",
        f"{contract_name.rsplit('/', 1)[-1]}.json",
    )
    with open(artifact_path) as f:
        return json.load(f)["abi"]


def get_contract(name: str, address: str):
    """Return a Web3 contract instance."""
    abi = _load_abi(name)
    return w3.eth.contract(address=Web3.to_checksum_address(address), abi=abi)


# ── Helper: send a transaction ────────────────────────────────────
def send_tx(contract_fn, value=0):
    """Build, sign, send a transaction and return the receipt."""
    tx = contract_fn.build_transaction({
        "from": account.address,
        "nonce": w3.eth.get_transaction_count(account.address),
        "gas": 3_000_000,
        "gasPrice": w3.eth.gas_price,
        "value": value,
    })
    signed = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    return w3.eth.wait_for_transaction_receipt(tx_hash)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  Tool functions the LangChain agent will use
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def check_vault_balance(vault_address: str, user_address: str) -> str:
    """Check a user's balance in the MockVault."""
    vault = get_contract("mocks/MockVault", vault_address)
    bal = vault.functions.getBalance(Web3.to_checksum_address(user_address)).call()
    eth_bal = w3.from_wei(bal, "ether")
    return f"Vault balance for {user_address}: {eth_bal} ETH"


def deposit_to_vault(vault_address: str, amount_eth: float) -> str:
    """Deposit ETH into the MockVault."""
    vault = get_contract("mocks/MockVault", vault_address)
    value = w3.to_wei(amount_eth, "ether")
    receipt = send_tx(vault.functions.deposit(), value=value)
    return f"Deposited {amount_eth} ETH to vault. Tx: {receipt.transactionHash.hex()}"


def withdraw_from_vault(vault_address: str, amount_eth: float) -> str:
    """Withdraw ETH from the MockVault."""
    vault = get_contract("mocks/MockVault", vault_address)
    value = w3.to_wei(amount_eth, "ether")
    receipt = send_tx(vault.functions.withdraw(value))
    return f"Withdrew {amount_eth} ETH from vault. Tx: {receipt.transactionHash.hex()}"


def get_eth_balance(address: str) -> str:
    """Get the ETH balance of any address."""
    bal = w3.eth.get_balance(Web3.to_checksum_address(address))
    return f"ETH balance of {address}: {w3.from_wei(bal, 'ether')} ETH"


def get_policy_rules(registry_address: str) -> str:
    """List all active rules from PolicyRegistry."""
    registry = get_contract("PolicyRegistry", registry_address)
    rules = registry.functions.getActiveRules().call()
    if not rules:
        return "No active policy rules found."

    lines = ["Active policy rules:"]
    for r in rules:
        severity_map = {0: "LOW", 1: "MEDIUM", 2: "HIGH", 3: "CRITICAL"}
        lines.append(
            f"  Rule #{r[0]}: pattern='{r[1]}', severity={severity_map.get(r[2], r[2])}"
        )
    return "\n".join(lines)


def get_recent_decisions(logger_address: str, count: int = 5) -> str:
    """Get recent policy decision records from PDRLogger."""
    logger = get_contract("PDRLogger", logger_address)
    records = logger.functions.getRecentRecords(count).call()
    if not records:
        return "No decision records found."

    decision_map = {0: "ALLOW", 1: "BLOCK", 2: "WARN"}
    lines = [f"Last {len(records)} policy decisions:"]
    for r in records:
        lines.append(
            f"  Record #{r[0]}: agent={r[1][:10]}..., action={r[2]}, "
            f"decision={decision_map.get(r[4], r[4])}, reason={r[8]}"
        )
    return "\n".join(lines)
