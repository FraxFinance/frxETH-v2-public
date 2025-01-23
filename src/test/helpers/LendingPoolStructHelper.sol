// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "src/contracts/lending-pool/LendingPool.sol";
import "src/contracts/libraries/VaultAccountingLibrary.sol";
import "src/contracts/lending-pool/interfaces/ILendingPool.sol";

library LendingPoolStructHelper {
    struct AddInterestReturn {
        uint256 interestEarned;
        uint256 feesAmount;
        uint256 feesShare;
        LendingPoolCore.CurrentRateInfo currentRateInfo;
        VaultAccount totalBorrow;
    }

    function __addInterest(
        LendingPool _lendingPool,
        bool _returnAccounting
    ) internal returns (AddInterestReturn memory _return) {
        (
            _return.interestEarned,
            _return.feesAmount,
            _return.feesShare,
            _return.currentRateInfo,
            _return.totalBorrow
        ) = _lendingPool.addInterest(_returnAccounting);
    }

    function __addInterest(
        ILendingPool _lendingPool,
        bool _returnAccounting
    ) internal returns (AddInterestReturn memory _return) {
        LendingPool _lendingPool = LendingPool(payable(address(_lendingPool)));
        return __addInterest(_lendingPool, _returnAccounting);
    }

    struct CurrentRateInfoReturn {
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint64 fullUtilizationRate;
    }

    function __currentRateInfo(
        LendingPool _lendingPool
    ) internal view returns (LendingPool.CurrentRateInfo memory _return) {
        (_return.lastTimestamp, _return.ratePerSec, _return.fullUtilizationRate) = _lendingPool.currentRateInfo();
    }

    function __currentRateInfo(
        ILendingPool _lendingPool
    ) internal view returns (LendingPool.CurrentRateInfo memory _return) {
        LendingPool _lendingPool = LendingPool(payable(address(_lendingPool)));
        return __currentRateInfo(_lendingPool);
    }

    struct PreviewAddInterestReturn {
        uint256 interestEarned;
        uint256 feesAmount;
        uint256 feesShare;
        LendingPoolCore.CurrentRateInfo newCurrentRateInfo;
        VaultAccount totalBorrow;
    }

    function __previewAddInterest(
        LendingPool _lendingPool
    ) internal view returns (PreviewAddInterestReturn memory _return) {
        (
            _return.interestEarned,
            _return.feesAmount,
            _return.feesShare,
            _return.newCurrentRateInfo,
            _return.totalBorrow
        ) = _lendingPool.previewAddInterest();
    }

    function __previewAddInterest(
        ILendingPool _lendingPool
    ) internal view returns (PreviewAddInterestReturn memory _return) {
        LendingPool _lendingPool = LendingPool(payable(address(_lendingPool)));
        return __previewAddInterest(_lendingPool);
    }

    struct TotalBorrowReturn {
        uint256 amount;
        uint256 shares;
    }

    function __totalBorrow(LendingPool _lendingPool) internal view returns (VaultAccount memory _return) {
        (_return.amount, _return.shares) = _lendingPool.totalBorrow();
    }

    function __totalBorrow(ILendingPool _lendingPool) internal view returns (VaultAccount memory _return) {
        LendingPool _lendingPool = LendingPool(payable(address(_lendingPool)));
        return __totalBorrow(_lendingPool);
    }

    struct ValidatorDepositInfoReturn {
        uint32 whenValidatorApproved;
        uint96 userDepositedEther;
        uint96 lendingPoolDepositedEther;
    }

    function __validatorDepositInfo(
        LendingPool _lendingPool,
        bytes memory _validatorPublicKey
    ) internal view returns (LendingPool.ValidatorDepositInfo memory _return) {
        (
            _return.whenValidatorApproved,
            _return.wasFullDepositOrFinalized,
            _return.validatorPoolAddress,
            _return.userDepositedEther,
            _return.lendingPoolDepositedEther
        ) = _lendingPool.validatorDepositInfo(_validatorPublicKey);
    }

    function __validatorDepositInfo(
        ILendingPool _lendingPool,
        bytes memory _validatorPublicKey
    ) internal view returns (LendingPool.ValidatorDepositInfo memory _return) {
        LendingPool _lendingPool = LendingPool(payable(address(_lendingPool)));
        return __validatorDepositInfo(_lendingPool, _validatorPublicKey);
    }

    struct ValidatorPoolAccountsReturn {
        bool isInitialized;
        bool wasLiquidated;
        uint64 lastWithdrawal;
        uint64 validatorCount;
        uint48 creditPerValidatorI48_E12;
        uint128 borrowAllowance;
        uint256 borrowShares;
    }

    function __validatorPoolAccounts(
        LendingPool _lendingPool,
        address _validatorPool
    ) internal view returns (LendingPool.ValidatorPoolAccount memory _return) {
        (
            _return.isInitialized,
            _return.wasLiquidated,
            _return.lastWithdrawal,
            _return.validatorCount,
            _return.creditPerValidatorI48_E12,
            _return.borrowAllowance,
            _return.borrowShares
        ) = _lendingPool.validatorPoolAccounts(_validatorPool);
    }

    function __validatorPoolAccounts(
        ILendingPool _lendingPool,
        address _validatorPool
    ) internal view returns (LendingPool.ValidatorPoolAccount memory _return) {
        LendingPool _lendingPool = LendingPool(payable(address(_lendingPool)));
        return __validatorPoolAccounts(_lendingPool, _validatorPool);
    }
}
