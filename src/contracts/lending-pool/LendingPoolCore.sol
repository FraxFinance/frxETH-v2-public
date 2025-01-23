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
// ========================= LendingPoolCore ==========================
// ====================================================================
// Recieves and gives out ETH to ValidatorPools for lending and borrowing (core code)

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Drake Evans: https://github.com/DrakeEvans
// Travis Moore: https://github.com/FortisFortuna

// Reviewer(s) / Contributor(s)
// Dennis: https://github.com/denett
// Sam Kazemian: https://github.com/samkazemian

import { Timelock2Step } from "frax-std/access-control/v2/Timelock2Step.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ValidatorPool } from "../ValidatorPool.sol";
import { VaultAccount, VaultAccountingLibrary } from "../libraries/VaultAccountingLibrary.sol";
import { BeaconOracle } from "../BeaconOracle.sol";
import { BeaconOracle, BeaconOracleRole } from "../access-control/BeaconOracleRole.sol";
import { EtherRouter, EtherRouterRole } from "../access-control/EtherRouterRole.sol";
import { FraxEtherRedemptionQueueV2, RedemptionQueueV2Role } from "../access-control/RedemptionQueueV2Role.sol";
import { IFrxEth } from "../interfaces/IFrxEth.sol";
import { IInterestRateCalculator } from "./IInterestRateCalculator.sol";
import { PublicReentrancyGuard } from "frax-std/access-control/v2/PublicReentrancyGuard.sol";
// import { console } from "frax-std/FraxTest.sol";
import { IDepositContract } from "../interfaces/IDepositContract.sol";

/// @notice Constructor information for the lending pool core
/// @param frxEthAddress Address of the frxETH token
/// @param timelockAddress The address of the governance timelock
/// @param etherRouterAddress The Ether Router address
/// @param beaconOracleAddress The Beacon Oracle address
/// @param redemptionQueueAddress The Redemption Queue address
/// @param interestRateCalculatorAddress Address used for interest rate calculations
/// @param eth2DepositAddress Address of the Eth2 deposit contract
/// @param fullUtilizationRate The interest rate at full utilization
struct LendingPoolCoreParams {
    address frxEthAddress;
    address timelockAddress;
    address payable etherRouterAddress;
    address beaconOracleAddress;
    address payable redemptionQueueAddress;
    address interestRateCalculatorAddress;
    address payable eth2DepositAddress;
    uint64 fullUtilizationRate;
}

