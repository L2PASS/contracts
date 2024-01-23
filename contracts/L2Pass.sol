// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {ONFT721WithVisitedChains} from "./core/ONFT721WithVisitedChains.sol";
import {IMetadataGenerator} from "./interfaces/IMetadataGenerator.sol";

contract L2Pass is ONFT721WithVisitedChains {
    address public metadataGenerator;
    uint256 public nextMintId;
    uint256 public maxMintId;

    uint256 public mintPrice;
    uint256 public sendPrice;

    event Referral(address referrer, address referral);

    constructor(
        uint256 minGasToStore,
        uint256 defaultGasLimit,
        address layerZeroEndpoint,
        uint256 startMintId,
        uint256 endMintId,
        uint256 mintPrice_,
        uint256 sendPrice_,
        uint8 chainId
    )
        ONFT721WithVisitedChains(
            "Mememorphosis",
            "L2PASS",
            minGasToStore,
            defaultGasLimit,
            layerZeroEndpoint,
            chainId
        )
    {
        mintPrice = mintPrice_;
        sendPrice = sendPrice_;

        nextMintId = startMintId;
        maxMintId = endMintId;
    }

    function mintWithReferral(uint256 n, address referrer) external payable {
        emit Referral(referrer, msg.sender);
        _mint(n);
    }

    function mint(uint256 n) external payable {
        _mint(n);
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(_exists(tokenId));
        if (metadataGenerator == address(0)) return "";
        return IMetadataGenerator(metadataGenerator).generateMetadata(tokenId);
    }

    function setMetadataGenerator(
        address metadataGenerator_
    ) external onlyOwner {
        metadataGenerator = metadataGenerator_;
    }

    function setMintPrice(uint256 mintPrice_) external onlyOwner {
        mintPrice = mintPrice_;
    }

    function setSendPrice(uint256 sendPrice_) external onlyOwner {
        sendPrice = sendPrice_;
    }

    function claimFunds() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}(
            ""
        );
        require(success);
    }

    fallback() external payable {}

    receive() external payable {}

    function _mint(uint256 n) internal {
        require(msg.value >= mintPrice * n);

        for (uint256 i = 0; i < n; i++) {
            require(nextMintId <= maxMintId);
            uint newId = nextMintId;
            nextMintId++;

            _safeMint(msg.sender, newId);
            _visitChain(newId);
        }
    }

    function _send(
        address _from,
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint[] memory _tokenIds,
        address payable,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) internal virtual override {
        uint256 n = _tokenIds.length;

        require(n > 0);
        require(n == 1 || n <= dstChainIdToBatchLimit[_dstChainId]);

        for (uint i = 0; i < n; i++) {
            _debitFrom(_from, _dstChainId, _toAddress, _tokenIds[i]);
        }

        _checkGasLimit(
            _dstChainId,
            FUNCTION_TYPE_SEND,
            _adapterParams,
            dstChainIdToTransferGas[_dstChainId] * n
        );
        _lzSend(
            _dstChainId,
            _generatePayload(_toAddress, _tokenIds),
            payable(address(this)),
            _zroPaymentAddress,
            _adapterParams,
            msg.value - n * sendPrice
        );
        emit SendToChain(_dstChainId, _from, _toAddress, _tokenIds);
    }
}
