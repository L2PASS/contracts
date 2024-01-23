// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SimpleLzApp} from "./SimpleLzApp.sol";

contract GasStation is SimpleLzApp {
    struct SendInfo {
        uint16 dstChainId;
        uint256 nativeAmount;
    }

    constructor(address _lzEndpoint) SimpleLzApp(_lzEndpoint) {}

    uint256 _commonStationFee;
    mapping(uint16 => uint256) _stationFee;

    function useGasStation(
        SendInfo[] calldata sendInfos,
        address to
    ) external payable {
        uint256 fee;
        for (uint256 i = 0; i < sendInfos.length; i++) {
            fee += _sendNative(sendInfos[i], to);
        }
        require(msg.value >= fee, "Fee Not Met");
    }

    function estimateFees(
        uint16 _dstChainId,
        bytes memory _adapterParams
    ) public view returns (uint256 nativeFee) {
        (nativeFee, ) = lzEndpoint.estimateFees(
            _dstChainId,
            address(this),
            "",
            false,
            _adapterParams
        );
        nativeFee += _stationFee[_dstChainId] + _commonStationFee;
    }

    function _sendNative(
        SendInfo memory sendInfo,
        address _to
    ) internal returns (uint256 fee) {
        bytes memory adapterParams = createAdapterParams(
            sendInfo.dstChainId,
            sendInfo.nativeAmount,
            _to
        );

        fee = estimateFees(sendInfo.dstChainId, adapterParams);
        _lzSend(sendInfo.dstChainId, "", payable(this), adapterParams, fee);
    }

    function createAdapterParams(
        uint16 dstChainId,
        uint256 nativeAmount,
        address to
    ) public view returns (bytes memory) {
        return
            abi.encodePacked(
                uint16(2),
                getGasLimit(dstChainId),
                nativeAmount,
                to
            );
    }

    function withdraw(address token, uint256 amount) external onlyOwner {
        bool s;
        if (token == address(0)) {
            (s, ) = msg.sender.call{value: amount}("");
        } else {
            (s, ) = token.call(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    msg.sender,
                    amount
                )
            );
        }
        require(s, "Withdraw Failed");
    }

    function setStationFee(
        uint256 commonFee,
        uint16[] calldata chainIds,
        uint256[] calldata fees
    ) external onlyOwner {
        _commonStationFee = commonFee;
        for (uint256 i = 0; i < chainIds.length; i++) {
            _stationFee[chainIds[i]] = fees[i];
        }
    }

    receive() external payable {}
}
