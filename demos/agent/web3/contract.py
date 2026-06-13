"""ERC-721 contract interaction via web3.py."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Any

from eth_account import Account
from web3 import Web3
from web3.types import TxReceipt

from agent.web3.config import Web3Config, get_abi, get_bytecode

logger = logging.getLogger(__name__)


@dataclass
class MintInfo:
    """Result of minting a single NFT."""
    token_id: int
    tx_hash: str
    block_number: int
    gas_used: int


class NFTContract:
    """Deploy and interact with the WorldBuilderNFT contract."""

    def __init__(self, config: Web3Config) -> None:
        self.config = config
        self.w3 = Web3(Web3.HTTPProvider(config.rpc_url))
        self.account = Account.from_key(config.private_key)
        self._contract: Any = None

        if config.contract_address:
            self._contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(config.contract_address),
                abi=get_abi(),
            )
            logger.info(f"[Web3] Connected to existing contract: {config.contract_address}")

    @property
    def contract_address(self) -> str | None:
        if self._contract:
            return self._contract.address
        return None

    def is_connected(self) -> bool:
        return self.w3.is_connected()

    def deploy(self, name: str = "WorldBuilderNFT", symbol: str = "WBNFT") -> str:
        """Deploy a new contract. Returns the deployed address."""
        contract = self.w3.eth.contract(abi=get_abi(), bytecode=get_bytecode())

        nonce = self.w3.eth.get_transaction_count(self.account.address)
        tx = contract.constructor(name, symbol).build_transaction({
            "from": self.account.address,
            "nonce": nonce,
            "gas": self.config.gas_limit,
            "maxFeePerGas": self.w3.to_wei(50, "gwei"),
            "maxPriorityFeePerGas": self.w3.to_wei(2, "gwei"),
            "chainId": self.config.chain_id,
        })

        signed = self.account.sign_transaction(tx)
        tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

        if receipt.status != 1:
            raise RuntimeError(f"Contract deployment failed: {receipt}")

        address = receipt.contractAddress
        self._contract = self.w3.eth.contract(
            address=address,
            abi=get_abi(),
        )
        logger.info(f"[Web3] Deployed contract at {address} (tx: {tx_hash.hex()})")
        return address

    def batch_mint(self, count: int) -> list[MintInfo]:
        """Mint `count` NFTs to the deployer wallet. Returns mint info per token."""
        if not self._contract:
            raise RuntimeError("No contract connected. Call deploy() first.")

        nonce = self.w3.eth.get_transaction_count(self.account.address)
        to_address = Web3.to_checksum_address(self.account.address)

        # Use batchMint for efficiency
        tx = self._contract.functions.batchMint(to_address, count).build_transaction({
            "from": self.account.address,
            "nonce": nonce,
            "gas": self.config.gas_limit,
            "maxFeePerGas": self.w3.to_wei(50, "gwei"),
            "maxPriorityFeePerGas": self.w3.to_wei(2, "gwei"),
            "chainId": self.config.chain_id,
        })

        signed = self.account.sign_transaction(tx)
        tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

        if receipt.status != 1:
            raise RuntimeError(f"Batch mint failed: {receipt}")

        # Parse Transfer events to get token IDs
        mints: list[MintInfo] = []
        transfer_topic = self.w3.keccak(text="Transfer(address,address,uint256)").hex()

        for log in receipt.logs:
            if len(log.topics) == 4 and log.topics[0].hex() == transfer_topic:
                token_id = int(log.topics[3].hex(), 16)
                mints.append(MintInfo(
                    token_id=token_id,
                    tx_hash=tx_hash.hex(),
                    block_number=receipt.blockNumber,
                    gas_used=receipt.gasUsed,
                ))

        # Fallback: if no Transfer events parsed, derive from totalMinted
        if not mints:
            total = self._contract.functions.totalMinted().call()
            start_id = total - count + 1
            for i in range(count):
                mints.append(MintInfo(
                    token_id=start_id + i,
                    tx_hash=tx_hash.hex(),
                    block_number=receipt.blockNumber,
                    gas_used=receipt.gasUsed,
                ))

        logger.info(f"[Web3] Minted {len(mints)} NFTs (tx: {tx_hash.hex()})")
        return mints

    def set_token_uri(self, token_id: int, uri: str) -> str:
        """Set metadata URI for a token."""
        if not self._contract:
            raise RuntimeError("No contract connected.")

        nonce = self.w3.eth.get_transaction_count(self.account.address)
        tx = self._contract.functions.setTokenURI(token_id, uri).build_transaction({
            "from": self.account.address,
            "nonce": nonce,
            "gas": 500_000,
            "maxFeePerGas": self.w3.to_wei(50, "gwei"),
            "maxPriorityFeePerGas": self.w3.to_wei(2, "gwei"),
            "chainId": self.config.chain_id,
        })

        signed = self.account.sign_transaction(tx)
        tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

        if receipt.status != 1:
            raise RuntimeError(f"setTokenURI failed for token {token_id}")

        logger.info(f"[Web3] Set URI for token {token_id} (tx: {tx_hash.hex()})")
        return tx_hash.hex()
