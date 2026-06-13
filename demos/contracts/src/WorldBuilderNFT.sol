// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title WorldBuilderNFT — Minimal ERC-721 for AI-generated 3D world NFTs
/// @notice Each minted token represents a booth artwork in a virtual gallery
contract WorldBuilderNFT is ERC721 {
    uint256 private _nextTokenId;
    mapping(uint256 => string) private _tokenURIs;

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {
        _nextTokenId = 1;
    }

    /// @notice Mint a single NFT to `to` with metadata `uri`
    function mint(address to, string calldata uri) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _tokenURIs[tokenId] = uri;
        return tokenId;
    }

    /// @notice Mint `count` NFTs to `to` in one transaction
    function batchMint(address to, uint256 count) external returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(to, tokenId);
            ids[i] = tokenId;
        }
        return ids;
    }

    /// @notice Set/update metadata URI for a token
    function setTokenURI(uint256 tokenId, string calldata uri) external {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        _tokenURIs[tokenId] = uri;
    }

    /// @notice Total number of minted tokens
    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        string memory uri = _tokenURIs[tokenId];
        if (bytes(uri).length > 0) {
            return uri;
        }
        return string(abi.encodePacked("https://worldbuilder.ai/nft/", _toString(tokenId)));
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
