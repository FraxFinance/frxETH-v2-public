// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "frax-std/FraxTest.sol";
import "src/test/helpers/Helpers.sol";
import "src/Constants.sol" as Constants;
import { BeaconOracle } from "src/contracts/BeaconOracle.sol";
import { EtherRouter } from "src/contracts/ether-router/EtherRouter.sol";
import { LendingPool, LendingPoolParams } from "src/contracts/lending-pool/LendingPool.sol";
import { VariableInterestRate } from "src/contracts/lending-pool/VariableInterestRate.sol";
import { IDepositContract, DepositContract } from "src/contracts/interfaces/IDepositContract.sol";
import { ValidatorPool } from "src/contracts/ValidatorPool.sol";
import { FraxEtherMinter, FraxEtherMinterParams, IFrxEth } from "src/contracts/frax-ether-minter/FraxEtherMinter.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { VaultAccount } from "src/contracts/libraries/VaultAccountingLibrary.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

using SafeCast for uint256;

struct DepositCredentials {
    bytes publicKey;
    bytes withdrawalCredentials;
    bytes signature;
    bytes32 depositDataRoot;
    uint256 depositAmount;
}

function generateDepositCredentials(
    ValidatorPool _validatorPool,
    bytes memory _publicKey,
    bytes memory _signature,
    uint256 _depositAmount
) view returns (DepositCredentials memory _return) {
    // Set defaults
    _return.publicKey = _publicKey;
    _return.signature = _signature;
    _return.depositAmount = _depositAmount;
    _return.withdrawalCredentials = abi.encodePacked(_validatorPool.withdrawalCredentials());

    // Generate deposit data root
    _return.depositDataRoot = generateDepositDataRoot(
        _return.publicKey,
        _return.withdrawalCredentials,
        _return.signature,
        _return.depositAmount
    );
}

function deployValidatorPool(
    LendingPool lendingPool,
    address validatorPoolOwner
) returns (ValidatorPool _validatorPool, address payable _validatorPoolAddress) {
    _validatorPoolAddress = lendingPool.deployValidatorPool(validatorPoolOwner, bytes32(block.timestamp));
    _validatorPool = ValidatorPool(_validatorPoolAddress);
}

// ==============================================================================
// User Snapshot Functions
// ==============================================================================

struct AddressAccountingSnapshot {
    address selfAddress;
    uint256 etherBalance;
    uint256 frxEthBalance;
}

struct DeltaAddressAccountingSnapshot {
    AddressAccountingSnapshot start;
    AddressAccountingSnapshot end;
    AddressAccountingSnapshot delta;
}

function addressAccountingSnapshot(address _address) view returns (AddressAccountingSnapshot memory _initial) {
    if (_address == address(0)) {
        return _initial;
    }
    _initial.selfAddress = _address;
    _initial.etherBalance = _address.balance;
    _initial.frxEthBalance = IERC20(Constants.Mainnet.FRX_ETH_ERC20_ADDRESS).balanceOf(_address);
}

function calculateDeltaAddressAccounting(
    AddressAccountingSnapshot memory _initial,
    AddressAccountingSnapshot memory _final
) pure returns (AddressAccountingSnapshot memory _delta) {
    _delta.selfAddress = _initial.selfAddress == _final.selfAddress ? address(0) : _final.selfAddress;
    _delta.etherBalance = stdMath.delta(_final.etherBalance, _initial.etherBalance);
    _delta.frxEthBalance = stdMath.delta(_final.frxEthBalance, _initial.frxEthBalance);
}

function deltaAddressAccountingSnapshot(
    AddressAccountingSnapshot memory _initial
) view returns (DeltaAddressAccountingSnapshot memory _end) {
    _end.start = _initial;
    _end.end = addressAccountingSnapshot(_initial.selfAddress);
    _end.delta = calculateDeltaAddressAccounting(_end.start, _end.end);
}

// ==============================================================================
// ValidatorPool Accounting Snapshot Functions
// ==============================================================================

struct ValidatorPoolAccountingSnapshot {
    address payable validatorPoolAddress;
    address payable lendingPoolAddress;
    address payable ownerAddress;
    AddressAccountingSnapshot addressAccounting;
    LendingPool.ValidatorPoolAccount lendingPool_validatorPoolAccount;
}

struct DeltaValidatorPoolAccountingSnapshot {
    ValidatorPoolAccountingSnapshot start;
    ValidatorPoolAccountingSnapshot end;
    ValidatorPoolAccountingSnapshot delta;
}

