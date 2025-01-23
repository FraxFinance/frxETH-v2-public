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
// =========================== LendingPool ============================
// ====================================================================
// Receives and gives out ETH to ValidatorPools for lending and borrowing

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna
// Drake Evans: https://github.com/DrakeEvans

// Reviewer(s) / Contributor(s)
// Dennis: https://github.com/denett
// Sam Kazemian: https://github.com/samkazemian

import { ValidatorPool } from "../ValidatorPool.sol";
import { LendingPoolCore, LendingPoolCoreParams } from "./LendingPoolCore.sol";
import { SSTORE2 } from "solmate/src/utils/SSTORE2.sol";

// import "frax-std/FraxTest.sol";

/// @notice Constructor information for the lending pool
/// @param frxEthAddress Address of the frxETH token
/// @param timelockAddress The address of the governance timelock
/// @param etherRouterAddress The Ether Router address
/// @param beaconOracleAddress The Beacon Oracle address
/// @param redemptionQueueAddress The Redemption Queue address
/// @param interestRateCalculatorAddress Address used for interest rate calculations
/// @param eth2DepositAddress Address of the Eth2 deposit contract
/// @param fullUtilizationRate The interest rate at full utilization
// / @param validatorPoolCreationCode Bytecode for the validator pool (for create2)
struct LendingPoolParams {
    address frxEthAddress;
    address timelockAddress;
    address payable etherRouterAddress;
    address beaconOracleAddress;
    address payable redemptionQueueAddress;
    address interestRateCalculatorAddress;
    address payable eth2DepositAddress;
    uint64 fullUtilizationRate;
}
// bytes validatorPoolCreationCode;

