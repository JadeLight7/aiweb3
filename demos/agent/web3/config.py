"""Web3 configuration and contract artifacts."""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)

# Load pre-compiled ABI + bytecode
_ARTIFACTS_PATH = Path(__file__).resolve().parent.parent / "web3_contract_artifacts.json"
_ABI: list | None = None
_BYTECODE: str | None = None


def get_abi() -> list:
    global _ABI
    if _ABI is None:
        _load_artifacts()
    return _ABI  # type: ignore[return-value]


def get_bytecode() -> str:
    global _BYTECODE
    if _BYTECODE is None:
        _load_artifacts()
    return _BYTECODE  # type: ignore[return-value]


def _load_artifacts() -> None:
    global _ABI, _BYTECODE
    try:
        with open(_ARTIFACTS_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        _ABI = data["abi"]
        _BYTECODE = data["bytecode"]
    except FileNotFoundError:
        logger.warning(f"Contract artifacts not found at {_ARTIFACTS_PATH}")
        _ABI = []
        _BYTECODE = "0x"


# Anvil default account (pre-funded)
ANVIL_DEFAULT_PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ANVIL_DEFAULT_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Chain profiles
CHAIN_PROFILES: dict[str, dict] = {
    "anvil": {
        "rpc_url": "http://127.0.0.1:8545",
        "chain_id": 31337,
        "private_key": ANVIL_DEFAULT_PRIVATE_KEY,
        "block_explorer": "",
    },
    "sepolia": {
        "rpc_url": "https://rpc.sepolia.org",
        "chain_id": 11155111,
        "private_key": "",
        "block_explorer": "https://sepolia.etherscan.io",
    },
}


@dataclass
class Web3Config:
    """Web3 chain configuration."""

    rpc_url: str = "http://127.0.0.1:8545"
    chain_id: int = 31337
    private_key: str = ANVIL_DEFAULT_PRIVATE_KEY
    contract_address: str | None = None
    gas_limit: int = 3_000_000
    block_explorer: str = ""

    @property
    def wallet_address(self) -> str:
        if not self.private_key:
            return ""
        from eth_account import Account
        return Account.from_key(self.private_key).address

    @staticmethod
    def from_env() -> Web3Config:
        """Load config from environment variables."""
        chain = os.environ.get("WEB3_CHAIN", "anvil").lower()
        profile = CHAIN_PROFILES.get(chain, CHAIN_PROFILES["anvil"])

        return Web3Config(
            rpc_url=os.environ.get("WEB3_RPC_URL", profile["rpc_url"]),
            chain_id=int(os.environ.get("WEB3_CHAIN_ID", profile["chain_id"])),
            private_key=os.environ.get("WEB3_PRIVATE_KEY", profile["private_key"]),
            contract_address=os.environ.get("WEB3_CONTRACT_ADDRESS") or None,
            block_explorer=os.environ.get("WEB3_BLOCK_EXPLORER", profile.get("block_explorer", "")),
        )

    @staticmethod
    def anvil() -> Web3Config:
        return Web3Config(
            rpc_url="http://127.0.0.1:8545",
            chain_id=31337,
            private_key=ANVIL_DEFAULT_PRIVATE_KEY,
        )

    @staticmethod
    def sepolia(rpc_url: str, private_key: str) -> Web3Config:
        return Web3Config(
            rpc_url=rpc_url,
            chain_id=11155111,
            private_key=private_key,
            block_explorer="https://sepolia.etherscan.io",
        )