function validatorPoolAccountingSnapshot(
    ValidatorPool _validatorPool
) view returns (ValidatorPoolAccountingSnapshot memory _initial) {
    if (address(_validatorPool) == address(0)) {
        return _initial;
    }
    _initial.validatorPoolAddress = payable(address(_validatorPool));
    _initial.lendingPoolAddress = payable(address(_validatorPool.lendingPool()));
    _initial.ownerAddress = payable(_validatorPool.owner());
    _initial.addressAccounting = addressAccountingSnapshot(_initial.validatorPoolAddress);
    _initial.lendingPool_validatorPoolAccount = LendingPoolStructHelper.__validatorPoolAccounts(
        LendingPool(_initial.lendingPoolAddress),
        address(_validatorPool)
    );
}

function validatorPoolAccountingSnapshot(
    address payable _validatorPoolAddress
) view returns (ValidatorPoolAccountingSnapshot memory _initial) {
    return validatorPoolAccountingSnapshot(ValidatorPool(_validatorPoolAddress));
}

function calculateValidatorPoolAccountingDelta(
    ValidatorPoolAccountingSnapshot memory _initial,
    ValidatorPoolAccountingSnapshot memory _final
) pure returns (ValidatorPoolAccountingSnapshot memory _delta) {
    _delta.validatorPoolAddress = _initial.validatorPoolAddress == _final.validatorPoolAddress
        ? payable(address(0))
        : _final.validatorPoolAddress;
    _delta.ownerAddress = _initial.ownerAddress == _final.ownerAddress ? payable(address(0)) : _final.ownerAddress;
    _delta.lendingPoolAddress = _initial.ownerAddress == _final.ownerAddress
        ? payable(address(0))
        : _final.ownerAddress;
    _delta.addressAccounting = calculateDeltaAddressAccounting(_initial.addressAccounting, _final.addressAccounting);

    //validatorPoolAccount struct delta accounting
    _delta.lendingPool_validatorPoolAccount.validatorCount = uint32(
        stdMath.delta(
            uint256(_final.lendingPool_validatorPoolAccount.validatorCount),
            uint256(_initial.lendingPool_validatorPoolAccount.validatorCount)
        )
    );
    _delta.lendingPool_validatorPoolAccount.creditPerValidatorI48_E12 = uint48(
        stdMath.delta(
            uint256(_final.lendingPool_validatorPoolAccount.creditPerValidatorI48_E12),
            uint256(_initial.lendingPool_validatorPoolAccount.creditPerValidatorI48_E12)
        )
    );
    _delta.lendingPool_validatorPoolAccount.borrowAllowance = uint128(
        stdMath.delta(
            uint256(_final.lendingPool_validatorPoolAccount.borrowAllowance),
            uint256(_initial.lendingPool_validatorPoolAccount.borrowAllowance)
        )
    );
    _delta.lendingPool_validatorPoolAccount.borrowShares = stdMath.delta(
        _final.lendingPool_validatorPoolAccount.borrowShares,
        _initial.lendingPool_validatorPoolAccount.borrowShares
    );
    _delta.lendingPool_validatorPoolAccount.lastWithdrawal = uint32(
        stdMath.delta(
            uint256(_final.lendingPool_validatorPoolAccount.lastWithdrawal),
            uint256(_initial.lendingPool_validatorPoolAccount.lastWithdrawal)
        )
    );
    _delta.lendingPool_validatorPoolAccount.wasLiquidated =
        _final.lendingPool_validatorPoolAccount.wasLiquidated !=
        _initial.lendingPool_validatorPoolAccount.wasLiquidated;
    _delta.lendingPool_validatorPoolAccount.isInitialized =
        _final.lendingPool_validatorPoolAccount.isInitialized !=
        _initial.lendingPool_validatorPoolAccount.isInitialized;
}

function deltaValidatorPoolAccountingSnapshot(
    ValidatorPoolAccountingSnapshot memory _initial
) view returns (DeltaValidatorPoolAccountingSnapshot memory _final) {
    _final.start = _initial;
    _final.end = validatorPoolAccountingSnapshot(_initial.validatorPoolAddress);
    _final.delta = calculateValidatorPoolAccountingDelta(_final.start, _final.end);
}

// ==============================================================================
// ValidatorDepositInfoSnapshot Functions
// ==============================================================================

struct ValidatorDepositInfoSnapshot {
    bytes publicKey;
    address payable lendingPoolAddress;
    LendingPool.ValidatorDepositInfo lendingPool_validatorDepositInfo;
}

