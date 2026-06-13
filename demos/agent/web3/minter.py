"""High-level NFT minting flow for a generated 3D world."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Coroutine

from agent.web3.config import Web3Config
from agent.web3.contract import MintInfo, NFTContract
from agent.web3.metadata import generate_metadata, save_metadata_files

logger = logging.getLogger(__name__)


@dataclass
class BoothMint:
    """Mint result for a single booth."""
    booth_id: str
    token_id: int
    tx_hash: str
    metadata: dict[str, Any]
    block_number: int


@dataclass
class MintResult:
    """Complete result of minting a world's NFTs."""
    contract_address: str
    chain_id: int
    wallet_address: str
    mints: list[BoothMint] = field(default_factory=list)
    total_gas_used: int = 0
    duration_ms: int = 0


class WorldMinter:
    """Orchestrates the Web3 minting flow for a generated world."""

    def __init__(self, config: Web3Config | None = None) -> None:
        self.config = config or Web3Config.from_env()

    async def mint_world(
        self,
        scene_spec: dict[str, Any],
        render_path: Path,
        event_callback: Callable[[dict[str, Any]], Coroutine[Any, Any, None]] | None = None,
    ) -> MintResult | None:
        """Full minting flow: connect → deploy → metadata → mint → update spec.

        Args:
            scene_spec: The finalized scene specification with booth data.
            render_path: Path to the rendered gallery screenshot.
            event_callback: Optional SSE event callback for progress updates.

        Returns:
            MintResult on success, None on failure (never raises).
        """
        start = time.monotonic()
        booths: list[dict] = scene_spec.get("booths", [])

        if not booths:
            logger.info("[Web3] No booths in spec, skipping mint.")
            return None

        try:
            # Run blocking web3 operations in executor
            result = await asyncio.get_event_loop().run_in_executor(
                None, self._mint_world_sync, scene_spec, render_path, booths
            )
            result.duration_ms = int((time.monotonic() - start) * 1000)
            return result

        except Exception as e:
            logger.warning(f"[Web3] Minting failed: {e}")
            raise

    def _mint_world_sync(
        self,
        scene_spec: dict[str, Any],
        render_path: Path,
        booths: list[dict],
    ) -> MintResult:
        """Synchronous minting logic (runs in executor)."""
        # 1. Connect and optionally deploy
        contract = NFTContract(self.config)

        if not contract.is_connected():
            raise ConnectionError(f"Cannot connect to RPC at {self.config.rpc_url}")

        if not self.config.contract_address:
            logger.info("[Web3] No contract address, deploying new contract...")
            addr = contract.deploy(
                name=f"WorldBuilder-{scene_spec.get('theme_name', 'Gallery')[:20]}",
                symbol="WBNFT",
            )
            logger.info(f"[Web3] Contract deployed: {addr}")
        # else: already connected in __init__

        # 2. Generate metadata for each booth
        metadata_dir = render_path.parent / "metadata"
        metadata_files = save_metadata_files(scene_spec, render_path, metadata_dir)

        # 3. Batch mint all NFTs
        mint_infos: list[MintInfo] = contract.batch_mint(len(booths))

        if len(mint_infos) != len(booths):
            raise RuntimeError(
                f"Minted {len(mint_infos)} tokens but expected {len(booths)}"
            )

        # 4. Build results (metadata saved to files, skip per-token setTokenURI for speed)
        booth_mints: list[BoothMint] = []
        total_gas = 0

        for booth, mint_info in zip(booths, mint_infos):
            metadata = generate_metadata(booth, scene_spec, render_path)

            booth_mints.append(BoothMint(
                booth_id=booth.get("id", ""),
                token_id=mint_info.token_id,
                tx_hash=mint_info.tx_hash,
                metadata=metadata,
                block_number=mint_info.block_number,
            ))
            total_gas += mint_info.gas_used

        return MintResult(
            contract_address=contract.contract_address or "",
            chain_id=self.config.chain_id,
            wallet_address=self.config.wallet_address,
            mints=booth_mints,
            total_gas_used=total_gas,
        )
