// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import { BytesHelper } from "frax-std/BytesHelper.sol";

function to_little_endian_64(uint64 value) pure returns (bytes memory ret) {
    ret = new bytes(8);
    bytes8 bytesValue = bytes8(value);
    // Byteswapping during copying to bytes.
    ret[0] = bytesValue[7];
    ret[1] = bytesValue[6];
    ret[2] = bytesValue[5];
    ret[3] = bytesValue[4];
    ret[4] = bytesValue[3];
    ret[5] = bytesValue[2];
    ret[6] = bytesValue[1];
    ret[7] = bytesValue[0];
}

function generateDepositDataRoot(
    bytes memory pubkey,
    bytes memory _withdrawalCredentials,
    bytes memory _signature,
    uint256 _amount
) pure returns (bytes32 depositDataRoot) {
    // Emit `DepositEvent` log
    bytes memory _bAmount = to_little_endian_64(uint64(_amount / 1 gwei));

    // Compute deposit data root (`DepositData` hash tree root)
    bytes32 _pubkeyRoot = sha256(abi.encodePacked(pubkey, bytes16(0)));
    bytes32 _signatureRoot = sha256(
        abi.encodePacked(
            sha256(abi.encodePacked(BytesHelper.slice(_signature, 0, 64))),
            sha256(abi.encodePacked(BytesHelper.slice(_signature, 64, _signature.length), bytes32(0)))
        )
    );

    // Set return values
    depositDataRoot = sha256(
        abi.encodePacked(
            sha256(abi.encodePacked(_pubkeyRoot, _withdrawalCredentials)),
            sha256(abi.encodePacked(_bAmount, bytes24(0), _signatureRoot))
        )
    );
}

function generateDepositDataRoot(
    bytes memory pubkey,
    bytes32 _withdrawalCredentials,
    bytes memory _signature,
    uint256 _amount
) pure returns (bytes32 depositDataRoot) {
    return generateDepositDataRoot(pubkey, abi.encodePacked(_withdrawalCredentials), _signature, _amount);
}
