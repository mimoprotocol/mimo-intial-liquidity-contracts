// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Token is ERC721("NFT Token", "TNFT") {
    function mint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }
}
