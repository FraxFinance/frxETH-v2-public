// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ==================== FraxEtherRedemptionQueueV2 ====================
// ====================================================================
// Users wishing to exchange frxETH for ETH 1-to-1 will need to deposit their frxETH and wait to redeem it.
// When they do the deposit, they get an NFT with a maturity time as well as an amount.
// V2: Used in tandem with frxETH V2's Lending Pool

// Frax Finance: https://github.com/FraxFinance

// Primary Author
// Drake Evans: https://github.com/DrakeEvans
// Travis Moore: https://github.com/FortisFortuna

// Reviewer(s) / Contributor(s)
// Dennis: https://github.com/denett
// Sam Kazemian: https://github.com/samkazemian

import {
    EtherRouter,
    FraxEtherRedemptionQueueCore,
    FraxEtherRedemptionQueueCoreParams,
    LendingPool,
    SafeCast
} from "./FraxEtherRedemptionQueueCore.sol";

contract FraxEtherRedemptionQueueV2 is FraxEtherRedemptionQueueCore {
    using SafeCast for *;

    constructor(
        FraxEtherRedemptionQueueCoreParams memory _params,
        address payable _etherRouterAddress
    ) FraxEtherRedemptionQueueCore(_params, _etherRouterAddress) {}

    // ==============================================================================
    // FraxEtherRedemptionQueue overrides
    // ==============================================================================

    /// @notice When someone redeems their NFT for ETH, burning it if it is a full redemption
    /// @param nftId the if of the nft redeemed
    /// @param sender the msg.sender
    /// @param recipient the recipient of the ether
    /// @param feeAmt the amount fee kept
    /// @param amountToRedeemer the amount of ether sent to the recipient
    /// @param isPartial If it was a partial redemption
    event NftTicketRedemption(
        uint256 indexed nftId,
        address indexed sender,
        address indexed recipient,
        uint120 feeAmt,
        uint120 amountToRedeemer,
        bool isPartial
    );

    /// @notice Fully redeems a FrxETHRedemptionTicket NFT for ETH. Must have reached the maturity date first.
    /// @param _nftId The ID of the NFT
    /// @param _recipient The recipient of the redeemed ETH
    function fullRedeemNft(
        uint256 _nftId,
        address payable _recipient
    ) external nonReentrant returns (uint120 _amountEtherPaidToUser, uint120 _redemptionFeeAmount) {
        // Add interest
        LendingPool(etherRouter.lendingPool()).addInterestPrivileged(false);

        // Burn the NFT and update the state
        RedemptionQueueItem memory _redemptionQueueItem = _handleRedemptionTicketNftPre(_nftId, 0);

        // Calculations: redemption fee
        _redemptionFeeAmount = ((uint256(_redemptionQueueItem.amount) * uint256(_redemptionQueueItem.redemptionFee)) /
            FEE_PRECISION).toUint120();

        // Calculations: amount of ETH owed to the user
        _amountEtherPaidToUser = _redemptionQueueItem.amount - _redemptionFeeAmount;

        // Calculations: increment unclaimed fees by the redemption fee taken
        redemptionQueueAccounting.unclaimedFees += _redemptionFeeAmount;

        // Calculations: decrement pending fees by the redemption fee taken
        redemptionQueueAccounting.pendingFees -= _redemptionFeeAmount;

        // Effects: Burn frxEth 1:1. Unburnt amount stays as the fee
        FRX_ETH.burn(_amountEtherPaidToUser);

        // If you don't have enough ETH in this contract, pull in the missing amount from the Ether Router
        if (_amountEtherPaidToUser > payable(this).balance) {
            // See how much ETH you actually are missing
            uint256 _missingEth = _amountEtherPaidToUser - payable(this).balance;

            // Pull only what is needed and not the entire RQ shortage
            // If there is still not enough, the entire fullRedeemNft function will revert and the user should try partialRedeemNft
            etherRouter.requestEther(payable(this), _missingEth, true);
        }

        // Effects: Subtract the amount from total liabilities
        // Uses _redemptionQueueItem.amount vs _amountEtherPaidToUser here
        redemptionQueueAccounting.etherLiabilities -= _redemptionQueueItem.amount;

        // Transfer ETH to recipient, minus the fee, if any
        (bool sent, ) = payable(_recipient).call{ value: _amountEtherPaidToUser }("");
        if (!sent) revert InvalidEthTransfer();

        // Update the stored utilization rate
        LendingPool(etherRouter.lendingPool()).updateUtilization();

        emit NftTicketRedemption({
            nftId: _nftId,
            sender: msg.sender,
            recipient: _recipient,
            feeAmt: _redemptionFeeAmount,
            amountToRedeemer: _amountEtherPaidToUser,
            isPartial: false
        });
    }

    /// @notice Partially redeems a FrxETHRedemptionTicket NFT for ETH. Must have reached the maturity date first.
    /// @param _nftId The ID of the NFT
    /// @param _recipient The recipient of the redeemed ETH
    /// @param _redeemAmt The amount you want to redeem
    function partialRedeemNft(uint256 _nftId, address payable _recipient, uint120 _redeemAmt) external nonReentrant {
        // 0 is reserved for full redeems only
        if (_redeemAmt == 0) revert CannotRedeemZero();

        // Add interest
        LendingPool(etherRouter.lendingPool()).addInterestPrivileged(false);

        // Modify the NFT and update the state
        RedemptionQueueItem memory _redemptionQueueItem = _handleRedemptionTicketNftPre(_nftId, _redeemAmt);

        // Calculations: redemption fee
        uint120 _redemptionFeeAmount = ((uint256(_redeemAmt) * uint256(_redemptionQueueItem.redemptionFee)) /
            FEE_PRECISION).toUint120();

        // Calculations: amount of ETH owed to the user
        uint120 _amountEtherOwedToUser = _redeemAmt - _redemptionFeeAmount;

        // Calculations: increment unclaimed fees by the redemption fee taken
        redemptionQueueAccounting.unclaimedFees += _redemptionFeeAmount;

        // Calculations: decrement pending fees by the redemption fee taken
        redemptionQueueAccounting.pendingFees -= _redemptionFeeAmount;

        // Effects: Burn frxEth 1:1. Unburnt amount stays as the fee
        FRX_ETH.burn(_amountEtherOwedToUser);

        // Get the ETH
        // If you don't have enough ETH in this contract, pull in the missing amount from the Ether Router
        if (_amountEtherOwedToUser > payable(this).balance) {
            // See how much ETH you actually are missing
            uint256 _missingEth = _amountEtherOwedToUser - payable(this).balance;

            // Pull only what is needed and not the entire RQ shortage
            // If there is still not enough, the entire partialRedeemNft function will revert here and the user should resubmit with a lower _redeemAmt
            etherRouter.requestEther(payable(this), _missingEth, true);
        }

        // Effects: Subtract the amount from total liabilities
        // Uses _redeemAmt vs _amountEtherOwedToUser here
        redemptionQueueAccounting.etherLiabilities -= _redeemAmt;

        // Transfer ETH to recipient, minus the fee, if any
        (bool sent, ) = payable(_recipient).call{ value: _amountEtherOwedToUser }("");
        if (!sent) revert InvalidEthTransfer();

        // Update the stored utilization rate
        LendingPool(etherRouter.lendingPool()).updateUtilization();

        emit NftTicketRedemption({
            nftId: _nftId,
            sender: msg.sender,
            recipient: _recipient,
            feeAmt: _redemptionFeeAmount,
            amountToRedeemer: _amountEtherOwedToUser,
            isPartial: true
        });
    }

    // ====================================
    // Errors
    // ====================================

    /// @notice Cannot redeem zero
    error CannotRedeemZero();
}