struct DeltaValidatorDepositInfoSnapshot {
    ValidatorDepositInfoSnapshot start;
    ValidatorDepositInfoSnapshot end;
    ValidatorDepositInfoSnapshot delta;
}

function validatorDepositInfoSnapshot(
    bytes memory _validatorPublicKey,
    address payable _lendingPoolAddress
) view returns (ValidatorDepositInfoSnapshot memory _initial) {
    // length of bytes
    if (_validatorPublicKey.length == 0) {
        return _initial;
    }
    _initial.publicKey = _validatorPublicKey;
    _initial.lendingPoolAddress = _lendingPoolAddress;
    _initial.lendingPool_validatorDepositInfo = LendingPoolStructHelper.__validatorDepositInfo(
        LendingPool(_lendingPoolAddress),
        _validatorPublicKey
    );
}

function validatorDepositInfoSnapshot(
    bytes memory _validatorPublicKey,
    LendingPool _lendingPool
) view returns (ValidatorDepositInfoSnapshot memory _initial) {
    return validatorDepositInfoSnapshot(_validatorPublicKey, payable(address(_lendingPool)));
}

function calculateValidatorDepositInfoDelta(
    ValidatorDepositInfoSnapshot memory _initial,
    ValidatorDepositInfoSnapshot memory _final
) pure returns (ValidatorDepositInfoSnapshot memory _delta) {
    _delta.publicKey = _initial.publicKey;
    _delta.lendingPoolAddress = _initial.lendingPoolAddress == _final.lendingPoolAddress
        ? payable(address(0))
        : _final.lendingPoolAddress;

    // validatorDepositInfo struct
    _delta.lendingPool_validatorDepositInfo.whenValidatorApproved = uint32(
        stdMath.delta(
            uint256(_final.lendingPool_validatorDepositInfo.whenValidatorApproved),
            uint256(_initial.lendingPool_validatorDepositInfo.whenValidatorApproved)
        )
    );
    _delta.lendingPool_validatorDepositInfo.wasFullDepositOrFinalized =
        _final.lendingPool_validatorDepositInfo.wasFullDepositOrFinalized !=
        _initial.lendingPool_validatorDepositInfo.wasFullDepositOrFinalized;
    _delta.lendingPool_validatorDepositInfo.userDepositedEther = uint96(
        stdMath.delta(
            uint256(_final.lendingPool_validatorDepositInfo.userDepositedEther),
            uint256(_initial.lendingPool_validatorDepositInfo.userDepositedEther)
        )
    );
    _delta.lendingPool_validatorDepositInfo.lendingPoolDepositedEther = uint96(
        stdMath.delta(
            uint256(_final.lendingPool_validatorDepositInfo.lendingPoolDepositedEther),
            uint256(_initial.lendingPool_validatorDepositInfo.lendingPoolDepositedEther)
        )
    );
}

function deltaValidatorDepositInfoSnapshot(
    ValidatorDepositInfoSnapshot memory _initial
) view returns (DeltaValidatorDepositInfoSnapshot memory _final) {
    _final.start = _initial;
    _final.end = validatorDepositInfoSnapshot(_initial.publicKey, _initial.lendingPoolAddress);
    _final.delta = calculateValidatorDepositInfoDelta(_final.start, _final.end);
}

// ==============================================================================
// LendingPoolAccountingSnapshot Functions
// ==============================================================================

struct LendingPoolAccountingSnapshot {
    address payable lendingPoolAddress;
    uint256 interestAccrued;
    uint256 utilization;
    AddressAccountingSnapshot addressAccounting;
    VaultAccount totalBorrow;
    LendingPool.CurrentRateInfo currentRateInfo;
}

struct DeltaLendingPoolAccountingSnapshot {
    LendingPoolAccountingSnapshot start;
    LendingPoolAccountingSnapshot end;
    LendingPoolAccountingSnapshot delta;
}

function lendingPoolAccountingSnapshot(
    LendingPool _lendingPool
) view returns (LendingPoolAccountingSnapshot memory _initial) {
    if (address(_lendingPool) == address(0)) {
        return _initial;
    }
    _initial.lendingPoolAddress = payable(address(_lendingPool));
    _initial.interestAccrued = _lendingPool.interestAccrued();
    _initial.utilization = _lendingPool.getUtilizationView();
    _initial.addressAccounting = addressAccountingSnapshot(_initial.lendingPoolAddress);
    _initial.totalBorrow = LendingPoolStructHelper.__totalBorrow(_lendingPool);
    _initial.currentRateInfo = LendingPoolStructHelper.__currentRateInfo(_lendingPool);
}

