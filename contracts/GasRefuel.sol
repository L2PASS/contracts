// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {ILayerZeroEndpoint} from "@layerzerolabs/solidity-examples/contracts/lzApp/interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "@layerzerolabs/solidity-examples/contracts/lzApp/interfaces/ILayerZeroReceiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract GasRefuel is Ownable, ILayerZeroReceiver {
    uint256 public gasRefuelPrice;

    address immutable lzEndpoint;
    uint256 lzReceiveGas = 25000;

    mapping(uint16 => bytes) destinations;

    constructor(address lzEndpoint_, uint256 gasRefuelPrice_) {
        lzEndpoint = lzEndpoint_;
        gasRefuelPrice = gasRefuelPrice_;
    }

    receive() external payable {}

    function gasRefuel(
        uint16 dstChainId,
        address zroPaymentAddress,
        uint256 nativeForDst,
        address addressOnDst
    ) external payable {
        ILayerZeroEndpoint(lzEndpoint).send{value: msg.value - gasRefuelPrice}(
            dstChainId,
            _destination(dstChainId),
            bytes(""),
            payable(address(this)),
            zroPaymentAddress,
            _adapterParams(nativeForDst, addressOnDst)
        );
    }

    function lzReceive(
        uint16,
        bytes calldata,
        uint64,
        bytes calldata
    ) external {}

    function setGasRefuelPrice(uint256 gasRefuelPrice_) external onlyOwner {
        gasRefuelPrice = gasRefuelPrice_;
    }

    function claimFunds() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}(
            ""
        );
        require(success);
    }

    function estimateGasRefuelFee(
        uint16 dstChainId,
        uint256 nativeForDst,
        address addressOnDst,
        bool useZro
    ) external view returns (uint nativeFee, uint zroFee) {
        return
            ILayerZeroEndpoint(lzEndpoint).estimateFees(
                dstChainId,
                address(this),
                "",
                useZro,
                _adapterParams(nativeForDst, addressOnDst)
            );
    }

    function _adapterParams(
        uint256 nativeForDst,
        address addressOnDst
    ) internal view returns (bytes memory) {
        return
            abi.encodePacked(
                uint16(2),
                lzReceiveGas,
                nativeForDst,
                addressOnDst
            );
    }

    function _destination(
        uint16 dstChainId
    ) internal view returns (bytes memory) {
        bytes memory destination = destinations[dstChainId];
        if (destination.length > 0) return destination;
        return abi.encodePacked(address(this), address(this));
    }
}
