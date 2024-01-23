// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {ONFT721Core, IONFT721Core} from "@layerzerolabs/solidity-examples/contracts/token/onft721/ONFT721Core.sol";
import {IONFT721} from "@layerzerolabs/solidity-examples/contracts/token/onft721/interfaces/IONFT721.sol";
import {ERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import {VisitedChainsMixin} from "./VisitedChainsMixin.sol";

contract ONFT721WithVisitedChains is
    ONFT721Core,
    ERC721Enumerable,
    IONFT721,
    VisitedChainsMixin
{
    uint256 immutable defaultGasLimit;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _minGasToTransfer,
        uint256 defaultGasLimit_,
        address _lzEndpoint,
        uint8 chainId
    )
        ERC721(_name, _symbol)
        ONFT721Core(_minGasToTransfer, _lzEndpoint)
        VisitedChainsMixin(chainId)
    {
        defaultGasLimit = defaultGasLimit_;
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ONFT721Core, ERC721Enumerable, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IONFT721).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function estimateSendBatchFee(
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint[] memory _tokenIds,
        bool _useZro,
        bytes memory _adapterParams
    )
        public
        view
        virtual
        override(IONFT721Core, ONFT721Core)
        returns (uint nativeFee, uint zroFee)
    {
        return
            lzEndpoint.estimateFees(
                _dstChainId,
                address(this),
                _generatePayload(_toAddress, _tokenIds),
                _useZro,
                _adapterParams
            );
    }

    function _mint(address to, uint256 tokenId) internal virtual override {
        //TODO: use _afterTokenTransfer
        super._mint(to, tokenId);
        _visitChain(tokenId);
    }

    function _debitFrom(
        address _from,
        uint16,
        bytes memory,
        uint _tokenId
    ) internal virtual override {
        require(_isApprovedOrOwner(_msgSender(), _tokenId));
        require(ERC721.ownerOf(_tokenId) == _from);
        _burn(_tokenId);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 /*_nonce*/,
        bytes memory _payload
    ) internal virtual override {
        // decode and load the toAddress
        (
            bytes memory toAddressBytes,
            uint256[] memory tokenIds,
            uint256[] memory chains
        ) = abi.decode(_payload, (bytes, uint[], uint256[]));

        address toAddress;
        assembly {
            toAddress := mload(add(toAddressBytes, 20))
        }

        uint nextIndex = _creditTill(
            _srcChainId,
            toAddress,
            0,
            tokenIds,
            chains
        );
        if (nextIndex < tokenIds.length) {
            // not enough gas to complete transfers, store to be cleared in another tx
            bytes32 hashedPayload = keccak256(_payload);
            storedCredits[hashedPayload] = StoredCredit(
                _srcChainId,
                toAddress,
                nextIndex,
                true
            );
            emit CreditStored(hashedPayload, _payload);
        }

        emit ReceiveFromChain(_srcChainId, _srcAddress, toAddress, tokenIds);
    }

    function clearCredits(
        bytes memory _payload
    ) external override nonReentrant {
        bytes32 hashedPayload = keccak256(_payload);
        require(storedCredits[hashedPayload].creditsRemain);

        // decode and load the toAddress
        (, uint256[] memory tokenIds, uint256[] memory chains) = abi.decode(
            _payload,
            (bytes, uint[], uint256[])
        );

        uint nextIndex = _creditTill(
            storedCredits[hashedPayload].srcChainId,
            storedCredits[hashedPayload].toAddress,
            storedCredits[hashedPayload].index,
            tokenIds,
            chains
        );
        require(nextIndex > storedCredits[hashedPayload].index);

        if (nextIndex == tokenIds.length) {
            // cleared the credits, delete the element
            delete storedCredits[hashedPayload];
            emit CreditCleared(hashedPayload);
        } else {
            // store the next index to mint
            storedCredits[hashedPayload] = StoredCredit(
                storedCredits[hashedPayload].srcChainId,
                storedCredits[hashedPayload].toAddress,
                nextIndex,
                true
            );
        }
    }

    function _creditTill(
        uint16 _srcChainId,
        address _toAddress,
        uint _startIndex,
        uint[] memory _tokenIds,
        uint256[] memory _chains
    ) internal returns (uint256) {
        uint i = _startIndex;

        while (i < _tokenIds.length) {
            // if not enough gas to process, store this index for next loop
            if (gasleft() < minGasToTransferAndStore) break;

            _creditTo(_srcChainId, _toAddress, _tokenIds[i], _chains[i]);
            i++;
        }

        // indicates the next index to send of tokenIds,
        // if i == tokenIds.length, we are finished
        return i;
    }

    function _creditTo(uint16, address, uint) internal override {}

    function _creditTo(
        uint16,
        address _toAddress,
        uint _tokenId,
        uint256 _visitedChains
    ) internal virtual {
        _safeMint(_toAddress, _tokenId);
        // we don't use _visitChain(_tokenId) because of sstore optimisation
        visitedChainsMask[_tokenId] = _visitedChains | (1 << currentChainId);
    }

    function _generatePayload(
        bytes memory _toAddress,
        uint256[] memory _tokenIds
    ) internal view returns (bytes memory) {
        uint256 n = _tokenIds.length;
        uint256[] memory _visitedChains = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            _visitedChains[i] = visitedChainsMask[_tokenIds[i]];
        }

        return abi.encode(_toAddress, _tokenIds, _visitedChains);
    }

    function _lzSend(
        uint16 _dstChainId,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams,
        uint _nativeFee
    ) internal virtual override {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];
        if (trustedRemote.length == 0) {
            trustedRemote = abi.encodePacked(address(this), address(this));
        }
        _checkPayloadSize(_dstChainId, _payload.length);
        lzEndpoint.send{value: _nativeFee}(
            _dstChainId,
            trustedRemote,
            _payload,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    function _checkGasLimit(
        uint16 _dstChainId,
        uint16 _type,
        bytes memory _adapterParams,
        uint _extraGas
    ) internal view virtual override {
        uint providedGasLimit = _getGasLimit(_adapterParams);
        uint minGasLimit = minDstGasLookup[_dstChainId][_type];
        if (minGasLimit == 0) minGasLimit = defaultGasLimit;
        require(providedGasLimit >= minGasLimit + _extraGas);
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public virtual override {
        // lzReceive must be called by the endpoint for security
        require(_msgSender() == address(lzEndpoint));

        bytes memory trustedRemote = trustedRemoteLookup[_srcChainId];
        if (trustedRemote.length == 0)
            trustedRemote = abi.encodePacked(address(this), address(this));
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from untrusted remote.
        require(
            _srcAddress.length == trustedRemote.length &&
                trustedRemote.length > 0 &&
                keccak256(_srcAddress) == keccak256(trustedRemote)
        );

        _blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }
}