function lendingPoolAccountingSnapshot(
    address payable _lendingPoolAddress
) view returns (LendingPoolAccountingSnapshot memory _initial) {
    return lendingPoolAccountingSnapshot(LendingPool(_lendingPoolAddress));
}

function getLendingPoolAccountingDelta(
    LendingPoolAccountingSnapshot memory _initial,
    LendingPoolAccountingSnapshot memory _final
) pure returns (LendingPoolAccountingSnapshot memory _delta) {
    _delta.lendingPoolAddress = _initial.lendingPoolAddress == _final.lendingPoolAddress
        ? payable(address(0))
        : _final.lendingPoolAddress;
    _delta.interestAccrued = stdMath.delta(_final.interestAccrued, _initial.interestAccrued);
    _delta.utilization = stdMath.delta(_final.utilization, _initial.utilization);

    _delta.addressAccounting = calculateDeltaAddressAccounting(_initial.addressAccounting, _final.addressAccounting);

    // total borrow struct delta accounting
    _delta.totalBorrow.amount = stdMath.delta(_final.totalBorrow.amount, _initial.totalBorrow.amount);
    _delta.totalBorrow.shares = stdMath.delta(_final.totalBorrow.shares, _initial.totalBorrow.shares);

    // current rate info struct delta accounting
    _delta.currentRateInfo.lastTimestamp = stdMath
        .delta(_final.currentRateInfo.lastTimestamp, _initial.currentRateInfo.lastTimestamp)
        .toUint64();
    _delta.currentRateInfo.ratePerSec = (
        stdMath.delta(uint256(_final.currentRateInfo.ratePerSec), uint256(_initial.currentRateInfo.ratePerSec))
    ).toUint64();
    _delta.currentRateInfo.fullUtilizationRate = _initial.currentRateInfo.fullUtilizationRate;
}

function deltaLendingPoolAccountingSnapshot(
    LendingPoolAccountingSnapshot memory _initial
) view returns (DeltaLendingPoolAccountingSnapshot memory _final) {
    _final.start = _initial;
    _final.end = lendingPoolAccountingSnapshot(_initial.lendingPoolAddress);
    _final.delta = getLendingPoolAccountingDelta(_final.start, _final.end);
}

// ==============================================================================
// System Snapshot Functions
// ==============================================================================

struct InitialSystemSnapshot {
    LendingPoolAccountingSnapshot lendingPool;
    ValidatorPoolAccountingSnapshot validatorPool;
    ValidatorDepositInfoSnapshot validator;
    AddressAccountingSnapshot user;
}

struct DeltaSystemSnapshot {
    InitialSystemSnapshot start;
    InitialSystemSnapshot end;
    InitialSystemSnapshot delta;
}

function initialSystemSnapshot(
    address _user,
    bytes memory _validatorPublicKey,
    LendingPool _lendingPool,
    ValidatorPool _validatorPool
) view returns (InitialSystemSnapshot memory _initial) {
    _initial.lendingPool = lendingPoolAccountingSnapshot(_lendingPool);
    _initial.validatorPool = validatorPoolAccountingSnapshot(_validatorPool);
    _initial.validator = validatorDepositInfoSnapshot(_validatorPublicKey, _lendingPool);
    _initial.user = addressAccountingSnapshot(_user);
}

function getDeltaSystemSnapshot(
    InitialSystemSnapshot memory _initial,
    InitialSystemSnapshot memory _final
) pure returns (InitialSystemSnapshot memory _delta) {
    _delta.lendingPool = getLendingPoolAccountingDelta(_initial.lendingPool, _final.lendingPool);
    _delta.validatorPool = calculateValidatorPoolAccountingDelta(_initial.validatorPool, _final.validatorPool);
    _delta.validator = calculateValidatorDepositInfoDelta(_initial.validator, _final.validator);
    _delta.user = calculateDeltaAddressAccounting(_initial.user, _final.user);
}

function deltaSystemSnapshot(InitialSystemSnapshot memory _initial) view returns (DeltaSystemSnapshot memory _final) {
    _final.start = _initial;
    _final.end = initialSystemSnapshot(
        _initial.user.selfAddress,
        _initial.validator.publicKey,
        LendingPool(_initial.lendingPool.lendingPoolAddress),
        ValidatorPool(_initial.validatorPool.validatorPoolAddress)
    );
    _final.delta = getDeltaSystemSnapshot(_final.start, _final.end);
}