/// @title Receives and gives out ETH to ValidatorPools for lending and borrowing
/// @author Frax Finance
/// @notice Controlled by Frax governance and validator pools
contract LendingPool is LendingPoolCore {
    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    /// @notice Where the bytecode for the validator pool factory to look at is
    address public validatorPoolCreationCodeAddress;

    // The default credit given to a validator pool, per validator (i.e. per 32 Eth)
    // 12 decimal precision, up to about ~281 Eth
    uint48 public constant DEFAULT_CREDIT_PER_VALIDATOR_I48_E12 = 24e12;

    // The maximum credit given to a validator pool, per validator (i.e. per 32 Eth)
    // 12 decimal precision, up to about ~281 Eth
    uint48 public constant MAXIMUM_CREDIT_PER_VALIDATOR_I48_E12 = 31e12;

    // Fee taken when a validator pool withdraws funds
    uint256 public vPoolWithdrawalFee; // 1e6 precision. Used to help cover slippage, LP fees, and beacon gas
    uint256 public constant MAX_WITHDRAWAL_FEE = 3000; // 0.3%

    /// @notice Constructor
    /// @param _params The LendingPoolParams
    constructor(
        LendingPoolParams memory _params
    )
        LendingPoolCore(
            LendingPoolCoreParams({
                frxEthAddress: _params.frxEthAddress,
                timelockAddress: _params.timelockAddress,
                etherRouterAddress: _params.etherRouterAddress,
                beaconOracleAddress: _params.beaconOracleAddress,
                redemptionQueueAddress: _params.redemptionQueueAddress,
                interestRateCalculatorAddress: _params.interestRateCalculatorAddress,
                eth2DepositAddress: _params.eth2DepositAddress,
                fullUtilizationRate: _params.fullUtilizationRate
            })
        )
    {
        // _setCreationCode(_params.validatorPoolCreationCode);
        _setCreationCode(type(ValidatorPool).creationCode);
    }

    // ==============================================================================
    // Global Configuration Setters
    // ==============================================================================

    // ------------------------------------------------------------------------
    /// @notice When someone tries setting the withdrawal fee above the max (100%)
    /// @param providedFee The provided withdrawal fee
    /// @param maxFee The maximum withdrawal fee
    error ExceedsMaxWithdrawalFee(uint256 providedFee, uint256 maxFee);

    /// @notice When the withdrawal fee for validator pools is set
    /// @param _newFee The new withdrawal fee
    event VPoolWithdrawalFeeSet(uint256 _newFee);

    /// @notice Sets the fee for when a validator pool withdraws
    /// @param _newFee New withdrawal fee given in percentage terms, using 1e6 precision
    /// @dev Mainly used to prevent griefing and handle the Curve LP fees.
    function setVPoolWithdrawalFee(uint256 _newFee) external {
        _requireSenderIsTimelock();
        if (_newFee > MAX_WITHDRAWAL_FEE) revert ExceedsMaxWithdrawalFee(_newFee, MAX_WITHDRAWAL_FEE);

        emit VPoolWithdrawalFeeSet(_newFee);

        vPoolWithdrawalFee = _newFee;
    }

    // ==============================================================================
    // Validator Pool State Setters
    // ==============================================================================

    // ------------------------------------------------------------------------

    /// @notice If the borrow allowance trying to be set is wrong
    error IncorrectBorrowAllowance(uint256 _maxAllowance, uint256 _newAllowance);

    /// @notice When some validator pools have both their total validator counts and/or borrow allowances set
    /// @param _validatorPoolAddresses The addresses of the validator pools
    /// @param _setValidatorCounts Whether to set the validator counts
    /// @param _setBorrowAllowances Whether to set the borrow allowances
    /// @param _newValidatorCounts The new total validator count for each pool
    /// @param _newBorrowAllowances The new borrow allowances for the validators
    /// @param _lastWithdrawalTimestamps validatorPoolAccounts's lastWithdrawal. When this function eventually is called, after a frxGov delay, _lastWithdrawalTimestamps need to match.
    event VPoolValidatorCountsAndBorrowAllowancesSet(
        address[] _validatorPoolAddresses,
        bool _setValidatorCounts,
        bool _setBorrowAllowances,
        uint32[] _newValidatorCounts,
        uint128[] _newBorrowAllowances,
        uint32[] _lastWithdrawalTimestamps
    );

    /// @notice Set the total validator count and/or the borrow allowance for each pool
    /// @param _validatorPoolAddresses The addresses of the validator pools
    /// @param _setValidatorCounts Whether to set the validator counts
    /// @param _setBorrowAllowances Whether to set the borrow allowances
    /// @param _newValidatorCounts The new total validator count for each pool
    /// @param _newBorrowAllowances The new borrow allowances for the validators
    /// @param _lastWithdrawalTimestamps validatorPoolAccounts's lastWithdrawal. When this function eventually is called, after a frxGov delay, _lastWithdrawalTimestamps need to match. Prevents the user from withdrawing immediately after depositing to earn a fake borrow allowance and steal funds.
    function setVPoolValidatorCountsAndBorrowAllowances(
        address[] calldata _validatorPoolAddresses,
        bool _setValidatorCounts,
        bool _setBorrowAllowances,
        uint32[] calldata _newValidatorCounts,
        uint128[] calldata _newBorrowAllowances,
        uint32[] calldata _lastWithdrawalTimestamps
    ) external {
        _requireSenderIsBeaconOracle();

        // Check that the _lastWithdrawalTimestamps array length matches _validatorPoolAddresses
        if (_validatorPoolAddresses.length != _lastWithdrawalTimestamps.length) revert InputArrayLengthMismatch();

        // Check that the _newValidatorCounts array length matches _validatorPoolAddresses
        if (_setValidatorCounts && (_validatorPoolAddresses.length != _newValidatorCounts.length)) {
            revert InputArrayLengthMismatch();
        }

        // Check that the _newBorrowAllowances array length matches _validatorPoolAddresses
        if (_setBorrowAllowances && (_validatorPoolAddresses.length != _newBorrowAllowances.length)) {
            revert InputArrayLengthMismatch();
        }

        // Accumulate interest
        _addInterest(false);

        for (uint256 i = 0; i < _validatorPoolAddresses.length; ) {
            // Fetch the address of the validator pool
            address _validatorPoolAddr = _validatorPoolAddresses[i];

            // Fetch the validator pool account
            ValidatorPoolAccount memory _validatorPoolAccount = validatorPoolAccounts[_validatorPoolAddr];

            // Make sure the validator pool is initialized
            _requireValidatorPoolInitialized(_validatorPoolAddr);

            // Make sure the user did not withdraw in the meantime
            if (_lastWithdrawalTimestamps[i] != _validatorPoolAccount.lastWithdrawal) {
                revert WithdrawalTimestampMismatch(_lastWithdrawalTimestamps[i], _validatorPoolAccount.lastWithdrawal);
            }

            // Set the validators, if specified
            if (_setValidatorCounts) {
                // Set the validator count
                _validatorPoolAccount.validatorCount = _newValidatorCounts[i];
            }

            // Set the borrow allowances, if specified
            if (_setBorrowAllowances) {
                // Calculate the optimistic amount of credit, assuming no borrowing
                uint256 _optimisticAllowance = (uint256(_validatorPoolAccount.validatorCount) *
                    (uint256(_validatorPoolAccount.creditPerValidatorI48_E12) * MISSING_CREDPERVAL_MULT));

                // Calculate the maximum allowance
                uint256 _maxAllowance;
                uint256 _borrowedAmount = toBorrowAmountOptionalRoundUp(_validatorPoolAccount.borrowShares, true);
                if (_optimisticAllowance == 0) {
                    // This may hit if a liquidated user welches on interest if the validator exits are not enough to cover the borrow + interest.
                    _maxAllowance = 0;
                } else if (_borrowedAmount > _optimisticAllowance) {
                    // New allowance should not be negative
                    revert AllowanceWouldBeNegative();
                } else {
                    // Calculate the maximum allowance. Could use unchecked here but meh
                    _maxAllowance = _optimisticAllowance - _borrowedAmount;
                }

                // Revert if you are trying to set above the maximum allowance
                if (_newBorrowAllowances[i] > _maxAllowance) {
                    revert IncorrectBorrowAllowance(_maxAllowance, _newBorrowAllowances[i]);
                }

                // Set the borrow allowance
                _validatorPoolAccount.borrowAllowance = _newBorrowAllowances[i];
            }

            // Write to storage
            validatorPoolAccounts[_validatorPoolAddr] = _validatorPoolAccount;

            // Increment
            unchecked {
                ++i;
            }
        }

        // Update the stored utilization rate
        updateUtilization();

        // Emit
        emit VPoolValidatorCountsAndBorrowAllowancesSet(
            _validatorPoolAddresses,
            _setValidatorCounts,
            _setBorrowAllowances,
            _newValidatorCounts,
            _newBorrowAllowances,
            _lastWithdrawalTimestamps
        );
    }

    // ------------------------------------------------------------------------
    /// @notice When some validator pools have their credits per validator set
    /// @param _validatorPoolAddresses The addresses of the validator pools
    /// @param _newCreditsPerValidator The new total number of credits per validator
    event VPoolCreditsPerPoolSet(address[] _validatorPoolAddresses, uint48[] _newCreditsPerValidator);

    /// @notice Set the amount of Eth credit per validator pool
    /// @param _validatorPoolAddresses The addresses of the validator pools
    /// @param _newCreditsPerValidator The new total number of credits per validator
    function setVPoolCreditsPerValidator(
        address[] calldata _validatorPoolAddresses,
        uint48[] calldata _newCreditsPerValidator
    ) external {
        _requireSenderIsBeaconOracle();

        // Check that the input arrays have the same length
        if (_validatorPoolAddresses.length != _newCreditsPerValidator.length) revert InputArrayLengthMismatch();

        for (uint256 i = 0; i < _validatorPoolAddresses.length; ) {
            // Make sure the validator pool is initialized
            _requireValidatorPoolInitialized(_validatorPoolAddresses[i]);

            // Make sure you are not setting the credit per validator to over MAXIMUM_CREDIT_PER_VALIDATOR_I48_E12 (31 ETH)
            require(
                _newCreditsPerValidator[i] <= MAXIMUM_CREDIT_PER_VALIDATOR_I48_E12,
                "Credit per validator > MAXIMUM_CREDIT_PER_VALIDATOR_I48_E12"
            );

            // Set the credit
            validatorPoolAccounts[_validatorPoolAddresses[i]].creditPerValidatorI48_E12 = _newCreditsPerValidator[i];

            // Increment
            unchecked {
                ++i;
            }
        }

        emit VPoolCreditsPerPoolSet(_validatorPoolAddresses, _newCreditsPerValidator);
    }

    // ------------------------------------------------------------------------
    /// @notice When approval statuses for a multiple validator pubkeys are set
    /// @param _validatorPublicKeys The pubkeys being set
    /// @param _validatorPoolAddresses The validator pools associated with the pubkeys being set
    /// @param _whenApprovedArr When the pubkeys were approved. 0 if they were not
    event VPoolApprovalsSet(bytes[] _validatorPublicKeys, address[] _validatorPoolAddresses, uint32[] _whenApprovedArr);

    /// @notice Set the approval statuses for a multiple validator pubkeys
    /// @param _validatorPublicKeys The pubkeys being set
    /// @param _validatorPoolAddresses The validator pools associated with the pubkeys being set
    /// @param _whenApprovedArr When the pubkeys were approved. 0 if they were not
    /// @param _lastWithdrawalTimestamps validatorPoolAccounts's lastWithdrawal. When this function eventually is called, after a frxGov delay, _lastWithdrawalTimestamps need to match. Prevents the user from withdrawing immediately after depositing to earn a fake borrow allowance and steal funds.
    function setValidatorApprovals(
        bytes[] calldata _validatorPublicKeys,
        address[] calldata _validatorPoolAddresses,
        uint32[] calldata _whenApprovedArr,
        uint32[] calldata _lastWithdrawalTimestamps
    ) external {
        _requireSenderIsBeaconOracle();

        // Check that the input arrays have the same length
        {
            uint256 _arrLength = _validatorPublicKeys.length;
            if (
                (_validatorPoolAddresses.length != _arrLength) ||
                (_whenApprovedArr.length != _arrLength) ||
                (_lastWithdrawalTimestamps.length != _arrLength)
            ) revert InputArrayLengthMismatch();
        }

        for (uint256 i = 0; i < _validatorPublicKeys.length; ) {
            // Fetch the address of the validator pool
            address _validatorPoolAddr = _validatorPoolAddresses[i];

            // Fetch the validator pool account
            ValidatorPoolAccount memory _validatorPoolAccount = validatorPoolAccounts[_validatorPoolAddr];

            // Make sure the user did not withdraw in the meantime
            if (_lastWithdrawalTimestamps[i] != _validatorPoolAccount.lastWithdrawal) {
                revert WithdrawalTimestampMismatch(_lastWithdrawalTimestamps[i], _validatorPoolAccount.lastWithdrawal);
            }

            // Revert if the provided validator pool address doesn't match the first depositor set in initialDepositValidator()
            // It should never be address(0) because the Beacon Oracle check cannot happen before the initial deposit
            if (validatorDepositInfo[_validatorPublicKeys[i]].validatorPoolAddress != _validatorPoolAddr) {
                revert ValidatorPoolKeyMismatch();
            }

            // Set the validator approval state
            validatorDepositInfo[_validatorPublicKeys[i]].whenValidatorApproved = _whenApprovedArr[i];

            // Increment
            unchecked {
                ++i;
            }
        }

        emit VPoolApprovalsSet(_validatorPublicKeys, _validatorPoolAddresses, _whenApprovedArr);
    }

    // ==============================================================================
    // Validator Pool Factory Functions
    // ==============================================================================

    /// @notice The ```setCreationCode``` function sets the bytecode for the ValidatorPool
    /// @dev splits the data if necessary to accommodate creation code that is slightly larger than 24kb
    /// @param _creationCode The creationCode for the ValidatorPool
    function setCreationCode(bytes memory _creationCode) external {
        _requireSenderIsTimelock();
        _setCreationCode(_creationCode);
    }

    /// @notice The ```setCreationCode``` function sets the bytecode for the ValidatorPool
    /// @dev splits the data if necessary to accommodate creation code that is slightly larger than 24kb
    /// @param _creationCode The creationCode for the ValidatorPool
    function _setCreationCode(bytes memory _creationCode) internal {
        validatorPoolCreationCodeAddress = SSTORE2.write(_creationCode);
    }

    // ------------------------------------------------------------------------
    /// @notice When a validator pool is created
    /// @param _validatorPoolOwnerAddress The owner of the validator pool
    /// @return _poolAddress The address of the validator pool that was created
    event VPoolDeployed(address _validatorPoolOwnerAddress, address _poolAddress);

    /// @notice Deploy a validator pool (callable by anyone)
    /// @param _validatorPoolOwnerAddress The owner of the validator pool
    /// @param _extraSalt An extra salt bytes32 provided by the user
    /// @return _poolAddress The address of the validator pool that was created
    function deployValidatorPool(
        address _validatorPoolOwnerAddress,
        bytes32 _extraSalt
    ) public returns (address payable _poolAddress) {
        // Get creation code
        bytes memory _creationCode = SSTORE2.read(validatorPoolCreationCodeAddress);

        // Get bytecode
        bytes memory bytecode = abi.encodePacked(
            _creationCode,
            abi.encode(_validatorPoolOwnerAddress, payable(address(this)), payable(address(ETH2_DEPOSIT_CONTRACT)))
        );

        bytes32 _salt = keccak256(abi.encodePacked(msg.sender, _validatorPoolOwnerAddress, _extraSalt));

        /// @solidity memory-safe-assembly
        assembly {
            _poolAddress := create2(0, add(bytecode, 32), mload(bytecode), _salt)
        }
        if (_poolAddress == address(0)) revert("create2 failed");

        // Mark validator pool as approved
        validatorPoolAccounts[_poolAddress].isInitialized = true;
        validatorPoolAccounts[_poolAddress].creditPerValidatorI48_E12 = DEFAULT_CREDIT_PER_VALIDATOR_I48_E12;

        emit VPoolDeployed(_validatorPoolOwnerAddress, _poolAddress);
    }

    // ==============================================================================
    // Preview Interest Functions
    // ==============================================================================

    /// @notice Get information about a validator pool
    /// @param _validatorPoolAddress The validator pool in question
    function previewValidatorAccounts(
        address _validatorPoolAddress
    ) external view returns (ValidatorPoolAccount memory) {
        return validatorPoolAccounts[_validatorPoolAddress];
    }

    // ==============================================================================
    // Reentrancy View Function
    // ==============================================================================

    /// @notice Get the entrancy status
    /// @return _isEntered If the contract has already been entered
    function entrancyStatus() external view returns (bool _isEntered) {
        _isEntered = _status == 2;
    }
}
