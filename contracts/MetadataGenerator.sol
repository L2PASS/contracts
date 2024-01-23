// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMetadataGenerator} from "./interfaces/IMetadataGenerator.sol";
import {VisitedChainsMixin} from "./core/VisitedChainsMixin.sol";

contract MetadataGenerator is Ownable, IMetadataGenerator {
    struct ChainName {
        uint8 id;
        string name;
    }

    uint256 public width = 1250;
    uint256 public height = 1500;

    uint256 numChains;
    mapping(uint8 => string) chainNames;

    function setSize(uint256 width_, uint256 height_) external onlyOwner {
        width = width_;
        height = height_;
    }

    function addChainName(
        ChainName[] calldata chainName,
        uint256 numChains_
    ) external onlyOwner {
        uint256 n = chainName.length;
        for (uint256 i = 0; i < n; i++) {
            chainNames[chainName[i].id] = chainName[i].name;
        }

        numChains = numChains_;
    }

    function generateMetadata(
        uint256 tokenId
    ) external view returns (string memory) {
        uint256 chainMaks = VisitedChainsMixin(msg.sender).visitedChainsMask(
            tokenId
        );
        uint8[] memory chainIds = VisitedChainsMixin(msg.sender)
            .getVisitedChains(tokenId);

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            '{"name":"MEME #',
                            Strings.toString(tokenId),
                            '","description":"Mememorphosis: A groundbreaking NFT collection blurring the lines between art and audience, where each piece evolves through collector engagement, forging a unique artistic journey.","image":"',
                            "https://l2pass.com/nft/",
                            Strings.toString(chainMaks),
                            ".png",
                            '","attributes":',
                            generateAttributes(chainIds),
                            "}"
                        )
                    )
                )
            );
    }

    function generateAttributes(
        uint8[] memory chainIds
    ) internal view returns (string memory attributes) {
        uint8 n = uint8(chainIds.length);

        attributes = string(
            abi.encodePacked(
                '[{"trait_type":"Memes collect","display_type":"number","value":',
                Strings.toString(n),
                ',"max_value":',
                Strings.toString(numChains),
                "}"
            )
        );

        for (uint8 i = 0; i < n; i++) {
            if (Strings.equal(chainNames[chainIds[i]], "")) continue;

            attributes = string(
                abi.encodePacked(
                    attributes,
                    string(
                        abi.encodePacked(
                            ',{"trait_type":"Chain","value":"',
                            chainNames[chainIds[i]],
                            '"}'
                        )
                    )
                )
            );
        }
        attributes = string(
            abi.encodePacked(attributes, abi.encodePacked("]"))
        );
    }
}
