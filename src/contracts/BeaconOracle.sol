// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// =========================== BeaconOracle ===========================
// ====================================================================
// Tracks frxETHV2 ValidatorPools. Controlled by Frax governance / bots

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Drake Evans: https://github.com/DrakeEvans
// Travis Moore: https://github.com/FortisFortuna

// Reviewer(s) / Contributor(s)
// Dennis: https://github.com/denett
// Sam Kazemian: https://github.com/samkazemian

import { Timelock2Step } from "frax-std/access-control/v2/Timelock2Step.sol";
import { ValidatorPool } from "./ValidatorPool.sol";
import { LendingPool } from "./lending-pool/LendingPool.sol";
import { LendingPoolRole } from "./access-control/LendingPoolRole.sol";
import { OperatorRole } from "frax-std/access-control/v2/OperatorRole.sol";

/// @title Tracks frxETHV2 ValidatorPools
/// @author Frax Finance
/// @notice Controlled by Frax governance / bots
contract BeaconOracle is LendingPoolRole, OperatorRole, Timelock2Step {
    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    /// @notice Constructor for the beacon oracle
    /// @param _timelockAddress The timelock address
    /// @param _operatorAddress The operator address
    constructor(
        address _timelockAddress,
        address _operatorAddress
    ) LendingPoolRole(payable(address(0))) OperatorRole(_operatorAddress) Timelock2Step(_timelockAddress) {}

    // ==============================================================================
    // Operator (and Timelock) Check Functions
    // ==============================================================================

    /// @notice Checks if msg.sender is the timelock address or the operator
    function _requireIsTimelockOrOperator() internal view {
        if (!((msg.sender == timelockAddress) || (msg.sender == operatorAddress))) revert NotTimelockOrOperator();
    }

    // ==============================================================================
    // Beacon Functions
    // ==============================================================================

    /// @notice Set the approval status for a single validator's pubkey
    /// @param _validatorPublicKey The pubkey being set
    /// @param _validatorPoolAddress The validator pool associated with the pubkey
    /// @param _whenApproved When the pubkey was approved. 0 if it is not
    /// @param _lastWithdrawalTimestamp Should be the timestamp of when the user last withdrew. Function will revert if user withdraws after this function is enqueued.
    function setValidatorApproval(
        bytes calldata _validatorPublicKey,
        address _validatorPoolAddress,
        uint32 _whenApproved,
        uint32 _lastWithdrawalTimestamp
    ) external {
        _requireIsTimelockOrOperator();

        // Set arrays
        bytes[] memory tmpArr0 = new bytes[](1);
        tmpArr0[0] = _validatorPublicKey;
        address[] memory tmpArr1 = new address[](1);
        tmpArr1[0] = _validatorPoolAddress;
        uint32[] memory tmpArr2 = new uint32[](1);
        tmpArr2[0] = _whenApproved;
        uint32[] memory lwTimestampTmpArr = new uint32[](1);
        lwTimestampTmpArr[0] = _lastWithdrawalTimestamp;

        // Set the approvals
        lendingPool.setValidatorApprovals(tmpArr0, tmpArr1, tmpArr2, lwTimestampTmpArr);
    }

    /// @notice Set the approval status for a multiple validator pubkeys
    /// @param _validatorPublicKeys The pubkeys being set
    /// @param _validatorPoolAddresses The validator pools associated with the pubkeys
    /// @param _whenApprovedArr When the validators were approved. 0 if they were not
    /// @param _lastWithdrawalTimestamps Should be the timestamps of when the user last withdrew. Function will revert if user withdraws after this function is enqueued.
    function setValidatorApprovals(
        bytes[] calldata _validatorPublicKeys,
        address[] calldata _validatorPoolAddresses,
        uint32[] calldata _whenApprovedArr,
        uint32[] calldata _lastWithdrawalTimestamps
    ) external {
        _requireIsTimelockOrOperator();

        // Set the approvals
        lendingPool.setValidatorApprovals(
            _validatorPublicKeys,
            _validatorPoolAddresses,
            _whenApprovedArr,
            _lastWithdrawalTimestamps
        );
    }

    /// @notice Set the borrow allowance for a single validator pool
    /// @param _validatorPoolAddress The validator pool being set
    /// @param _newBorrowAllowance The new borrow allowance
    /// @param _lastWithdrawalTimestamp Should be the timestamp of when the user last withdrew. Function will revert if user withdraws after this function is enqueued.
    function setVPoolBorrowAllowance(
        address _validatorPoolAddress,
        uint128 _newBorrowAllowance,
        uint32 _lastWithdrawalTimestamp
    ) external {
        _requireIsTimelockOrOperator();

        // Set arrays
        address[] memory vpAddrTmpArr = new address[](1);
        vpAddrTmpArr[0] = _validatorPoolAddress;
        uint128[] memory nbaTmpArr = new uint128[](1);
        nbaTmpArr[0] = _newBorrowAllowance;
        uint32[] memory emptyArr = new uint32[](0);
        uint32[] memory lwTimestampTmpArr = new uint32[](1);
        lwTimestampTmpArr[0] = _lastWithdrawalTimestamp;

        // Set the borrow allowance only, for a single validator pool
        lendingPool.setVPoolValidatorCountsAndBorrowAllowances(
            vpAddrTmpArr,
            false,
            true,
            emptyArr,
            nbaTmpArr,
            lwTimestampTmpArr
        );
    }

    /// @notice Set the borrow allowances for a multiple validator pools
    /// @param _validatorPoolAddresses The validator pools being set
    /// @param _newBorrowAllowances The new borrow allowances
    /// @param _lastWithdrawalTimestamps Should be the timestamps of when the user last withdrew. Function will revert if user withdraws after this function is enqueued.
    function setVPoolBorrowAllowances(
        address[] calldata _validatorPoolAddresses,
        uint128[] calldata _newBorrowAllowances,
        uint32[] calldata _lastWithdrawalTimestamps
    ) external {
        _requireIsTimelockOrOperator();
        uint32[] memory emptyArr = new uint32[](0);

        // Set the borrow allowances only, for a multiple validator pools
        lendingPool.setVPoolValidatorCountsAndBorrowAllowances(
            _validatorPoolAddresses,
            false,
            true,
            emptyArr,
            _newBorrowAllowances,
            _lastWithdrawalTimestamps
        );
    }

    /// @notice Set the credits per validator for a single validator pool
    /// @param _validatorPoolAddress The validator pool being set
    /// @param _newCreditPerValidatorI48_E12 The ETH credit per validator this pool should be given
    function setVPoolCreditPerValidatorI48_E12(
        address _validatorPoolAddress,
        uint48 _newCreditPerValidatorI48_E12
    ) external {
        _requireIsTimelockOrOperator();

        // Set arrays
        address[] memory vpAddrTmpArr = new address[](1);
        vpAddrTmpArr[0] = _validatorPoolAddress;
        uint48[] memory ncpvTmpArr = new uint48[](1);
        ncpvTmpArr[0] = _newCreditPerValidatorI48_E12;

        lendingPool.setVPoolCreditsPerValidator(vpAddrTmpArr, ncpvTmpArr);
    }

    /// @notice Set the credits per validator for a multiple validator pools
    /// @param _validatorPoolAddresses The validator pools being set
    /// @param _newCreditsPerValidator The ETH credits per validator each pool should be given
    function setVPoolCreditsPerValidator(
        address[] calldata _validatorPoolAddresses,
        uint48[] calldata _newCreditsPerValidator
    ) external {
        _requireIsTimelockOrOperator();
        lendingPool.setVPoolCreditsPerValidator(_validatorPoolAddresses, _newCreditsPerValidator);
    }

    /// @notice Set the number of validators for a single validator pool
    /// @param _validatorPoolAddress The validator pool being set
    /// @param _newValidatorCount The new total number of validators for the pool
    /// @param _lastWithdrawalTimestamp Should be the timestamp of when the user last withdrew. Function will revert if user withdraws after this function is enqueued.
    function setVPoolValidatorCount(
        address _validatorPoolAddress,
        uint32 _newValidatorCount,
        uint32 _lastWithdrawalTimestamp
    ) external {
        _requireIsTimelockOrOperator();

        // Set arrays
        address[] memory vpAddrTmpArr = new address[](1);
        vpAddrTmpArr[0] = _validatorPoolAddress;
        uint32[] memory nvcTmpArr = new uint32[](1);
        nvcTmpArr[0] = _newValidatorCount;
        uint128[] memory emptyArr = new uint128[](0);
        uint32[] memory lwTimestampTmpArr = new uint32[](1);
        lwTimestampTmpArr[0] = _lastWithdrawalTimestamp;

        // Set the count only, for a single validator pool
        lendingPool.setVPoolValidatorCountsAndBorrowAllowances(
            vpAddrTmpArr,
            true,
            false,
            nvcTmpArr,
            emptyArr,
            lwTimestampTmpArr
        );
    }

    /// @notice Set the number of validators for multiple validator pools
    /// @param _validatorPoolAddresses The validator pools being set
    /// @param _newValidatorCounts The new total number of validators for the pools
    /// @param _lastWithdrawalTimestamps Should be the timestamps of when the user last withdrew. Function will revert if user withdraws after this function is enqueued.
    function setVPoolValidatorCounts(
        address[] calldata _validatorPoolAddresses,
        uint32[] calldata _newValidatorCounts,
        uint32[] calldata _lastWithdrawalTimestamps
    ) external {
        _requireIsTimelockOrOperator();
        uint128[] memory emptyArr = new uint128[](0);

        // Set the counts only, for multiple validator pools
        lendingPool.setVPoolValidatorCountsAndBorrowAllowances(
            _validatorPoolAddresses,
            true,
            false,
            _newValidatorCounts,
            emptyArr,
            _lastWithdrawalTimestamps
        );
    }

    /// @notice Set the number of validators and the borrow allowance for a single validator pools
    /// @param _validatorPoolAddress The validator pool being set
    /// @param _newValidatorCount The new total number of validators for the pool
    /// @param _newBorrowAllowance The new borrow allowance
    /// @param _lastWithdrawalTimestamp Should be the timestamp of when the user last withdrew. Function will revert if user withdraws after this function is enqueued.
    function setVPoolValidatorCountAndBorrowAllowance(
        address _validatorPoolAddress,
        uint32 _newValidatorCount,
        uint128 _newBorrowAllowance,
        uint32 _lastWithdrawalTimestamp
    ) external {
        _requireIsTimelockOrOperator();

        // Set arrays
        address[] memory vpAddrTmpArr = new address[](1);
        vpAddrTmpArr[0] = _validatorPoolAddress;
        uint32[] memory nvcTmpArr = new uint32[](1);
        nvcTmpArr[0] = _newValidatorCount;
        uint128[] memory nbaTmpArr = new uint128[](1);
        nbaTmpArr[0] = _newBorrowAllowance;
        uint32[] memory lwTimestampTmpArr = new uint32[](1);
        lwTimestampTmpArr[0] = _lastWithdrawalTimestamp;

        // Set both the count and borrow allowance for a single validator pool
        lendingPool.setVPoolValidatorCountsAndBorrowAllowances(
            vpAddrTmpArr,
            true,
            true,
            nvcTmpArr,
            nbaTmpArr,
            lwTimestampTmpArr
        );
    }

    /// @notice Set the number of validators, as well as their allowances, for multiple validator pools
    /// @param _validatorPoolAddresses The validator pools being set
    /// @param _newValidatorCounts The new total number of validators for the pools
    /// @param _newBorrowAllowances The new borrow allowances
    /// @param _lastWithdrawalTimestamps Should be the timestamps of when the user last withdrew. Function will revert if user withdraws after this function is enqueued.
    function setVPoolValidatorCountsAndBorrowAllowances(
        address[] calldata _validatorPoolAddresses,
        uint32[] calldata _newValidatorCounts,
        uint128[] calldata _newBorrowAllowances,
        uint32[] calldata _lastWithdrawalTimestamps
    ) external {
        _requireIsTimelockOrOperator();

        // Set both the counts and borrow allowances for multiple validator pools
        lendingPool.setVPoolValidatorCountsAndBorrowAllowances(
            _validatorPoolAddresses,
            true,
            true,
            _newValidatorCounts,
            _newBorrowAllowances,
            _lastWithdrawalTimestamps
        );
    }

    // ==============================================================================
    // Restricted Functions
    // ==============================================================================

    /// @notice Set the lending pool address
    /// @param _newLendingPoolAddress The new address of the lending pool
    function setLendingPool(address payable _newLendingPoolAddress) external {
        _requireSenderIsTimelock();
        _setLendingPool(_newLendingPoolAddress);
    }

    /// @notice Change the Operator address
    /// @param _newOperatorAddress Operator address
    function setOperatorAddress(address _newOperatorAddress) external {
        _requireSenderIsTimelock();
        _setOperator(_newOperatorAddress);
    }

    // ====================================
    // Errors
    // ====================================

    /// @notice Thrown if the sender is not the timelock or the operator
    error NotTimelockOrOperator();
}
