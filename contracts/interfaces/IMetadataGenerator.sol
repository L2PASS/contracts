// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface IMetadataGenerator {
    function generateMetadata(
        uint256 tokenId
    ) external view returns (string memory);
}