library logSnapshot {
    function log(LendingPoolAccountingSnapshot memory _snapshot, string memory _prefix) internal pure {
        console.log(string.concat(_prefix, "lendingPoolAddress"), _snapshot.lendingPoolAddress);
        console.log(string.concat(_prefix, "totalBorrow.amount"), _snapshot.totalBorrow.amount);
        console.log(string.concat(_prefix, "totalBorrow.shares"), _snapshot.totalBorrow.shares);
        console.log(string.concat(_prefix, "interestAccrued"), _snapshot.interestAccrued);
        console.log(string.concat(_prefix, "currentRateInfo.lastTimestamp"), _snapshot.currentRateInfo.lastTimestamp);
        console.log(string.concat(_prefix, "currentRateInfo.ratePerSec"), _snapshot.currentRateInfo.ratePerSec);
        console.log(
            string.concat(_prefix, "currentRateInfo.fullUtilizationRate"),
            _snapshot.currentRateInfo.fullUtilizationRate
        );
    }

    function log(InitialSystemSnapshot memory _snapshot, string memory _prefix) internal pure {
        log(_snapshot.lendingPool, "_snapshot.lendingPool.");

        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.validatorPoolAddress"),
            _snapshot.validatorPool.validatorPoolAddress
        );
        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.lendingPoolAddress"),
            _snapshot.validatorPool.lendingPoolAddress
        );
        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.ownerAddress"),
            _snapshot.validatorPool.ownerAddress
        );
        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.etherBalance"),
            _snapshot.validatorPool.addressAccounting.etherBalance
        );
        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.validatorCount"),
            _snapshot.validatorPool.lendingPool_validatorPoolAccount.validatorCount
        );
        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.creditPerValidatorI48_E12"),
            _snapshot.validatorPool.lendingPool_validatorPoolAccount.creditPerValidatorI48_E12
        );
        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.borrowAllowance"),
            _snapshot.validatorPool.lendingPool_validatorPoolAccount.borrowAllowance
        );
        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.borrowShares"),
            _snapshot.validatorPool.lendingPool_validatorPoolAccount.borrowShares
        );
        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.lastWithdrawal"),
            _snapshot.validatorPool.lendingPool_validatorPoolAccount.lastWithdrawal
        );
        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.wasLiquidated"),
            _snapshot.validatorPool.lendingPool_validatorPoolAccount.wasLiquidated
        );
        console.log(
            string.concat(_prefix, "_snapshot.validatorPool.isInitialized"),
            _snapshot.validatorPool.lendingPool_validatorPoolAccount.isInitialized
        );

        console.log(string.concat(_prefix, "_snapshot.validator.publicKey"));
        console.logBytes(_snapshot.validator.publicKey);
        console.log(
            string.concat(_prefix, "_snapshot.validator.lendingPoolAddress"),
            _snapshot.validator.lendingPoolAddress
        );
        console.log(
            string.concat(_prefix, "_snapshot.validator.lendingPool_validatorDepositInfo.whenValidatorApproved"),
            _snapshot.validator.lendingPool_validatorDepositInfo.whenValidatorApproved
        );
        console.log(
            string.concat(_prefix, "_snapshot.validator.lendingPool_validatorDepositInfo.wasFullDepositOrFinalized"),
            _snapshot.validator.lendingPool_validatorDepositInfo.wasFullDepositOrFinalized
        );
        console.log(
            string.concat(_prefix, "_snapshot.validator.lendingPool_validatorDepositInfo.userDepositedEther"),
            _snapshot.validator.lendingPool_validatorDepositInfo.userDepositedEther
        );
        console.log(
            string.concat(_prefix, "_snapshot.validator.lendingPool_validatorDepositInfo.lendingPoolDepositedEther"),
            _snapshot.validator.lendingPool_validatorDepositInfo.lendingPoolDepositedEther
        );

        console.log(string.concat(_prefix, "_snapshot.user.userAddress"), _snapshot.user.selfAddress);
        console.log(string.concat(_prefix, "_snapshot.user.etherBalance"), _snapshot.user.etherBalance);
        console.log(string.concat(_prefix, "_snapshot.user.frxEthBalance"), _snapshot.user.frxEthBalance);
    }

    function log(DeltaSystemSnapshot memory _snapshot, string memory _prefix) internal pure {
        log(_snapshot.start, string.concat(_prefix, "start: "));
        log(_snapshot.end, string.concat(_prefix, "end: "));
        log(_snapshot.delta, string.concat(_prefix, "delta: "));
    }
}
