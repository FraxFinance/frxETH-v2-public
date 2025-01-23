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
// =========================== ValidatorPool ==========================
// ====================================================================
// Deposits ETH to earn collateral credit for borrowing on the LendingPool
// Controlled by the depositor

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Drake Evans: https://github.com/DrakeEvans
// Travis Moore: https://github.com/FortisFortuna

// Reviewer(s) / Contributor(s)
// Dennis: https://github.com/denett
// Sam Kazemian: https://github.com/samkazemian

import { PublicReentrancyGuard } from "frax-std/access-control/v2/PublicReentrancyGuard.sol";
import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Timelock2Step } from "frax-std/access-control/v2/Timelock2Step.sol";
import { ILendingPool } from "./lending-pool/interfaces/ILendingPool.sol";
import { IDepositContract } from "./interfaces/IDepositContract.sol";

// import { console } from "frax-std/FraxTest.sol";
// import { Logger } from "frax-std/Logger.sol";

/// @title Deposits ETH to earn collateral credit for borrowing on the LendingPool
/// @author Frax Finance
/// @notice Controlled by the depositor
contract ValidatorPool is Ownable2Step, PublicReentrancyGuard {
    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    /// @notice Track amount of ETH sent to deposit contract, by pubkey
    mapping(bytes validatorPubKey => uint256 amtDeposited) public depositedAmts;

    /// @notice Withdrawal creds for the validators
    bytes32 public immutable withdrawalCredentials;

    /// @notice The Eth lending pool
    ILendingPool public immutable lendingPool;

    /// @notice The official Eth2 deposit contract
    IDepositContract public immutable ETH2_DEPOSIT_CONTRACT;

    /// @notice Constructor
    /// @param _ownerAddress The owner of the validator pool
    /// @param _lendingPoolAddress Address of the lending pool
    /// @param _eth2DepositAddress Address of the Eth2 deposit contract
    constructor(
        address _ownerAddress,
        address payable _lendingPoolAddress,
        address payable _eth2DepositAddress
    ) Ownable(_ownerAddress) {
        lendingPool = ILendingPool(_lendingPoolAddress);
        bytes32 _bitMask = 0x0100000000000000000000000000000000000000000000000000000000000000;
        bytes32 _address = bytes32(uint256(uint160(address(this))));
        withdrawalCredentials = _bitMask | _address;

        ETH2_DEPOSIT_CONTRACT = IDepositContract(_eth2DepositAddress);
    }

    // ==============================================================================
    // Eth Handling
    // ==============================================================================

    /// @notice Accept Eth
    receive() external payable {}

    // ==============================================================================
    // Check Functions
    // ==============================================================================

    /// @notice Make sure the sender is the validator pool owner
    function _requireSenderIsOwner() internal view {
        if (msg.sender != owner()) revert SenderMustBeOwner();
    }

    /// @notice Make sure the sender is either the validator pool owner or the owner
    function _requireSenderIsOwnerOrLendingPool() internal view {
        if (msg.sender == owner() || msg.sender == address(lendingPool)) {
            // Do nothing
        } else {
            revert SenderMustBeOwnerOrLendingPool();
        }
    }

    /// @notice Make sure the supplied pubkey has been used (deposited to) by this validator before
    /// @param _pubKey The pubkey you want to test
    function _requireValidatorIsUsed(bytes memory _pubKey) internal view {
        if (depositedAmts[_pubKey] == 0) revert ValidatorIsNotUsed();
    }

    // ==============================================================================
    // View Functions
    // ==============================================================================
    /// @notice Get the amount of Eth borrowed by this validator pool (live)
    /// @param _amtEthBorrowed The amount of ETH this pool has borrowed
    function getAmountBorrowed() public view returns (uint256 _amtEthBorrowed) {
        // Calculate the amount borrowed after adding interest
        (, _amtEthBorrowed, ) = lendingPool.wouldBeSolvent(address(this), true, 0, 0);
    }

    /// @notice Get the amount of Eth borrowed by this validator pool. May be stale if LendingPool.addInterest has not been called for a while
    /// @return _amtEthBorrowed The amount of ETH this pool has borrowed
    /// @return _sharesBorrowed The amount of shares this pool has borrowed
    function getAmountAndSharesBorrowedStored() public view returns (uint256 _amtEthBorrowed, uint256 _sharesBorrowed) {
        // Fetch the borrowShares
        (, , , , , , _sharesBorrowed) = lendingPool.validatorPoolAccounts(address(this));

        // Return the amount of ETH borrowed
        _amtEthBorrowed = lendingPool.toBorrowAmountOptionalRoundUp(_sharesBorrowed, true);
    }

    // ==============================================================================
    // Deposit Functions
    // ==============================================================================

    /// @notice When the validator pool makes a deposit
    /// @param _validatorPool The validator pool making the deposit
    /// @param _pubkey Public key of the validator.
    /// @param _amount Amount of Eth being deposited
    /// @dev The ETH2 emits a Deposit event, but this is for Beacon Oracle / offchain tracking help
    event ValidatorPoolDeposit(address _validatorPool, bytes _pubkey, uint256 _amount);

    /// @notice Deposit a specified amount of ETH into the ETH2 deposit contract
    /// @param pubkey Public key of the validator
    /// @param signature Signature from the validator
    /// @param _depositDataRoot Part of the deposit message
    /// @param _depositAmount The amount to deposit
    function _deposit(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 _depositDataRoot,
        uint256 _depositAmount
    ) internal {
        bytes memory _withdrawalCredentials = abi.encodePacked(withdrawalCredentials);
        // Deposit one batch
        ETH2_DEPOSIT_CONTRACT.deposit{ value: _depositAmount }(
            pubkey,
            _withdrawalCredentials,
            signature,
            _depositDataRoot
        );

        // Increment the amount deposited
        depositedAmts[pubkey] += _depositAmount;

        emit ValidatorPoolDeposit(address(this), pubkey, _depositAmount);
    }

    // /// @notice Deposit 32 ETH into the ETH2 deposit contract
    // /// @param pubkey Public key of the validator
    // /// @param signature Signature from the validator
    // /// @param _depositDataRoot Part of the deposit message
    // function fullDeposit(
    //     bytes calldata pubkey,
    //     bytes calldata signature,
    //     bytes32 _depositDataRoot
    // ) external payable nonReentrant {
    //     _requireSenderIsOwner();

    //     // Deposit the ether in the ETH 2.0 deposit contract
    //     // Use this contract's stored withdrawal_credentials
    //     require((msg.value + address(this).balance) >= 32 ether, "Need 32 ETH");
    //     _deposit(pubkey, signature, _depositDataRoot, 32 ether);

    //     lendingPool.initialDepositValidator(pubkey, 32 ether);
    // }

    // /// @notice Deposit a partial amount of ETH into the ETH2 deposit contract
    // /// @param _validatorPublicKey Public key of the validator
    // /// @param _validatorSignature Signature from the validator
    // /// @param _depositDataRoot Part of the deposit message
    // /// @dev This is not a full deposit and will have to be completed later
    // function partialDeposit(
    //     bytes calldata _validatorPublicKey,
    //     bytes calldata _validatorSignature,
    //     bytes32 _depositDataRoot
    // ) external payable nonReentrant {
    //     _requireSenderIsOwner();

    //     // Deposit the ether in the ETH 2.0 deposit contract
    //     require((msg.value + address(this).balance) >= 8 ether, "Need 8 ETH");
    //     _deposit(_validatorPublicKey, _validatorSignature, _depositDataRoot, 8 ether);

    //     lendingPool.initialDepositValidator(_validatorPublicKey, 8 ether);
    // }

    /// @notice Deposit ETH into the ETH2 deposit contract. Only msg.value / sender funds can be used
    /// @param _validatorPublicKey Public key of the validator
    /// @param _validatorSignature Signature from the validator
    /// @param _depositDataRoot Part of the deposit message
    /// @dev Forcing msg.value only prevents users from seeding an external validator and depositing exited funds into there,
    /// which they can then further exit and steal
    function deposit(
        bytes calldata _validatorPublicKey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot
    ) external payable nonReentrant {
        _requireSenderIsOwner();

        // Make sure an integer amount of 1 Eth is being deposited
        // Avoids a case where < 1 Eth is borrowed to finalize a deposit, only to have it fail at the Eth 2.0 contract
        // Also avoids the 1 gwei minimum increment issue at the Eth 2.0 contract
        if ((msg.value % (1 ether)) != 0) revert MustBeIntegerMultipleOf1Eth();

        // Deposit the ether in the ETH 2.0 deposit contract
        // This will reject if the deposit amount isn't at least 1 ETH + a multiple of 1 gwei
        _deposit(_validatorPublicKey, _validatorSignature, _depositDataRoot, msg.value);

        // Register the deposit with the lending pool
        // Will revert if you go over 32 ETH
        lendingPool.initialDepositValidator(_validatorPublicKey, msg.value);
    }

    /// @notice Finalizes an incomplete ETH2 deposit made earlier, borrowing any remainder from the lending pool
    /// @param _validatorPublicKey Public key of the validator
    /// @param _validatorSignature Signature from the validator
    /// @param _depositDataRoot Part of the deposit message
    /// @dev You don't necessarily need credit here because the collateral is secured by the exit message. You pay the interest rate.
    /// Not part of the normal borrow credit system, this is separate.
    /// Useful for leveraging your position if the borrow rate is low enough
    function requestFinalDeposit(
        bytes calldata _validatorPublicKey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot
    ) external nonReentrant {
        _requireSenderIsOwner();
        _requireValidatorIsUsed(_validatorPublicKey);

        // Reverts if deposits not allowed or Validator Pool does not have enough credit/allowance
        lendingPool.finalDepositValidator(
            _validatorPublicKey,
            abi.encodePacked(withdrawalCredentials),
            _validatorSignature,
            _depositDataRoot
        );
    }

    // ==============================================================================
    // Borrow Functions
    // ==============================================================================

    /// @notice Borrow ETH from the Lending Pool and give to the recipient
    /// @param _recipient Recipient of the borrowed funds
    /// @param _borrowAmount Amount being borrowed
    function borrow(address payable _recipient, uint256 _borrowAmount) public nonReentrant {
        _requireSenderIsOwner();

        // Borrow ETH from the Lending Pool and give to the recipient
        lendingPool.borrow(_recipient, _borrowAmount);
    }

    // ==============================================================================
    // Repay Functions
    // ==============================================================================

    // /// @notice Repay a loan with sender's msg.value ETH
    // /// @dev May have a Zeno's paradox situation where repay -> dust accumulates interest -> repay -> dustier dust accumulates interest
    // /// @dev So use repayAllWithPoolAndValue
    // function repayWithValue() external payable nonReentrant {
    //     // On liquidation lending pool will call this function to repay the debt
    //     _requireSenderIsOwnerOrLendingPool();

    //     // Take ETH from the sender and give to the Lending Pool to repay any loans
    //     lendingPool.repay{ value: msg.value }(address(this));
    // }

    // /// @notice Repay a loan, specifing the ETH amount using the contract's own ETH
    // /// @param _repayAmount Amount of ETH to repay
    // /// @dev May have a Zeno's paradox situation where repay -> dust accumulates interest -> repay -> dustier dust accumulates interest
    // /// @dev So use repayAllWithPoolAndValue
    // function repayAmount(uint256 _repayAmount) external nonReentrant {
    //     // On liquidation lending pool will call this function to repay the debt
    //     _requireSenderIsOwnerOrLendingPool();

    //     // Take ETH from this contract and give to the Lending Pool to repay any loans
    //     lendingPool.repay{ value: _repayAmount }(address(this));
    // }

    /// @notice Repay a loan, specifing the shares amount. Uses this contract's own ETH
    /// @param _repayShares Amount of shares to repay
    function repayShares(uint256 _repayShares) external nonReentrant {
        _requireSenderIsOwnerOrLendingPool();
        uint256 _repayAmount = lendingPool.toBorrowAmountOptionalRoundUp(_repayShares, true);
        lendingPool.repay{ value: _repayAmount }(address(this));
    }

    /// @notice Repay a loan using pool ETH, msg.value ETH, or both. Will revert if overpaying
    /// @param _vPoolAmountToUse Amount of validator pool ETH to use
    /// @dev May have a Zeno's paradox situation where repay -> dust accumulates interest -> repay -> dustier dust accumulates interest
    /// @dev So use repayAllWithPoolAndValue in that case
    function repayWithPoolAndValue(uint256 _vPoolAmountToUse) external payable nonReentrant {
        // On liquidation lending pool will call this function to repay the debt
        _requireSenderIsOwnerOrLendingPool();

        // Take ETH from this contract and msg.sender and give it to the Lending Pool to repay any loans
        lendingPool.repay{ value: _vPoolAmountToUse + msg.value }(address(this));
    }

    /// @notice Repay an ENTIRE loan using pool ETH, msg.value ETH, or both. Will revert if overpaying msg.value
    function repayAllWithPoolAndValue() external payable nonReentrant {
        // On liquidation lending pool will call this function to repay the debt
        _requireSenderIsOwnerOrLendingPool();

        // Calculate the true amount borrowed after adding interest
        (, uint256 _remainingBorrow, ) = lendingPool.wouldBeSolvent(address(this), true, 0, 0);

        // Repay with msg.value first. Will revert if overpaying
        if (msg.value > 0) {
            // Repay with all of the msg.value provided
            lendingPool.repay{ value: msg.value }(address(this));

            // Update _remainingBorrow
            _remainingBorrow -= msg.value;
        }

        // Repay any leftover with VP ETH. Will revert if insufficient.
        lendingPool.repay{ value: _remainingBorrow }(address(this));
    }

    // ==============================================================================
    // Withdraw Functions
    // ==============================================================================

    /// @notice Withdraw ETH from this contract. Must not have any outstanding loans.
    /// @param _recipient Recipient of the ETH
    /// @param _withdrawAmount Amount to withdraw
    /// @dev Even assuming the exited ETH is dumped back in here before the Beacon Oracle registers that, and if the user
    /// tried to borrow again, their collateral would be this exited ETH now that is "trapped" until the loan is repaid,
    /// rather than being in a validator, so it is still ok. borrow() would increase borrowShares, which would still need to be paid off first
    function withdraw(address payable _recipient, uint256 _withdrawAmount) external nonReentrant {
        _requireSenderIsOwner();

        // Calculate the withdrawal fee amount
        uint256 _withdrawalFeeAmt = (_withdrawAmount * lendingPool.vPoolWithdrawalFee()) / 1e6;
        uint256 _postFeeAmt = _withdrawAmount - _withdrawalFeeAmt;

        // Register the withdrawal on the lending pool
        // Will revert unless all debts are paid off first
        lendingPool.registerWithdrawal(_recipient, _postFeeAmt, _withdrawalFeeAmt);

        // Give the fee to the Ether Router first, to cover any fees/slippage from LP movements
        (bool sent, ) = payable(lendingPool.etherRouter()).call{ value: _withdrawalFeeAmt }("");
        if (!sent) revert InvalidEthTransfer();

        // Withdraw ETH from this validator pool and give to the recipient
        (sent, ) = payable(_recipient).call{ value: _postFeeAmt }("");
        if (!sent) revert InvalidEthTransfer();
    }

    // ==============================================================================
    // Errors
    // ==============================================================================

    /// @notice External contract should not have been entered previously
    error ExternalContractAlreadyEntered();

    /// @notice Invalid ETH transfer during recoverEther
    error InvalidEthTransfer();

    /// @notice When you are trying to deposit a non integer multiple of 1 ether
    error MustBeIntegerMultipleOf1Eth();

    /// @notice Sender must be the lending pool
    error SenderMustBeLendingPool();

    /// @notice Sender must be the owner
    error SenderMustBeOwner();

    /// @notice Sender must be the owner or the lendingPool
    error SenderMustBeOwnerOrLendingPool();

    /// @notice Validator is not approved
    error ValidatorIsNotUsed();

    /// @notice Wrong Ether deposit amount
    error WrongEthDepositAmount();
}
