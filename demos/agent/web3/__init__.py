"""Web3 integration module for the 3D World Builder.

Provides NFT minting, contract deployment, and metadata generation
for booth artworks in the generated virtual worlds.
"""

from agent.web3.config import Web3Config
from agent.web3.minter import WorldMinter

__all__ = ["Web3Config", "WorldMinter"]
