// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

abstract contract VisitedChainsMixin {
    uint8 currentChainId;
    mapping(uint256 => uint256) public visitedChainsMask;

    constructor(uint8 chainId) {
        currentChainId = chainId;
    }

    function getVisitedChains(
        uint256 id
    ) external view returns (uint8[] memory visitedChains) {
        uint256 mask = visitedChainsMask[id];

        uint256 numOfVisitedChains = 0;
        for (uint8 chainId = 0; chainId < 255; chainId++) {
            if (_isChainVisited(mask, chainId)) {
                numOfVisitedChains++;
            }
        }

        visitedChains = new uint8[](numOfVisitedChains);
        for (uint8 chainId = 0; chainId < 255; chainId++) {
            if (_isChainVisited(mask, chainId)) {
                visitedChains[--numOfVisitedChains] = chainId;
            }

            if (numOfVisitedChains == 0) {
                break;
            }
        }
    }

    function _isChainVisited(
        uint256 mask,
        uint256 chainId
    ) internal pure returns (bool) {
        return mask & (1 << chainId) > 0;
    }

    function _visitChain(uint256 id) internal {
        visitedChainsMask[id] |= 1 << currentChainId;
    }
}