/// @title Recieves and gives out ETH to ValidatorPools for lending and borrowing
/// @author Frax Finance
/// @notice Controlled by Frax governance and validator pools
abstract contract LendingPoolCore is
    EtherRouterRole,
    BeaconOracleRole,
    RedemptionQueueV2Role,
    Timelock2Step,
    PublicReentrancyGuard
{
    using SafeCast for uint256;
    using VaultAccountingLibrary for VaultAccount;

    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    /// @notice frxETH
    IFrxEth public immutable frxETH;

    /// @notice The official Eth2 deposit contract
    IDepositContract public immutable ETH2_DEPOSIT_CONTRACT;

    /// @notice Precision for the utilization ratio
    uint256 public constant UTILIZATION_PRECISION = 1e5;

    /// @notice Precision for the interest rate
    uint256 public constant INTEREST_RATE_PRECISION = 1e18;

    /// @notice Total amount of ETH currently borrowed
    VaultAccount public totalBorrow;

    /// @notice Total amount of ETH interest accrued from lending out the ETH
    uint256 public interestAccrued;

    /// @notice Stored utilization rate, to mitigate manipulation. Updated with addInterest.
    uint256 public utilizationStored;

    /// @notice Contract for interest rate calculations
    IInterestRateCalculator public rateCalculator;

    /// @notice Multiplier for credits per vault calculations
    uint256 public immutable MISSING_CREDPERVAL_MULT = 1e6;

    /// @notice Minimum borrow amount (used to help with share rounding / prevent share manipulation)
    uint256 public constant MINIMUM_BORROW_AMOUNT = 1000 gwei;

    /// @notice ValidatorPool state information
    /// @param isInitialialized If the validator pool is initialized
    /// @param wasLiquidated If the validator pool is currently being liquidated
    /// @param lastWithdrawal The last time the validator pool made a withdrawal
    /// @param validatorCount The number of validators the pool has
    /// @param creditPerValidatorI48_E12 The amount of lending credit per validator. 12 decimals of precision. Max is ~281e12
    /// @param borrowShares How many shares the pool is currently borrowing
    struct ValidatorPoolAccount {
        bool isInitialized;
        bool wasLiquidated;
        uint32 lastWithdrawal;
        uint32 validatorCount;
        uint48 creditPerValidatorI48_E12;
        uint128 borrowAllowance;
        uint256 borrowShares;
    }

    /// @notice Validator pool account information
    mapping(address _validatorPool => ValidatorPoolAccount) public validatorPoolAccounts;

    /// @notice ValidatorPool pubkey deposit information
    /// @param whenValidatorApproved When the pubkey was approved by the beacon oracle. 0 if it was not
    /// @param wasFullDepositOrFinalized If the pubkey was either a full 32 ETH deposit, or if it was a partial that was finalized.
    /// @param validatorPoolAddress The validator pool associated with the pubkey
    /// @param userDepositedEther The amount of Eth the validator pool contributed. Will be less than 32 Eth for a partial deposit
    /// @param lendingPoolDepositedEther The amount of Eth the lending pool loaned to complete this deposit. Will be > 0 for a partial deposit.
    /// @dev Useful for tracking full vs partial deposits
    struct ValidatorDepositInfo {
        uint32 whenValidatorApproved;
        bool wasFullDepositOrFinalized;
        address validatorPoolAddress;
        uint96 userDepositedEther;
        uint96 lendingPoolDepositedEther;
    }

    /// @notice Validator pool deposit information
    mapping(bytes _validatorPublicKey => ValidatorDepositInfo) public validatorDepositInfo;

    /// @notice Current interest rate information (storage variable)
    CurrentRateInfo public currentRateInfo;

    /// @notice Current interest rate information (struct)
    /// @param lastTimestamp Timestamp of the last state update
    /// @param ratePerSec Interest rate, in e18 per second
    /// @param fullUtilizationRate The rate at full utilization
    struct CurrentRateInfo {
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint64 fullUtilizationRate;
    }

    /// @notice Allowed liquidators
    mapping(address _addr => bool _canLiquidate) public isLiquidator;

    // ==============================================================================
    // Constructor
    // ==============================================================================

    /// @notice Constructor
    /// @param _params The LendingPoolCoreParams
    constructor(
        LendingPoolCoreParams memory _params
    )
        Timelock2Step(_params.timelockAddress)
        RedemptionQueueV2Role(_params.redemptionQueueAddress)
        EtherRouterRole(_params.etherRouterAddress)
        BeaconOracleRole(_params.beaconOracleAddress)
    {
        frxETH = IFrxEth(_params.frxEthAddress);
        rateCalculator = IInterestRateCalculator(_params.interestRateCalculatorAddress);
        currentRateInfo.fullUtilizationRate = _params.fullUtilizationRate;
        currentRateInfo.lastTimestamp = uint64(block.timestamp - 1);

        ETH2_DEPOSIT_CONTRACT = IDepositContract(_params.eth2DepositAddress);
    }

    // ==============================================================================
    // Check functions
    // ==============================================================================

    /// @notice Reverts if the pubkey is not associated with the validator pool address supplied
    /// @param _address The address of the validator pool that should be associated with the pubkey
    /// @param _publicKey The pubkey to check
    function _requireAddressAssociatedWithPubkey(address _address, bytes calldata _publicKey) internal view {
        if (validatorDepositInfo[_publicKey].validatorPoolAddress != _address) revert ValidatorPoolKeyMismatch();
    }

    /// @notice Reverts if the address cannot liquidate
    /// @param _address The address to check
    /// @dev Either an allowed liquidator, the timelock, or the beacon oracle
    function _requireAddressCanLiquidate(address _address) internal view {
        if (!(isLiquidator[_address] || (_address == timelockAddress) || (_address == address(beaconOracle)))) {
            revert NotAllowedLiquidator();
        }
    }

    /// @notice Checks if msg.sender is the ether router or the redemption queue
    function _requireSenderIsEtherRouterOrRedemptionQueue() internal view {
        if (!((msg.sender == address(etherRouter)) || (msg.sender == address(redemptionQueue)))) {
            revert NotEtherRouterOrRedemptionQueue();
        }
    }

    /// @notice Reverts if the validator pubkey is not approved
    /// @param _publicKey The pubkey to check
    function _requireValidatorApproved(bytes calldata _publicKey) internal view {
        if (!isValidatorApproved(_publicKey)) revert ValidatorIsNotApprovedLP();
    }

    /// @notice Reverts if the validator pubkey is not initialized
    /// @param _publicKey The pubkey to check
    function _requireValidatorInitialized(bytes calldata _publicKey) internal view {
        if (validatorDepositInfo[_publicKey].userDepositedEther == 0) revert ValidatorIsNotInitialized();
    }

    /// @notice Reverts if the validator pool is not initialized
    /// @param _address The address of the validator pool to check
    function _requireValidatorPoolInitialized(address _address) internal view {
        if (!validatorPoolAccounts[_address].isInitialized) revert InvalidValidatorPool();
    }

    /// @notice Reverts if the validator pool is insolvent
    /// @param _validatorPool The validator pool address
    function _requireValidatorPoolIsSolvent(address _validatorPool) internal view {
        if (!isSolvent(_validatorPool)) revert ValidatorPoolIsNotSolvent();
    }

    /// @notice Reverts if the validator pool is in liquidation
    /// @param _address The address of the validator pool to check
    function _requireValidatorPoolNotLiquidated(address _address) internal view {
        if (validatorPoolAccounts[_address].wasLiquidated) revert ValidatorPoolWasLiquidated();
    }

    // ==============================================================================
    // Helper Functions
    // ==============================================================================

    /// @notice Get the last withdrawal time for an address
    /// @param _validatorPoolAddress The validator pool being looked up
    /// @return _lastWithdrawalTimestamp The timestamp of the last withdrawal
    function getLastWithdrawalTimestamp(
        address _validatorPoolAddress
    ) public view returns (uint32 _lastWithdrawalTimestamp) {
        // Get the timestamp
        _lastWithdrawalTimestamp = validatorPoolAccounts[_validatorPoolAddress].lastWithdrawal;
    }

    /// @notice Get the last withdrawal times for a given set of addresses
    /// @param _validatorPoolAddresses The validator pools being looked up
    /// @return _lastWithdrawalTimestamps The timestamps of the last withdrawals
    function getLastWithdrawalTimestamps(
        address[] calldata _validatorPoolAddresses
    ) public view returns (uint32[] memory _lastWithdrawalTimestamps) {
        // Initialize the return array
        _lastWithdrawalTimestamps = new uint32[](_validatorPoolAddresses.length);

        // Loop through the addresses
        // --------------------------------------------------------
        for (uint256 i = 0; i < _validatorPoolAddresses.length; ) {
            // Add the timestamp to the return array
            _lastWithdrawalTimestamps[i] = validatorPoolAccounts[_validatorPoolAddresses[i]].lastWithdrawal;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Return the current utilization
    /// @param _cachedBals AMO values from getConsolidatedEthFrxEthBalance
    /// @param _skipRQReentrantCheck True to disable checking RedemptionQueue reentrancy. Only should be True for addInterestPrivileged calls
    /// @return _utilization The current utilization
    /// @dev ETH in LP on the Curve AMO is considered "utilized" and thus a "liability"
    function _getUtilizationPostCore(
        EtherRouter.CachedConsEFxBalances memory _cachedBals,
        bool _skipRQReentrantCheck
    ) internal view returns (uint256 _utilization) {
        // console.log("_getUtilizationPostCore: PART 0");

        // Check for reentrancy
        if (!_skipRQReentrantCheck && redemptionQueue.entrancyStatus()) revert ReentrancyStatusIsTrue();

        // console.log("_getUtilizationPostCore: PART 1");

        // Check the shortage or surplus of ETH in the redemption queue
        (int256 _netEthBalance, ) = redemptionQueue.ethShortageOrSurplus();

        // console.log("_getUtilizationPostCore: PART 2");

        // Return 100% utilization if there would be an underflow due to an ETH shortage in the redemption queue
        int256 denominator = int256(totalBorrow.amount) +
            int256(uint256(_cachedBals.ethTotalBalanced)) +
            _netEthBalance;
        if (denominator <= 0) {
            // console.log("_getUtilizationPostCore: PART 2B");
            return UTILIZATION_PRECISION;
        }

        // console.log("_getUtilizationPostCore (numerator): %s", totalBorrow.amount * UTILIZATION_PRECISION);
        // console.log("_getUtilizationPostCore (totalBorrow.amount): %s", totalBorrow.amount);
        // console.log("_getUtilizationPostCore (_cachedBals.ethTotalBalanced): %s", _cachedBals.ethTotalBalanced);
        // console.log("_getUtilizationPostCore (_netEthBalance): %s", _netEthBalance);
        // console.log("_getUtilizationPostCore (denominator): %s", denominator);
        // console.log("_getUtilizationPostCore: PART 3");
        // Calculate the utilization
        _utilization = (totalBorrow.amount * UTILIZATION_PRECISION) / (uint256(denominator));

        // console.log("_utilization (uncapped): %s", _utilization);
        // console.log("_getUtilizationPostCore: PART 4");
        // Cap the utilization at 100%
        if (_utilization > UTILIZATION_PRECISION) _utilization = UTILIZATION_PRECISION;

        // console.log("_getUtilizationPostCore: PART 5");
    }

    /// @notice Return the current utilization. Calculates live AMO values. Should only be called internally
    /// @param _forceLive Force a live recalculation of the AMO values
    /// @param _updateCache Update the cached AMO values, if they were stale
    /// @param _skipRQReentrantCheck True to disable checking RedemptionQueue reentrancy. Only should be True for addInterestPrivileged calls
    /// @return _utilization The current utilization
    /// @dev ETH in LP on the Curve AMO is considered "utilized" and thus a "liability"
    function _getUtilizationInternal(
        bool _forceLive,
        bool _updateCache,
        bool _skipRQReentrantCheck
    ) internal returns (uint256 _utilization) {
        // console.log("_getUtilizationInternal: PART 1");
        EtherRouter.CachedConsEFxBalances memory _cachedBals = etherRouter.getConsolidatedEthFrxEthBalance(
            _forceLive,
            _updateCache
        );
        // console.log("_getUtilizationInternal: PART 2");
        return _getUtilizationPostCore(_cachedBals, _skipRQReentrantCheck);
    }

    /// @notice Return the current utilization. Calculates live AMO values
    /// @param _forceLive Force a live recalculation of the AMO values
    /// @param _updateCache Update the cached AMO values, if they were stale
    /// @return _utilization The current utilization
    /// @dev ETH in LP on the Curve AMO is considered "utilized" and thus a "liability"
    function getUtilization(bool _forceLive, bool _updateCache) public returns (uint256 _utilization) {
        return _getUtilizationInternal(_forceLive, _updateCache, false);
    }

    /// @notice Return the current utilization. Calculates live AMO values
    /// @return _utilization The current utilization
    /// @dev ETH in LP on the Curve AMO is considered "utilized" and thus a "liability"
    function getUtilizationView() public view returns (uint256 _utilization) {
        EtherRouter.CachedConsEFxBalances memory _cachedBals = etherRouter.getConsolidatedEthFrxEthBalanceView(true);
        return _getUtilizationPostCore(_cachedBals, false);
    }

    /// @notice Return the max amount of ETH available to borrow
    /// @return _maxBorrow The amount of ETH available to borrow
    function getMaxBorrow() external view returns (uint256 _maxBorrow) {
        EtherRouter.CachedConsEFxBalances memory _cachedBals = etherRouter.getConsolidatedEthFrxEthBalanceView(true);
        (, uint256 _rqShortage) = redemptionQueue.ethShortageOrSurplus();

        // If there is a shortage, you have to subtract it from the available borrow
        if (_cachedBals.ethTotalBalanced >= _rqShortage) {
            _maxBorrow = (_cachedBals.ethTotalBalanced - _rqShortage);
        } else {
            // _maxBorrow = 0; // Redundant set
        }
    }

    /// @notice Whether the provided validator pool is solvent, accounting just for accrued interest
    /// @param _validatorPoolAddress The validator pool address
    /// @return _isSolvent Whether the provided validator pool is solvent
    function isSolvent(address _validatorPoolAddress) public view returns (bool _isSolvent) {
        (_isSolvent, , ) = wouldBeSolvent(_validatorPoolAddress, true, 0, 0);
    }

    /// @notice Returns whether the public key has been approved by the beacon oracle
    /// @param _publicKey The pubkey to check
    /// @return _isApproved Whether the provided validator pool is solvent
    function isValidatorApproved(bytes calldata _publicKey) public view returns (bool _isApproved) {
        // Get the deposit info for the validator
        ValidatorDepositInfo memory _validatorDepositInfo = validatorDepositInfo[_publicKey];

        // Return early if it was never approved at all
        if (_validatorDepositInfo.whenValidatorApproved == 0) return false;

        // Fetch the validator pool info
        ValidatorPoolAccount memory _poolAcc = validatorPoolAccounts[_validatorDepositInfo.validatorPoolAddress];

        // A validator can only be approved if a withdrawal (if it ever happened in the first place)
        // occured before the beacon approval timestamp
        _isApproved = (_poolAcc.lastWithdrawal < _validatorDepositInfo.whenValidatorApproved);
    }

    /// @notice Convert borrow shares to Eth amount. Defaults to rounding up
    /// @param _shares Amount of borrow shares
    /// @return _borrowAmount The amount of Eth borrowed
    function toBorrowAmount(uint256 _shares) public view returns (uint256 _borrowAmount) {
        _borrowAmount = totalBorrow._toAmount(_shares, true);
    }

    /// @notice Convert borrow shares to Eth amount. Optionally rounds up
    /// @param _shares Amount of borrow shares
    /// @param _roundUp Amount of borrow shares
    /// @return _borrowAmount The amount of Eth borrowed
    function toBorrowAmountOptionalRoundUp(uint256 _shares, bool _roundUp) public view returns (uint256 _borrowAmount) {
        _borrowAmount = totalBorrow._toAmount(_shares, _roundUp);
    }

    /// @notice Helper method to check if the validator pool is/was liquidated
    /// @param _validatorPoolAddress The validator pool address
    /// @return _wasLiquidated Whether the validator pool is/was liquidated
    function wasLiquidated(address _validatorPoolAddress) public view returns (bool _wasLiquidated) {
        // Get the validator pool account info
        ValidatorPoolAccount memory _validatorPoolAccount = validatorPoolAccounts[_validatorPoolAddress];
        _wasLiquidated = _validatorPoolAccount.wasLiquidated;
    }

    /// @notice Solvency details for a validator pool, accounting for accrued interest.
    /// @param _validatorPoolAddress The validator pool address
    /// @param _accrueInterest Whether to accrue interest first. Should be true in most cases. False if you did it before somewhere and want to save gas
    /// @param _addlValidators Additional validators to test solvency for. Can be zero.
    /// @param _addlBorrowAmount Additional borrow amount to test solvency for. Can be zero.
    /// @return _wouldBeSolvent Whether the provided validator pool would be solvent given the interest accrual and additional borrow, if any.
    /// @return _borrowAmount Borrowed amount for the specified validator pool
    /// @return _creditAmount Credit amount for the specified validator pool
    function wouldBeSolvent(
        address _validatorPoolAddress,
        bool _accrueInterest,
        uint256 _addlValidators,
        uint256 _addlBorrowAmount
    ) public view returns (bool _wouldBeSolvent, uint256 _borrowAmount, uint256 _creditAmount) {
        // Get the validator pool account info
        ValidatorPoolAccount memory _validatorPoolAccount = validatorPoolAccounts[_validatorPoolAddress];

        // Accrue interest (non-write) first
        // Normally true, but false if you already did it previously in the same call and want to save gas
        VaultAccount memory _totalBorrow;
        if (_accrueInterest) {
            (, , , , _totalBorrow) = previewAddInterest();
        } else {
            _totalBorrow = totalBorrow;
        }

        // Get the borrowed amount for the validator pool, adding the new borrow amount if applicable
        _borrowAmount = _addlBorrowAmount + _totalBorrow._toAmount(_validatorPoolAccount.borrowShares, true);

        // Get the credit amount for the validator pool
        _creditAmount =
            _validatorPoolAccount.creditPerValidatorI48_E12 *
            MISSING_CREDPERVAL_MULT *
            (_validatorPoolAccount.validatorCount + _addlValidators);

        // Check if it is solvent, or if it was liquidated
        if ((_creditAmount >= _borrowAmount) && !_validatorPoolAccount.wasLiquidated) _wouldBeSolvent = true;
    }

    // ============================================================================================
    // Functions: Interest Accumulation and Adjustment
    // ============================================================================================

    /// @notice The ```AddInterest``` event is emitted when interest is accrued by borrowers
    /// @param interestEarned The total interest accrued by all borrowers
    /// @param rate The interest rate used to calculate accrued interest
    /// @param feesAmount The amount of fees paid to protocol
    /// @param feesShare The amount of shares distributed to protocol
    event AddInterest(uint256 interestEarned, uint256 rate, uint256 feesAmount, uint256 feesShare);

    /// @notice The ```UpdateRate``` event is emitted when the interest rate is updated
    /// @param oldRatePerSec The old interest rate (per second)
    /// @param oldFullUtilizationRate The old full utilization rate
    /// @param newRatePerSec The new interest rate (per second)
    /// @param newFullUtilizationRate The new full utilization rate
    event UpdateRate(
        uint256 oldRatePerSec,
        uint256 oldFullUtilizationRate,
        uint256 newRatePerSec,
        uint256 newFullUtilizationRate
    );

    /// @notice The ```addInterest``` function is a public implementation of _addInterest and allows 3rd parties to trigger interest accrual
    /// @return _interestEarned The amount of interest accrued by all borrowers
    /// @return _feesAmount The amount of fees paid to protocol
    /// @return _feesShare The amount of shares distributed to protocol
    /// @return _currentRateInfo The new rate info struct
    /// @return _totalBorrow The new total borrow struct
    function addInterest(
        bool _returnAccounting
    )
        public
        nonReentrant
        returns (
            uint256 _interestEarned,
            uint256 _feesAmount,
            uint256 _feesShare,
            CurrentRateInfo memory _currentRateInfo,
            VaultAccount memory _totalBorrow
        )
    {
        // Accrue interest
        (, _interestEarned, _feesAmount, _feesShare, _currentRateInfo) = _addInterest(false);

        // Optionally return borrow information
        if (_returnAccounting) {
            _totalBorrow = totalBorrow;
        }
    }

    /// @notice Same as addInterest but without the reentrancy check (it would be done on the calling function). Only EtherRouter or RedemptionQueue can call
    /// @return _interestEarned The amount of interest accrued by all borrowers
    /// @return _feesAmount The amount of fees paid to protocol
    /// @return _feesShare The amount of shares distributed to protocol
    /// @return _currentRateInfo The new rate info struct
    /// @return _totalBorrow The new total borrow struct
    function addInterestPrivileged(
        bool _returnAccounting
    )
        external
        returns (
            uint256 _interestEarned,
            uint256 _feesAmount,
            uint256 _feesShare,
            CurrentRateInfo memory _currentRateInfo,
            VaultAccount memory _totalBorrow
        )
    {
        // Skip reentrancy check for certain callers
        _requireSenderIsEtherRouterOrRedemptionQueue();

        // Accrue interest
        (, _interestEarned, _feesAmount, _feesShare, _currentRateInfo) = _addInterest(true);

        // Optionally return borrow information
        if (_returnAccounting) {
            _totalBorrow = totalBorrow;
        }
    }

    /// @notice Preview adding interest
    /// @return _interestEarned The amount of interest accrued by all borrowers
    /// @return _feesAmount The amount of fees paid to protocol
    /// @return _feesShare The amount of shares distributed to protocol
    /// @return _newCurrentRateInfo The new rate info struct
    /// @return _totalBorrow The new total borrow struct
    function previewAddInterest()
        public
        view
        returns (
            uint256 _interestEarned,
            uint256 _feesAmount,
            uint256 _feesShare,
            CurrentRateInfo memory _newCurrentRateInfo,
            VaultAccount memory _totalBorrow
        )
    {
        _newCurrentRateInfo = currentRateInfo;

        // Write return values
        // InterestCalculationResults memory _results = _calculateInterestView(_newCurrentRateInfo);
        InterestCalculationResults memory _results = _calculateInterestWithStored(_newCurrentRateInfo);

        if (_results.isInterestUpdated) {
            _interestEarned = _results.interestEarned;

            _newCurrentRateInfo.ratePerSec = _results.newRate;
            _newCurrentRateInfo.fullUtilizationRate = _results.newFullUtilizationRate;

            _totalBorrow = _results.totalBorrow;
        } else {
            _totalBorrow = totalBorrow;
        }
    }

    struct InterestCalculationResults {
        bool isInterestUpdated;
        uint64 newRate;
        uint64 newFullUtilizationRate;
        uint256 interestEarned;
        VaultAccount totalBorrow;
    }

    /// @notice Calculates the interest to be accrued and the new interest rate info
    /// @param _currentRateInfo The current rate info
    /// @return _results The results of the interest calculation
    function _calculateInterestCore(
        CurrentRateInfo memory _currentRateInfo,
        uint256 _utilizationRate
    ) internal view returns (InterestCalculationResults memory _results) {
        // Short circuit if interest already calculated this block OR if interest is paused
        if (_currentRateInfo.lastTimestamp != block.timestamp) {
            // Indicate that interest is updated and calculated
            _results.isInterestUpdated = true;

            // Write return values and use these to save gas
            _results.totalBorrow = totalBorrow;

            // Time elapsed since last interest update
            uint256 _deltaTime = block.timestamp - _currentRateInfo.lastTimestamp;

            // Request new interest rate and full utilization rate from the rate calculator
            (_results.newRate, _results.newFullUtilizationRate) = rateCalculator.getNewRate(
                _deltaTime,
                _utilizationRate,
                _currentRateInfo.fullUtilizationRate
            );

            // Calculate interest accrued
            _results.interestEarned =
                (_deltaTime * _results.totalBorrow.amount * _results.newRate) /
                INTEREST_RATE_PRECISION;

            // Accrue interest (if any) and fees iff no overflow
            if (
                _results.interestEarned > 0 &&
                _results.interestEarned + _results.totalBorrow.amount <= type(uint128).max
            ) {
                // Increment totalBorrow by interestEarned
                _results.totalBorrow.amount += (_results.interestEarned).toUint128();
            }
        }
    }

    /// @notice Calculates the interest to be accrued and the new interest rate info. May update cached getConsolidatedEthFrxEthBalance values if stale
    /// @param _currentRateInfo The current rate info
    /// @return _results The results of the interest calculation
    function _calculateInterestWithStored(
        CurrentRateInfo memory _currentRateInfo
    ) internal view returns (InterestCalculationResults memory _results) {
        // // Get the potentially mutated utilization rate
        // uint256 _utilizationRate = getUtilization({ _forceLive: false, _updateCache: true });

        // Calculate the interest using the stored utilization rate
        return _calculateInterestCore(_currentRateInfo, utilizationStored);
    }

    // /// @notice Calculates the interest to be accrued and the new interest rate info. Will not update cached getConsolidatedEthFrxEthBalance values if stale
    // /// @param _currentRateInfo The current rate info
    // /// @return _results The results of the interest calculation
    // function _calculateInterestLiveView(
    //     CurrentRateInfo memory _currentRateInfo
    // ) internal view returns (InterestCalculationResults memory _results) {
    //     // Get the live utilization rate
    //     uint256 _utilizationRate = getUtilization({ _forceLive: true, _updateCache: false });

    //     // Calculate the interest
    //     return _calculateInterestCore(_currentRateInfo, _utilizationRate);
    // }

    /// @notice The ```_addInterest``` function is invoked prior to every external function and is used to accrue interest and update interest rate
    /// @dev Can only called once per block
    /// @param _skipRQReentrantCheck True to disable checking RedemptionQueue reentrancy. Only should be True for addInterestPrivileged calls
    /// @return _isInterestUpdated True if interest was calculated
    /// @return _interestEarned The amount of interest accrued by all borrowers
    /// @return _feesAmount The amount of fees paid to protocol
    /// @return _feesShare The amount of shares distributed to protocol
    /// @return _currentRateInfo The new rate info struct
    function _addInterest(
        bool _skipRQReentrantCheck
    )
        internal
        returns (
            bool _isInterestUpdated,
            uint256 _interestEarned,
            uint256 _feesAmount,
            uint256 _feesShare,
            CurrentRateInfo memory _currentRateInfo
        )
    {
        // Pull from storage and set default return values
        _currentRateInfo = currentRateInfo;

        // console.log("ADD INTEREST: PART 1");

        // Calc interest
        InterestCalculationResults memory _results = _calculateInterestWithStored(_currentRateInfo);

        // console.log("ADD INTEREST: PART 2");

        // Write return values only if interest was updated and calculated
        if (_results.isInterestUpdated) {
            // console.log("ADD INTEREST: PART 3");
            _isInterestUpdated = _results.isInterestUpdated;
            _interestEarned = _results.interestEarned;

            // Emit here so that we have access to the old values
            emit UpdateRate(
                _currentRateInfo.ratePerSec,
                _currentRateInfo.fullUtilizationRate,
                _results.newRate,
                _results.newFullUtilizationRate
            );
            emit AddInterest(_interestEarned, _results.newRate, _feesAmount, _feesShare);

            // Overwrite original values
            _currentRateInfo.ratePerSec = _results.newRate;
            _currentRateInfo.fullUtilizationRate = _results.newFullUtilizationRate;
            _currentRateInfo.lastTimestamp = uint64(block.timestamp);

            // console.log("ADD INTEREST: PART 4");

            // Effects: write to state
            currentRateInfo = _currentRateInfo;
            totalBorrow = _results.totalBorrow;
            interestAccrued += _interestEarned;
        }

        // Update the utilization
        utilizationStored = _getUtilizationInternal(true, true, _skipRQReentrantCheck);

        // console.log("ADD INTEREST: PART 5");
    }

    /// @notice Updates the utilizationStored
    function updateUtilization() public {
        utilizationStored = _getUtilizationInternal(true, true, true);
    }

    // ==============================================================================
    // Repay Functions
    // ==============================================================================

    /// @notice When a repayment is made for a validator pool
    /// @param _payorAddress The address paying, usually the validator pool
    /// @param _targetPoolAddress The validator pool getting repaid
    /// @param _repayAmount Amount of Eth being repaid
    event Repay(address indexed _payorAddress, address _targetPoolAddress, uint256 _repayAmount);

    /// @notice Repay a given validator pool with the provided msg.value Eth. Anyone can call and pay off on behalf of another.
    /// @param _targetPool The validator pool getting repaid
    function repay(address _targetPool) external payable nonReentrant {
        // Make sure the validator pool is initialized
        _requireValidatorPoolInitialized(_targetPool);

        // Accrue interest first
        _addInterest(false);

        // Do repay accounting for the target validator pool
        _repay(_targetPool, msg.value);

        // Give the repaid Ether to the Ether Router for investing
        etherRouter.depositEther{ value: msg.value }();

        // Update the stored utilization rate
        updateUtilization();
    }

    /// @notice Repay a given validator pool
    /// @param _targetPoolAddress The validator pool getting repaid
    /// @param _repayAmount Amount of Eth being repaid
    function _repay(address _targetPoolAddress, uint256 _repayAmount) internal {
        // Calculations
        (ValidatorPoolAccount memory _validatorPoolAccount, VaultAccount memory _totalBorrow) = _previewRepay(
            _targetPoolAddress,
            _repayAmount
        );

        // Effects
        validatorPoolAccounts[_targetPoolAddress] = _validatorPoolAccount;
        totalBorrow = _totalBorrow;

        emit Repay(msg.sender, _targetPoolAddress, _repayAmount);
    }

    /// @notice Preview repaying a validator pool
    /// @param _targetPoolAddress The validator pool getting repaid
    /// @param _repayAmount Amount of Eth being repaid
    /// @return _newValidatorPoolAccount The new state of the pool after the repayment
    /// @return _newTotalBorrow The new total amount of borrowed Eth after the repayment
    function _previewRepay(
        address _targetPoolAddress,
        uint256 _repayAmount
    )
        internal
        view
        returns (ValidatorPoolAccount memory _newValidatorPoolAccount, VaultAccount memory _newTotalBorrow)
    {
        // Copy dont mutate

        _newValidatorPoolAccount = validatorPoolAccounts[_targetPoolAddress];
        _newTotalBorrow = totalBorrow;

        // Calculate repaid share
        uint256 _sharesToRepay = _newTotalBorrow._toShares(_repayAmount, false);

        // Set values
        if (_sharesToRepay > _newValidatorPoolAccount.borrowShares) revert RepayingTooMuch();
        _newValidatorPoolAccount.borrowShares -= _sharesToRepay; // <<< HERE
        _newTotalBorrow.shares -= _sharesToRepay;
        _newTotalBorrow.amount -= _repayAmount;
    }

    // ==============================================================================
    // Borrow Functions
    // ==============================================================================

    /// @notice When the validator pool borrows from the lending pool
    /// @param _validatorPool The validator pool whose borrowing credit will be used
    /// @param _recipient The recipient of the Eth.
    /// @param _borrowAmount Amount of Eth being borrowed
    event Borrow(address indexed _validatorPool, address _recipient, uint256 _borrowAmount);

    /// @notice Borrow Eth from the lending pool (callable by a validator pool only)
    /// @param _recipient The recipient of the Eth
    /// @param _borrowAmount Amount of Eth being borrowed
    /// @dev The Eth is sourced from the EtherRouter
    function borrow(address payable _recipient, uint256 _borrowAmount) external nonReentrant {
        // Make sure the validator pool is initialized
        _requireValidatorPoolInitialized(msg.sender);

        // Accrue interest first
        _addInterest(false);

        // Do borrow accounting for the validator
        _borrow(msg.sender, _recipient, _borrowAmount, _borrowAmount);

        // Make sure the validator is still solvent after doing the accounting
        _requireValidatorPoolIsSolvent(msg.sender);

        // Pull Eth from the Ether Router and give it to the recipient (not necessarily the validator pool)
        etherRouter.requestEther(_recipient, _borrowAmount, false);

        // Update the stored utilization rate
        updateUtilization();
    }

    /// @notice Borrow Eth (internal)
    /// @param _validatorPoolAddress The validator pool address
    /// @param _recipient The recipient of the Eth
    /// @param _borrowAmount Amount of Eth being borrowed
    /// @param _allowanceAmount Validator pool's borrowing allowance
    function _borrow(
        address _validatorPoolAddress,
        address _recipient,
        uint256 _borrowAmount,
        uint256 _allowanceAmount
    ) internal {
        // Make sure the minimum borrow amount is met
        if (_borrowAmount < MINIMUM_BORROW_AMOUNT) revert MinimumBorrowAmount();

        // Calculations
        (ValidatorPoolAccount memory _validatorPoolAccount, VaultAccount memory _totalBorrow) = _previewBorrow(
            _validatorPoolAddress,
            _borrowAmount,
            _allowanceAmount
        );

        // Effects
        validatorPoolAccounts[_validatorPoolAddress] = _validatorPoolAccount;
        totalBorrow = _totalBorrow;

        // Make sure the validator is still solvent after doing the accounting
        // SKIPPED HERE as finalDepositValidator() would revert. Checked after the fact in external borrow()

        // Make sure the validator has not been liquidated
        _requireValidatorPoolNotLiquidated(msg.sender);

        emit Borrow(_validatorPoolAddress, _recipient, _borrowAmount);
    }

    /// @notice Preview borrowing some Eth
    /// @param _validatorPoolAddress The validator pool doing the borrowing
    /// @param _borrowAmount Amount of Eth being borrowed
    /// @return _newValidatorPoolAccount The new state of the pool after the borrow
    /// @return _newTotalBorrow The new total amount of borrowed Eth after the borrow
    function _previewBorrow(
        address _validatorPoolAddress,
        uint256 _borrowAmount,
        uint256 _allowanceAmount
    )
        internal
        view
        returns (ValidatorPoolAccount memory _newValidatorPoolAccount, VaultAccount memory _newTotalBorrow)
    {
        // Copy dont mutate
        _newValidatorPoolAccount = validatorPoolAccounts[_validatorPoolAddress];
        _newTotalBorrow = totalBorrow;

        // Set return values
        _newValidatorPoolAccount.borrowShares += _newTotalBorrow._toShares(_borrowAmount, true);
        if (_allowanceAmount.toUint128() > _newValidatorPoolAccount.borrowAllowance) revert AllowanceWouldBeNegative();
        else _newValidatorPoolAccount.borrowAllowance -= _allowanceAmount.toUint128();
        _newTotalBorrow.shares += _newTotalBorrow._toShares(_borrowAmount, true);
        _newTotalBorrow.amount += _borrowAmount;
    }

    // ==============================================================================
    // Deposit Functions
    // ==============================================================================

    /// @notice When a validator pool initially deposits
    /// @param _validatorPoolAddress Address of the validator pool
    /// @param _validatorPublicKey The public key of the validator
    /// @param _depositAmount The deposit amount of the validator
    event InitialDeposit(
        address payable indexed _validatorPoolAddress,
        bytes _validatorPublicKey,
        uint256 _depositAmount
    );

    /// @notice When a validator pool finalizes a deposit
    /// @param _validatorPoolAddress Address of the validator pool
    /// @param _validatorPublicKey The public key of the validator
    /// @param _poolSuppliedAmount The amount the validator pool supplied
    /// @param _borrowedAmount The amount borrowed in order to complete the deposit
    event DepositFinalized(
        address payable indexed _validatorPoolAddress,
        bytes _validatorPublicKey,
        uint256 _poolSuppliedAmount,
        uint96 _borrowedAmount
    );

    /// @notice Perform accounting for the first deposit for a given validator. May be either partial or full
    /// @param _validatorPublicKey Public key of the validator
    /// @param _depositAmount Amount being deposited
    function initialDepositValidator(bytes calldata _validatorPublicKey, uint256 _depositAmount) external nonReentrant {
        // Make sure the validator pool is initialized
        _requireValidatorPoolInitialized(msg.sender);

        // Accrue interest beforehand
        _addInterest(false);

        // Fetch the deposit info
        ValidatorDepositInfo storage _depositInfo = validatorDepositInfo[_validatorPublicKey];

        // Make sure the pubkey isn't already complete/finalized
        if (_depositInfo.wasFullDepositOrFinalized) revert PubKeyAlreadyFinalized();

        // Make sure the pubkey is either associated with the msg.sender validator pool, or not associated at all
        // Helps against validators altering data for other pubkeys as well as front-running
        if (!(_depositInfo.validatorPoolAddress == msg.sender || _depositInfo.validatorPoolAddress == address(0))) {
            revert ValidatorPoolKeyMismatch();
        }

        // Liquidated validator pools need to be emptied and abandoned, and should not be able to add any new validators
        // If you are mid-way through a partial deposit and liquidation happens, you will need to manually complete the 32 ETH
        // with an EOA or something, then exit
        _requireValidatorPoolNotLiquidated(msg.sender);

        // Update individual validator accounting
        _depositInfo.userDepositedEther += uint96(_depositAmount);

        // (Special case) If this came in as a full 32 Eth deposit all at once, or a final partial deposit with no borrow,
        // mark it as complete.
        if (_depositInfo.userDepositedEther == 32 ether) {
            // Verify that adding 1 validator would keep the validator pool solvent
            // You already accrued interest above so can leave false to save gas
            // _addlBorrowAmount is 0 since you came in full 32 all at once
            // Does not actually write these changes, just checks
            {
                (bool _wouldBeSolvent, uint256 _ttlBorrow, uint256 _ttlCredit) = wouldBeSolvent(
                    msg.sender,
                    false,
                    1,
                    0
                );
                if (!_wouldBeSolvent) revert ValidatorPoolIsNotSolventDetailed(_ttlBorrow, _ttlCredit);
            }

            // Mark the deposit as finalized
            _depositInfo.wasFullDepositOrFinalized = true;
        }

        // Mark the sender as the first validator so front-running attempts to alter the withdrawal address
        // will revert
        _depositInfo.validatorPoolAddress = msg.sender;

        // Make sure you are not depositing more than 32 Eth for this pubkey
        if (_depositInfo.userDepositedEther > 32 ether) revert CannotDepositMoreThan32Eth();

        // Update the stored utilization rate
        updateUtilization();

        emit InitialDeposit(payable(msg.sender), _validatorPublicKey, _depositAmount);
    }

    /// @notice Finalizes an incomplete ETH2 deposit made earlier, borrowing any remainder from the lending pool
    /// @param _validatorPublicKey Public key of the validator
    /// @param _withdrawalCredentials Withdrawal credentials for the validator
    /// @param _validatorSignature Signature from the validator
    /// @param _depositDataRoot Part of the deposit message
    function finalDepositValidator(
        bytes calldata _validatorPublicKey,
        bytes calldata _withdrawalCredentials,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot
    ) external nonReentrant {
        _requireValidatorInitialized(_validatorPublicKey);
        _requireValidatorApproved(_validatorPublicKey);
        _requireValidatorPoolInitialized(msg.sender);
        _requireAddressAssociatedWithPubkey(msg.sender, _validatorPublicKey);

        // Fetch the deposit info
        ValidatorDepositInfo memory _depositInfo = validatorDepositInfo[_validatorPublicKey];

        // Make sure the pubkey wasn't used yet
        if (_depositInfo.wasFullDepositOrFinalized) revert PubKeyAlreadyFinalized();

        // Calculate the borrow amount and make sure it is nonzero
        uint96 _borrowAmount = 32 ether - _depositInfo.userDepositedEther;
        if (_borrowAmount == 0) revert NoDepositToFinalize();

        // Update the deposit info
        _depositInfo.lendingPoolDepositedEther += _borrowAmount;
        _depositInfo.wasFullDepositOrFinalized = true;
        validatorDepositInfo[_validatorPublicKey] = _depositInfo;

        // Accrue interest beforehand
        _addInterest(false);

        // You can borrow even if you don't have credit, assuming you can still pay the interest rate
        // Your partial deposit (at least 8 ETH here for anon due to 24 ETH credit),
        // plus the fact that exited ETH is trapped in the validator pool (until debts are paid),
        // is essentially the collateral
        _borrow({
            _validatorPoolAddress: msg.sender,
            _recipient: msg.sender,
            _borrowAmount: uint256(_borrowAmount),
            _allowanceAmount: 0
        });

        // Request the needed Eth
        etherRouter.requestEther(payable(address(this)), uint256(_borrowAmount), false);

        // Complete the deposit
        ETH2_DEPOSIT_CONTRACT.deposit{ value: uint256(_borrowAmount) }(
            _validatorPublicKey,
            _withdrawalCredentials,
            _validatorSignature,
            _depositDataRoot
        );

        // Verify that accruing interest and adding 1 validator would keep the validator pool solvent
        // You already accrued interest above so can leave false to save gas
        // BorrowAmount already increased by _borrowAmount so no need to put it in wouldBeSolvent()
        // Does not actually write these changes, just checks
        {
            (bool _wouldBeSolvent, uint256 _ttlBorrow, uint256 _ttlCredit) = wouldBeSolvent(msg.sender, false, 1, 0);
            if (!_wouldBeSolvent) revert ValidatorPoolIsNotSolventDetailed(_ttlBorrow, _ttlCredit);
        }

        // // Increment the validator count, but NOT the borrow allowance. This prevents immediate liquidation.
        // // TODO: Check to make sure this cannot be manipulated to never allow a liquidation.
        // validatorPoolAccounts[msg.sender].validatorCount++;

        // Update the utilization
        updateUtilization();

        emit DepositFinalized(payable(msg.sender), _validatorPublicKey, _depositInfo.userDepositedEther, _borrowAmount);
    }

    // ==============================================================================
    // Withdraw Functions
    // ==============================================================================

    /// @notice When a validator pool withdraws ETH
    /// @param _validatorPoolAddress Address of the validator pool
    /// @param _endRecipient The ultimate recipient of the ETH
    /// @param _sentBackAmount Amount of Eth actually given back (requested - fee)
    /// @param _feeAmount Amount of Eth kept as the withdrawal fee (sent to the Ether Router)
    event WithdrawalRegistered(
        address payable indexed _validatorPoolAddress,
        address payable _endRecipient,
        uint256 _sentBackAmount,
        uint256 _feeAmount
    );

    /// @notice Registers that a validator pool is withdrawing and resets the borrowAllowance to 0 until the next beacon update.
    /// @param _endRecipient The ultimate recipient of the Eth. msg.sender (the validator pool) should get any ETH first
    /// @param _sentBackAmount Amount of Eth actually given back (requested - fee)
    /// @param _feeAmount Amount of Eth kept as the withdrawal fee (sent to the Ether Router)
    /// @dev This prevents syncing issues between when the ETH comes back from a Beacon Chain exit (dumped into the validator pool)
    /// and letting the validator pool borrow "for free" with lesser collateral (since there was just an exit)
    /// Once the Beacon Oracle actually registers the beacon chain exit, borrowAllowance
    /// will simply be (# validators) * (credit per validator) and the validator pool can borrow normally again
    /// with the new, correct number of total validators
    function registerWithdrawal(
        address payable _endRecipient,
        uint256 _sentBackAmount,
        uint256 _feeAmount
    ) external nonReentrant {
        _requireValidatorPoolInitialized(msg.sender);

        // Catch up the interest
        _addInterest(false);

        // Fetch the validator pool info
        ValidatorPoolAccount memory _validatorPoolAccount = validatorPoolAccounts[msg.sender];

        // Make sure debts have been paid off first
        if (_validatorPoolAccount.borrowShares == 0) {
            // 0 balance turns off borrowing until next oracle update, to prevent front running
            _validatorPoolAccount.borrowAllowance = 0;
        } else {
            revert BorrowBalanceMustBeZero();
        }

        // Mark this withdrawal timestamp. Important to prevent beacon frontrunning and other attacks
        _validatorPoolAccount.lastWithdrawal = uint32(block.timestamp);

        // Update the validator pool struct
        validatorPoolAccounts[msg.sender] = _validatorPoolAccount;

        // Update the utilization
        updateUtilization();

        emit WithdrawalRegistered(payable(msg.sender), _endRecipient, _sentBackAmount, _feeAmount);
    }

    // ==============================================================================
    // Liquidate Functions
    // ==============================================================================

    /// @notice When a validator pool is liquidated
    /// @param _validatorPoolAddress Address of the validator pool
    /// @param _amountToLiquidate Amount of Eth to liquidate
    event Liquidate(address indexed _validatorPoolAddress, uint256 _amountToLiquidate);

    /// @notice Liquidate a specified amount of Eth for a validator pool. Callable only by an allowed liquidator, the timelock, or the beacon oracle
    /// @param _validatorPoolAddress Address of the validator pool
    /// @param _amountToLiquidate Amount of Eth to liquidate
    /// @dev Marks the pool as "wasLiquidated = true", which will prevent new borrows and deposits
    function liquidate(address payable _validatorPoolAddress, uint256 _amountToLiquidate) external payable {
        // Make sure the caller is allowed
        _requireAddressCanLiquidate(msg.sender);

        // Accrue interest
        _addInterest(false);

        // Don't liquidate if the position is healthy
        if (isSolvent(_validatorPoolAddress)) {
            revert ValidatorPoolIsSolvent();
        }

        // Mark the validator pool as being in liquidation
        validatorPoolAccounts[_validatorPoolAddress].wasLiquidated = true;

        // Force the validator pool to pay back its loan
        ValidatorPool(_validatorPoolAddress).repayWithPoolAndValue{ value: 0 }(_amountToLiquidate);

        emit Liquidate(_validatorPoolAddress, _amountToLiquidate);
    }

    // ==============================================================================
    // ETH Handling
    // ==============================================================================

    /// @notice Allows contract to receive Eth
    receive() external payable {
        // Do nothing except take in the Eth
    }

    /// @notice When the lending pool sends stranded ETH to the Ether Router
    /// @param _amountRecovered Amount of ETH recovered
    event StrandedEthRecovered(uint256 _amountRecovered);

    /// @notice Pushes ETH back into the Ether Router, in case ETH gets stuck in this contract somehow
    /// @dev Under normal operations, ETH is only in this contract transiently.
    function recoverStrandedEth() external returns (uint256 _amountRecovered) {
        _requireSenderIsTimelock();

        // Save the balance before
        _amountRecovered = address(this).balance;

        // Give the ETH to the Ether Router
        (bool _success, ) = address(etherRouter).call{ value: _amountRecovered }("");
        require(_success, "ETH transfer failed (recoverStrandedEth ETH)");

        emit StrandedEthRecovered(_amountRecovered);
    }

    // ==============================================================================
    // Restricted Functions
    // ==============================================================================

    /// @notice When the interest rate calculator is set
    /// @param addr Address being set
    event InterestRateCalculatorSet(address addr);

    /// @notice Set the address for the interest rate calculator
    /// @param _calculatorAddress Address to set
    function setInterestRateCalculator(address _calculatorAddress) external {
        _requireSenderIsTimelock();

        // Set the status
        rateCalculator = IInterestRateCalculator(_calculatorAddress);

        emit InterestRateCalculatorSet(_calculatorAddress);
    }

    /// @notice When an address is allowed/disallowed to liquidate
    /// @param addr Address being set
    /// @param canLiquidate Whether it can liquidate or not
    event LiquidatorSet(address addr, bool canLiquidate);

    /// @notice Allow/disallow an address to perform liquidations
    /// @param _liquidatorAddress Address to set
    /// @param _canLiquidate Whether it can liquidate or not
    function setLiquidator(address _liquidatorAddress, bool _canLiquidate) external {
        _requireSenderIsTimelock();

        // Set the status
        isLiquidator[_liquidatorAddress] = _canLiquidate;

        emit LiquidatorSet(_liquidatorAddress, _canLiquidate);
    }

    /// @notice Change the Beacon Oracle address
    /// @param _newBeaconOracleAddress Beacon Oracle address
    function setBeaconOracleAddress(address _newBeaconOracleAddress) external {
        _requireSenderIsTimelock();
        _setBeaconOracle(_newBeaconOracleAddress);
    }

    /// @notice Change the Ether Router address
    /// @param _newEtherRouterAddress Ether Router address
    function setEtherRouterAddress(address payable _newEtherRouterAddress) external {
        _requireSenderIsTimelock();
        _setEtherRouter(_newEtherRouterAddress);
    }

    /// @notice Change the Redemption Queue address
    /// @param _newRedemptionQueue Redemption Queue address
    function setRedemptionQueueAddress(address payable _newRedemptionQueue) external {
        _requireSenderIsTimelock();
        _setFraxEtherRedemptionQueueV2(_newRedemptionQueue);
    }

    // ==============================================================================
    // Errors
    // ==============================================================================
    /// @notice If the borrow allowance trying to be set would be negative
    error AllowanceWouldBeNegative();

    /// @notice Cannot withdraw with nonzero borrow balance
    error BorrowBalanceMustBeZero();

    /// @notice Cannot exit pool
    error CannotExitPool();

    /// @notice When you are trying to deposit more than 32 ETH
    error CannotDepositMoreThan32Eth();

    /// @notice When certain supplied arrays parameters have differing lengths
    error InputArrayLengthMismatch();

    /// @notice Invalid validator pool
    error InvalidValidatorPool();

    /// @notice If you are trying to finalize an already completed deposit
    error NoDepositToFinalize();

    /// @notice If the caller is not allowed to liquidate
    error NotAllowedLiquidator();

    /// @notice If the sender is not the EtherRouter or RedemptionQueue
    error NotEtherRouterOrRedemptionQueue();

    /// @notice When you are trying to borrow less than the minimum amount
    error MinimumBorrowAmount();

    /// @notice Must repay debt first
    error MustRepayDebtFirst();

    /// @notice Prevent trying to cycle pubkeys and get more debt
    error PubKeyAlreadyFinalized();

    /// @notice When have a reentrant call
    error ReentrancyStatusIsTrue();

    /// @notice When you try to repay too much
    error RepayingTooMuch();

    /// @notice Validator is not approved
    error ValidatorIsNotApprovedLP();

    /// @notice Validator is not initialized
    error ValidatorIsNotInitialized();

    /// @notice Supplied pubkey not associated with the supplied validator pool address
    error ValidatorPoolKeyMismatch();

    /// @notice Validator pool is liquidated
    error ValidatorPoolWasLiquidated();

    /// @notice Validator pool is not solvent
    error ValidatorPoolIsNotSolvent();

    /// @notice Validator pool is not solvent (detailed)
    error ValidatorPoolIsNotSolventDetailed(uint256 _ttlBorrow, uint256 _ttlCredit);

    /// @notice Validator pool is solvent
    error ValidatorPoolIsSolvent();

    /// @notice Withdrawal timestamp mismatch
    error WithdrawalTimestampMismatch(uint32 _suppliedTimestamp, uint32 _actualTimestamp);
}
