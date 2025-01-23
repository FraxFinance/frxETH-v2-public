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
// ===================== FraxEtherRedemptionQueue =====================
// ====================================================================
// Users wishing to exchange frxETH for ETH 1-to-1 will need to deposit their frxETH and wait to redeem it.
// When they do the deposit, they get an NFT with a maturity time as well as an amount.

// Frax Finance: https://github.com/FraxFinance

// Primary Author
// Drake Evans: https://github.com/DrakeEvans
// Travis Moore: https://github.com/FortisFortuna

// Reviewer(s) / Contributor(s)
// Dennis: https://github.com/denett
// Sam Kazemian: https://github.com/samkazemian

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PublicReentrancyGuard } from "frax-std/access-control/v2/PublicReentrancyGuard.sol";
import { LendingPool } from "src/contracts/lending-pool/LendingPool.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { EtherRouter } from "../ether-router/EtherRouter.sol";
import { Timelock2Step } from "frax-std/access-control/v2/Timelock2Step.sol";
import { OperatorRole } from "frax-std/access-control/v2/OperatorRole.sol";
import { IFrxEth } from "./interfaces/IFrxEth.sol";
import { ISfrxEth } from "./interfaces/ISfrxEth.sol";

/// @notice Used by the constructor
/// @param timelockAddress Address of the timelock, which the main owner of the this contract
/// @param operatorAddress Address of the operator, which does other tasks
/// @param frxEthAddress Address of frxEth Erc20
/// @param sfrxEthAddress Address of sfrxEth Erc20
/// @param initialQueueLengthSecondss Initial length of the queue, in seconds
struct FraxEtherRedemptionQueueCoreParams {
    address timelockAddress;
    address operatorAddress;
    address frxEthAddress;
    address sfrxEthAddress;
    uint32 initialQueueLengthSeconds;
}

contract FraxEtherRedemptionQueueCore is ERC721, Timelock2Step, OperatorRole, PublicReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    // ==============================================================================
    // Storage
    // ==============================================================================

    // Contracts
    // ================
    /// @notice The Ether Router
    EtherRouter public immutable etherRouter;

    // Tokens
    // ================
    /// @notice The frxETH token
    IFrxEth public immutable FRX_ETH;

    /// @notice The sfrxETH token
    ISfrxEth public immutable SFRX_ETH;

    // Version
    // ================
    string public version = "1.0.2";

    // Queue-Related
    // ================
    /// @notice State of Frax's frxETH redemption queue
    /// @param etherLiabilities How much ETH is currently under request to be redeemed
    /// @param nextNftId Autoincrement for the NFT id
    /// @param queueLengthSecs Current wait time (in seconds) a new redeemer would have. Should be close to Beacon.
    /// @param redemptionFee Redemption fee given as a percentage with 1e6 precision
    /// @param ttlEthRequested Cumulative total amount of ETH requested for redemption
    /// @param ttlEthServed Cumulative total amount of ETH and/or frxETH actually sent back to redeemers. ETH in the case of a mature redeem
    struct RedemptionQueueState {
        uint64 nextNftId;
        uint64 queueLengthSecs;
        uint64 redemptionFee;
        uint120 ttlEthRequested;
        uint120 ttlEthServed;
    }

    /// @notice State of Frax's frxETH redemption queue
    RedemptionQueueState public redemptionQueueState;

    /// @param etherLiabilities How much ETH would need to be paid out if every NFT holder could claim immediately
    /// @param unclaimedFees Earned fees that the protocol has not collected yet
    /// @param pendingFees Amount of fees expected if all outstanding NFTs were redeemed fully
    struct RedemptionQueueAccounting {
        uint120 etherLiabilities;
        uint120 unclaimedFees;
        uint120 pendingFees;
    }

    /// @notice Accounting of Frax's frxETH redemption queue
    RedemptionQueueAccounting public redemptionQueueAccounting;

    /// @notice Information about a user's redemption ticket NFT
    mapping(uint256 nftId => RedemptionQueueItem) public nftInformation;

    /// @notice The ```RedemptionQueueItem``` struct provides metadata information about each Nft
    /// @param hasBeenRedeemed boolean for whether the NFT has been redeemed
    /// @param amount How much ETH is claimable
    /// @param maturity Unix timestamp when they can claim their ETH
    /// @param redemptionFee redemptionFee (E6) at time of NFT mint
    /// @param ttlEthRequestedSnapshot ttlEthServed + (available ETH) must be >= ttlEthRequestedSnapshot. ttlEthRequestedSnapshot is redemptionQueueState.ttlEthRequested + (the amount of ETH you put in your redemption request) at the time of the enterRedemptionQueue call
    struct RedemptionQueueItem {
        bool hasBeenRedeemed;
        uint64 maturity;
        uint120 amount;
        uint64 redemptionFee;
        uint120 ttlEthRequestedSnapshot;
    }

    /// @notice Maximum queue length the operator can set, given in seconds
    uint256 public maxQueueLengthSeconds = 100 days;

    /// @notice Precision of the redemption fee
    uint64 public constant FEE_PRECISION = 1e6;

    /// @notice Maximum settable fee for redeeming
    uint64 public constant MAX_REDEMPTION_FEE = 20_000; // 2% max

    /// @notice Maximum amount of frxETH that can be used to create an NFT
    /// @dev If it were too large, the user could get stuck for a while until loans get paid back, or more people deposit ETH for frxETH
    uint120 public constant MAX_FRXETH_PER_NFT = 1000 ether;

    /// @notice The fee recipient for various fees
    address public feeRecipient;

    // ==============================================================================
    // Constructor
    // ==============================================================================

    /// @notice Constructor
    /// @param _params The contructor FraxEtherRedemptionQueueCoreParams params
    constructor(
        FraxEtherRedemptionQueueCoreParams memory _params,
        address payable _etherRouterAddress
    )
        payable
        ERC721("FrxETH Redemption Queue Ticket V2", "FrxETHRedemptionTicketV2")
        OperatorRole(_params.operatorAddress)
        Timelock2Step(_params.timelockAddress)
    {
        // Initialize some state variables
        if (_params.initialQueueLengthSeconds > maxQueueLengthSeconds) {
            revert ExceedsMaxQueueLengthSecs(_params.initialQueueLengthSeconds, maxQueueLengthSeconds);
        }
        redemptionQueueState.queueLengthSecs = _params.initialQueueLengthSeconds;
        FRX_ETH = IFrxEth(_params.frxEthAddress);
        SFRX_ETH = ISfrxEth(_params.sfrxEthAddress);
        etherRouter = EtherRouter(_etherRouterAddress);

        // Default the fee recipient to the operator (can be changed later)
        feeRecipient = _params.operatorAddress;
    }

    /// @notice Allows contract to receive Eth
    receive() external payable {
        // Do nothing except take in the Eth
    }

    // =============================================================================================
    // Configurations / Privileged functions
    // =============================================================================================

    /// @notice When the accrued redemption fees are collected
    /// @param recipient The address to receive the fees
    /// @param collectAmount Amount of fees collected
    event CollectRedemptionFees(address recipient, uint120 collectAmount);

    /// @notice Collect all redemption fees (in frxETH)
    function collectAllRedemptionFees() external returns (uint120 _collectedAmount) {
        // Call the internal function
        return _collectRedemptionFees(0, true);
    }

    /// @notice Collect a specified amount of redemption fees (in frxETH)
    /// @param _collectAmount Amount of frxEth to collect
    function collectRedemptionFees(uint120 _collectAmount) external returns (uint120 _collectedAmount) {
        // Call the internal function
        _collectRedemptionFees(_collectAmount, false);
    }

    /// @notice Collect redemption fees (in frxETH). Fees go to the fee recipient address
    /// @param _collectAmount Amount of frxEth to collect.
    /// @param _collectAllOverride If true, _collectAmount is overriden with redemptionQueueAccounting.unclaimedFees and all available fees are collected
    function _collectRedemptionFees(
        uint120 _collectAmount,
        bool _collectAllOverride
    ) internal returns (uint120 _collectedAmount) {
        // Make sure the sender is either the timelock, operator, or fee recipient
        _requireIsTimelockOperatorOrFeeRecipient();

        // Get the amount of unclaimed fees
        uint120 _unclaimedFees = redemptionQueueAccounting.unclaimedFees;

        // See if there is the override
        if (_collectAllOverride) _collectAmount = _unclaimedFees;

        // Make sure you are not taking too much
        if (_collectAmount > _unclaimedFees) revert ExceedsCollectedFees(_collectAmount, _unclaimedFees);

        // Decrement the unclaimed fee amount
        redemptionQueueAccounting.unclaimedFees -= _collectAmount;

        // Interactions: Transfer frxEth fees to the recipient
        IERC20(address(FRX_ETH)).safeTransfer({ to: feeRecipient, value: _collectAmount });

        emit CollectRedemptionFees({ recipient: feeRecipient, collectAmount: _collectAmount });

        return _collectAmount;
    }

    /// @notice When the timelock or operator recovers ERC20 tokens mistakenly sent here
    /// @param recipient Address of the recipient
    /// @param token Address of the erc20 token
    /// @param amount Amount of the erc20 token recovered
    event RecoverErc20(address recipient, address token, uint256 amount);

    /// @notice Recovers ERC20 tokens mistakenly sent to this contract
    /// @param _tokenAddress Address of the token
    /// @param _tokenAmount Amount of the token
    function recoverErc20(address _tokenAddress, uint256 _tokenAmount) external {
        _requireSenderIsTimelock();
        IERC20(_tokenAddress).safeTransfer({ to: msg.sender, value: _tokenAmount });
        emit RecoverErc20({ recipient: msg.sender, token: _tokenAddress, amount: _tokenAmount });
    }

    /// @notice The EtherRecovered event is emitted when recoverEther is called
    /// @param recipient Address of the recipient
    /// @param amount Amount of the ether recovered
    event RecoverEther(address recipient, uint256 amount);

    /// @notice Recover ETH when someone mistakenly directly sends ETH here
    /// @param _amount Amount of ETH to recover
    function recoverEther(uint256 _amount) external {
        _requireSenderIsTimelock();

        (bool _success, ) = address(msg.sender).call{ value: _amount }("");
        if (!_success) revert InvalidEthTransfer();

        emit RecoverEther({ recipient: msg.sender, amount: _amount });
    }

    /// @notice When the redemption fee is set
    /// @param oldRedemptionFee Old redemption fee
    /// @param newRedemptionFee New redemption fee
    event SetRedemptionFee(uint64 oldRedemptionFee, uint64 newRedemptionFee);

    /// @notice Sets the fee for redeeming
    /// @param _newFee New redemption fee given in percentage terms, using 1e6 precision
    function setRedemptionFee(uint64 _newFee) external {
        _requireSenderIsTimelock();
        if (_newFee > MAX_REDEMPTION_FEE) revert ExceedsMaxRedemptionFee(_newFee, MAX_REDEMPTION_FEE);

        emit SetRedemptionFee({ oldRedemptionFee: redemptionQueueState.redemptionFee, newRedemptionFee: _newFee });

        redemptionQueueState.redemptionFee = _newFee;
    }

    /// @notice When the current wait time (in seconds) of the queue is set
    /// @param oldQueueLength Old queue length in seconds
    /// @param newQueueLength New queue length in seconds
    event SetQueueLengthSeconds(uint64 oldQueueLength, uint64 newQueueLength);

    /// @notice Sets the current wait time (in seconds) a new redeemer would have
    /// @param _newLength New queue time, in seconds
    function setQueueLengthSeconds(uint64 _newLength) external {
        _requireIsTimelockOrOperator();
        if (msg.sender != timelockAddress && _newLength > maxQueueLengthSeconds) {
            revert ExceedsMaxQueueLengthSecs(_newLength, maxQueueLengthSeconds);
        }

        emit SetQueueLengthSeconds({
            oldQueueLength: redemptionQueueState.queueLengthSecs,
            newQueueLength: _newLength
        });

        redemptionQueueState.queueLengthSecs = _newLength;
    }

    /// @notice When the max queue length the operator can set is changed
    /// @param oldMaxQueueLengthSecs Old max queue length in seconds
    /// @param newMaxQueueLengthSecs New max queue length in seconds
    event SetMaxQueueLengthSeconds(uint256 oldMaxQueueLengthSecs, uint256 newMaxQueueLengthSecs);

    /// @notice Sets the maximum queue length the operator can set
    /// @param _newMaxQueueLengthSeconds New maximum queue length
    function setMaxQueueLengthSeconds(uint256 _newMaxQueueLengthSeconds) external {
        _requireSenderIsTimelock();

        emit SetMaxQueueLengthSeconds({
            oldMaxQueueLengthSecs: maxQueueLengthSeconds,
            newMaxQueueLengthSecs: _newMaxQueueLengthSeconds
        });

        maxQueueLengthSeconds = _newMaxQueueLengthSeconds;
    }

    /// @notice Sets the operator (bot) that updates the queue length
    /// @param _newOperator New bot address
    function setOperator(address _newOperator) external {
        _requireSenderIsTimelock();
        _setOperator(_newOperator);
    }

    /// @notice When the fee recipient is set
    /// @param oldFeeRecipient Old fee recipient address
    /// @param newFeeRecipient New fee recipient address
    event SetFeeRecipient(address oldFeeRecipient, address newFeeRecipient);

    /// @notice Where redemption fees go
    /// @param _newFeeRecipient New fee recipient address
    function setFeeRecipient(address _newFeeRecipient) external {
        _requireSenderIsTimelock();

        emit SetFeeRecipient({ oldFeeRecipient: feeRecipient, newFeeRecipient: _newFeeRecipient });

        feeRecipient = _newFeeRecipient;
    }

    // ==============================================================================
    // Helper views
    // ==============================================================================

    /// @notice See if you can redeem the given NFT.
    /// @param _nftId The ID of the FrxEthRedemptionTicket NFT
    /// @param _partialAmount The partial amount you want to redeem. Leave as 0 for a full redemption test
    /// @param _revertIfFalse If true, will revert if false
    /// @return _isRedeemable If the NFT can be redeemed with the specified _partialAmount
    /// @return _maxAmountRedeemable The max amount you can actually redeem. Will be <= your full position amount. May be 0 if your queue position or something else is wrong.
    function canRedeem(
        uint256 _nftId,
        uint120 _partialAmount,
        bool _revertIfFalse
    ) public view returns (bool _isRedeemable, uint120 _maxAmountRedeemable) {
        // Get NFT information
        RedemptionQueueItem memory _redemptionQueueItem = nftInformation[_nftId];

        // Different routes depending on the _partialAmount input
        if (_partialAmount > 0) {
            // Call the internal function
            (_isRedeemable, _maxAmountRedeemable) = _canRedeem(_redemptionQueueItem, _partialAmount, _revertIfFalse);
        } else {
            // Call the internal function
            (_isRedeemable, _maxAmountRedeemable) = _canRedeem(
                _redemptionQueueItem,
                _redemptionQueueItem.amount,
                _revertIfFalse
            );
        }
    }

    /// @notice See if you can partially redeem the given NFT.
    /// @param _redemptionQueueItem The ID of the FrxEthRedemptionTicket NFT
    /// @param _amountRequested The amount you want to redeem
    /// @param _revertIfFalse If true, will revert if false. Otherwise returns a boolean
    /// @return _isRedeemable If the NFT can be redeemed with the specified _amountRequested
    /// @return _maxAmountRedeemable The max amount you can actually redeem. Will be <= your full position amount. May be 0 if your queue position or something else is wrong.
    /// @dev A partial redeem can not be used to 'cut' in line for the queue. Your queue position is always as if you tried to redeem fully
    function _canRedeem(
        RedemptionQueueItem memory _redemptionQueueItem,
        uint120 _amountRequested,
        bool _revertIfFalse
    ) internal view returns (bool _isRedeemable, uint120 _maxAmountRedeemable) {
        // Check Maturity
        // -----------------------------------------------------------
        // See if the maturity has been reached and it hasn't already been redeemed
        if (block.timestamp >= _redemptionQueueItem.maturity && !_redemptionQueueItem.hasBeenRedeemed) {
            // So far so good
            _isRedeemable = true;
        } else {
            // Either revert or mark _isRedeemable as false
            if (_revertIfFalse) {
                revert NotMatureYet({ currentTime: block.timestamp, maturity: _redemptionQueueItem.maturity });
            } else {
                // Return early
                return (false, 0);
            }
        }

        // Check for full redeem
        // Special case if _amountRequested is 0, then set it to _redemptionQueueItem.amount
        if (_amountRequested == 0) _amountRequested = _redemptionQueueItem.amount;

        // Calculate how much ETH is present and/or pullable
        // -----------------------------------------------------------
        // Get the actual amount of ETH needed, accounting for the fee
        uint120 _amountReqMinusFee = _amountRequested -
            ((uint256(_amountRequested) * uint256(_redemptionQueueItem.redemptionFee)) / FEE_PRECISION).toUint120();

        // Get the ETH balance in this contract
        uint120 _localBal = uint120(address(this).balance);

        // Get the amount of ETH pullable from the Ether Router
        EtherRouter.CachedConsEFxBalances memory _cachedBals = etherRouter.getConsolidatedEthFrxEthBalanceView(true);
        uint120 _pullableBal = uint120(_cachedBals.ethTotalBalanced);
        uint120 _availableBal = _localBal + _pullableBal;

        // See if enough is present and/or pullable to satisfy the NFT
        // -----------------------------------------------------------

        // If the NFT amount is more than the local Eth and the pullable Eth, you cannot redeem
        if (_amountReqMinusFee > _availableBal) {
            // Either revert or mark _isRedeemable as false
            if (_revertIfFalse) {
                revert InsufficientEth({ requested: _amountReqMinusFee, available: _availableBal });
            } else {
                // Don't return yet
                _isRedeemable = false;
            }
        }

        // Check queue position.
        // -----------------------------------------------------------
        // Get queue information
        RedemptionQueueState memory _redemptionQueueState = redemptionQueueState;

        // What ttlEthServed would be if everyone redeemed who could, with the available balance from contracts, AMOs, etc.
        uint120 _maxTtlEthServed = _redemptionQueueState.ttlEthServed + _availableBal;

        // The max amount of ETH that can be used to serve YOU specifically
        uint120 _maxTtlEthServeableToYou;
        if (_maxTtlEthServed >= _redemptionQueueItem.ttlEthRequestedSnapshot) {
            _maxTtlEthServeableToYou = _maxTtlEthServed - _redemptionQueueItem.ttlEthRequestedSnapshot;
        } else {
            (_maxTtlEthServeableToYou = 0);
        }

        // _amountReqMinusFee must be <= _maxTtlEthServeableToYou
        if (_amountReqMinusFee <= _maxTtlEthServeableToYou) {
            // Do nothing since _isRedeemable is already true
        } else {
            // Either revert or mark _isRedeemable as false
            if (_revertIfFalse) {
                revert QueuePosition({
                    ttlEthRequestedSnapshot: _redemptionQueueItem.ttlEthRequestedSnapshot,
                    requestedAmount: _amountReqMinusFee,
                    maxTtlEthServed: _maxTtlEthServed
                });
            } else {
                // Don't return yet
                _isRedeemable = false;
            }
        }

        // Update _maxAmountRedeemable
        // -----------------------------------------------------------
        // For starters, it should never be more than your actual position
        _maxAmountRedeemable = _redemptionQueueItem.amount;

        // Lower _maxAmountRedeemable if there isn't enough ETH
        if (_maxAmountRedeemable > _availableBal) _maxAmountRedeemable = _availableBal;

        // Lower _maxAmountRedeemable again if there is some ETH, but you cannot have it because others are in front of you
        if (_maxAmountRedeemable > _maxTtlEthServeableToYou) _maxAmountRedeemable = _maxTtlEthServeableToYou;

        // You cannot request more than you are entitled too
        // -----------------------------------------------------------

        // See if you are requesting more than you should
        if (_amountRequested > _redemptionQueueItem.amount) {
            // Either revert or mark _isRedeemable as false
            if (_revertIfFalse) {
                revert RedeemingTooMuch({ requested: _amountRequested, entitledTo: _redemptionQueueItem.amount });
            } else {
                // Don't return yet
                _isRedeemable = false;
            }
        }
    }

    /// @notice Get the entrancy status
    /// @return _isEntered If the contract has already been entered
    function entrancyStatus() external view returns (bool _isEntered) {
        _isEntered = _status == 2;
    }

    /// @notice How much shortage or surplus (to cover upcoming redemptions) this contract has
    /// @return _netEthBalance int256 Positive or negative balance of ETH
    /// @return _shortage uint256 The remaining amount of ETH needed to cover all redemptions. 0 if there is no shortage or a surplus.
    function ethShortageOrSurplus() external view returns (int256 _netEthBalance, uint256 _shortage) {
        // // Protect against reentrancy (not entered yet)
        // require(_status == 1, "ethShortageOrSurplus reentrancy");

        // Current ETH balance of this contract
        int256 _currBalance = int256(address(this).balance);

        // Total amount of ETH needed to cover all outstanding redemptions
        int256 _currLiabilities = int256(uint256(redemptionQueueAccounting.etherLiabilities));

        // Subtract pending fees since these technically will part of a surplus
        _currLiabilities -= int256(uint256(redemptionQueueAccounting.pendingFees));

        // Calculate the shortage or surplus
        _netEthBalance = _currBalance - _currLiabilities;

        // If there is a shortage, convert it to uint256
        if (_netEthBalance < 0) _shortage = uint256(-_netEthBalance);
    }

    // =============================================================================================
    // Queue Functions
    // =============================================================================================

    /// @notice When someone enters the redemption queue
    /// @param nftId The ID of the NFT
    /// @param sender The address of the msg.sender, who is redeeming frxEth
    /// @param recipient The recipient of the NFT
    /// @param amountFrxEthRedeemed The amount of frxEth requested to be redeemed
    /// @param maturityTimestamp The date of maturity, upon which redemption is allowed
    /// @param redemptionFee The redemption fee (E6) at the time of minting
    /// @param ttlEthRequestedSnapshot ttlEthRequested + amountFrxEthRedeemed at the time of the enterRedemptionQueue
    event EnterRedemptionQueue(
        uint256 indexed nftId,
        address indexed sender,
        address indexed recipient,
        uint256 amountFrxEthRedeemed,
        uint64 maturityTimestamp,
        uint64 redemptionFee,
        uint120 ttlEthRequestedSnapshot
    );

    /// @notice Enter the queue for redeeming frxEth 1-to-1 for Eth, without the need to approve first (EIP-712 / EIP-2612)
    /// @notice Will generate a FrxEthRedemptionTicket NFT that can be redeemed for the actual Eth later.
    /// @param _amountToRedeem Amount of frxETH to redeem. Must be < MAX_FRXETH_PER_NFT
    /// @param _recipient Recipient of the NFT. Must be ERC721 compatible if a contract
    /// @param _deadline Deadline for this signature
    /// @param _nftId The ID of the FrxEthRedemptionTicket NFT
    function enterRedemptionQueueWithPermit(
        uint120 _amountToRedeem,
        address _recipient,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256 _nftId) {
        // Call the permit
        FRX_ETH.permit({
            owner: msg.sender,
            spender: address(this),
            value: _amountToRedeem,
            deadline: _deadline,
            v: _v,
            r: _r,
            s: _s
        });

        // Do the redemption
        _nftId = enterRedemptionQueue({ _recipient: _recipient, _amountToRedeem: _amountToRedeem });
    }

    /// @notice Enter the queue for redeeming sfrxEth to frxETH at the current rate, then frxETH to Eth 1-to-1, without the need to approve first (EIP-712 / EIP-2612)
    /// @notice Will generate a FrxEthRedemptionTicket NFT that can be redeemed for the actual Eth later.
    /// @param _sfrxEthAmount Amount of sfrxETH to redeem (in shares / balanceOf). Resultant frxETH amount must be < MAX_FRXETH_PER_NFT
    /// @param _recipient Recipient of the NFT. Must be ERC721 compatible if a contract
    /// @param _deadline Deadline for this signature
    /// @param _nftId The ID of the FrxEthRedemptionTicket NFT
    function enterRedemptionQueueWithSfrxEthPermit(
        uint120 _sfrxEthAmount,
        address _recipient,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256 _nftId) {
        // Call the permit
        SFRX_ETH.permit({
            owner: msg.sender,
            spender: address(this),
            value: _sfrxEthAmount,
            deadline: _deadline,
            v: _v,
            r: _r,
            s: _s
        });

        // Do the redemption
        _nftId = enterRedemptionQueueViaSfrxEth({ _recipient: _recipient, _sfrxEthAmount: _sfrxEthAmount });
    }

    /// @notice Enter the queue for redeeming sfrxEth to frxETH at the current rate, then frxETH to ETH 1-to-1. Must have approved or permitted first.
    /// @notice Will generate a FrxETHRedemptionTicket NFT that can be redeemed for the actual ETH later.
    /// @param _recipient Recipient of the NFT. Must be ERC721 compatible if a contract
    /// @param _sfrxEthAmount Amount of sfrxETH to redeem (in shares / balanceOf). Resultant frxETH amount must be < MAX_FRXETH_PER_NFT
    /// @param _nftId The ID of the FrxEthRedemptionTicket NFT
    /// @dev Must call approve/permit on frxEth contract prior to this call
    function enterRedemptionQueueViaSfrxEth(
        address _recipient,
        uint120 _sfrxEthAmount
    ) public returns (uint256 _nftId) {
        // Pull in the sfrxETH
        SFRX_ETH.transferFrom({ from: msg.sender, to: address(this), amount: uint256(_sfrxEthAmount) });

        // Exchange the sfrxETH for frxETH
        uint256 _frxEthAmount = SFRX_ETH.redeem(_sfrxEthAmount, address(this), address(this));

        // Enter the queue with the frxETH you just obtained
        _nftId = _enterRedemptionQueueCore(_recipient, uint120(_frxEthAmount));
    }

    /// @notice Enter the queue for redeeming frxETH 1-to-1. Must approve first. Internal only so payor can be set
    /// @notice Will generate a FrxETHRedemptionTicket NFT that can be redeemed for the actual ETH later.
    /// @param _recipient Recipient of the NFT. Must be ERC721 compatible if a contract
    /// @param _amountToRedeem Amount of frxETH to redeem.
    /// @param _nftId The ID of the FrxEthRedemptionTicket NFT
    /// @dev Must call approve/permit on frxEth contract prior to this call
    function _enterRedemptionQueueCore(
        address _recipient,
        uint120 _amountToRedeem
    ) internal nonReentrant returns (uint256 _nftId) {
        // Don't allow too much frxETH per NFT, otherwise it can get hard to redeem later if borrow activity is high
        if (_amountToRedeem > MAX_FRXETH_PER_NFT) revert ExceedsMaxFrxEthPerNFT();

        // Add interest
        LendingPool(etherRouter.lendingPool()).addInterestPrivileged(false);

        // Get queue information
        RedemptionQueueState memory _redemptionQueueState = redemptionQueueState;
        RedemptionQueueAccounting memory _redemptionQueueAccounting = redemptionQueueAccounting;

        // Calculations: increment ether liabilities by the amount of ether owed to the user
        _redemptionQueueAccounting.etherLiabilities += _amountToRedeem;

        // Calculations: increment pending fees that will eventually be taken
        _redemptionQueueAccounting.pendingFees += ((uint256(_amountToRedeem) *
            uint256(_redemptionQueueState.redemptionFee)) / FEE_PRECISION).toUint120();

        // Calculations: maturity timestamp
        uint64 _maturityTimestamp = uint64(block.timestamp) + _redemptionQueueState.queueLengthSecs;

        // Effects: Initialize the redemption ticket NFT information
        nftInformation[_redemptionQueueState.nextNftId] = RedemptionQueueItem({
            amount: _amountToRedeem,
            maturity: _maturityTimestamp,
            hasBeenRedeemed: false,
            redemptionFee: _redemptionQueueState.redemptionFee,
            ttlEthRequestedSnapshot: _redemptionQueueState.ttlEthRequested // pre-increment
        });

        // Effects: Mint the redemption ticket NFT. Make sure the recipient supports ERC721.
        _safeMint({ to: _recipient, tokenId: _redemptionQueueState.nextNftId });

        // Emit here, before the state change
        _nftId = _redemptionQueueState.nextNftId;
        emit EnterRedemptionQueue({
            nftId: _nftId,
            sender: msg.sender,
            recipient: _recipient,
            amountFrxEthRedeemed: _amountToRedeem,
            maturityTimestamp: _maturityTimestamp,
            redemptionFee: _redemptionQueueState.redemptionFee,
            ttlEthRequestedSnapshot: _redemptionQueueState.ttlEthRequested // pre-increment
        });

        // Calculations: Increment the ttlEthRequested.
        _redemptionQueueState.ttlEthRequested += _amountToRedeem;

        // Calculations: Increment the autoincrement
        ++_redemptionQueueState.nextNftId;

        // Effects: Write all of the state changes to storage
        redemptionQueueState = _redemptionQueueState;

        // Effects: Write all of the accounting changes to storage
        redemptionQueueAccounting = _redemptionQueueAccounting;

        // Update the stored utilization rate
        LendingPool(etherRouter.lendingPool()).updateUtilization();
    }

    /// @notice Enter the queue for redeeming frxETH 1-to-1. Must approve or permit first.
    /// @notice Will generate a FrxETHRedemptionTicket NFT that can be redeemed for the actual ETH later.
    /// @param _recipient Recipient of the NFT. Must be ERC721 compatible if a contract
    /// @param _amountToRedeem Amount of frxETH to redeem. Must be < MAX_FRXETH_PER_NFT
    /// @param _nftId The ID of the FrxEthRedemptionTicket NFT
    /// @dev Must call approve/permit on frxEth contract prior to this call
    function enterRedemptionQueue(address _recipient, uint120 _amountToRedeem) public returns (uint256 _nftId) {
        // Do all of the NFT-generating and accounting logic
        _nftId = _enterRedemptionQueueCore(_recipient, _amountToRedeem);

        // Interactions: Transfer frxEth in from the sender
        IERC20(address(FRX_ETH)).safeTransferFrom({ from: msg.sender, to: address(this), value: _amountToRedeem });
    }

    /// @notice Redeems a FrxETHRedemptionTicket NFT for ETH. (Pre-ETH send)
    /// @param _nftId The ID of the NFT
    /// @param _redeemAmt The amount to redeem
    /// @return _redemptionQueueItem The RedemptionQueueItem
    function _handleRedemptionTicketNftPre(
        uint256 _nftId,
        uint120 _redeemAmt
    ) internal returns (RedemptionQueueItem memory _redemptionQueueItem) {
        // Checks: ensure proper NFT ownership
        if (!_isAuthorized({ owner: _requireOwned(_nftId), spender: msg.sender, tokenId: _nftId })) {
            revert Erc721CallerNotOwnerOrApproved();
        }

        // Get NFT information
        _redemptionQueueItem = nftInformation[_nftId];

        // Checks: Make sure maturity was reached
        // Will revert if it was not
        _canRedeem(_redemptionQueueItem, _redeemAmt, true);

        // Different paths for full vs partial
        if (_redeemAmt == 0 || _redeemAmt == _redemptionQueueItem.amount) {
            // Full Redeem
            // ---------------------------------------

            // Effects: burn the NFT
            _burn(_nftId);

            // Effects: Increment the ttlEthServed
            // Not including fees here so ttlEthRequested gets canceled out
            redemptionQueueState.ttlEthServed += _redemptionQueueItem.amount;

            // Effects: Zero the amount remaining in the NFT
            nftInformation[_nftId].amount = 0;

            // Effects: Mark NFT as redeemed
            nftInformation[_nftId].hasBeenRedeemed = true;
        } else {
            // Partial Redeem
            // ---------------------------------------

            // Effects: Increment the ttlEthServed
            // Not including fees here so ttlEthRequested gets canceled out
            redemptionQueueState.ttlEthServed += _redeemAmt;

            // Effects: Lower amount remaining in the NFT
            nftInformation[_nftId].amount -= _redeemAmt;
        }

        // IMPORTANT!!!
        // NOTE: Make sure redemptionQueueAccounting.etherLiabilities is accounted for somewhere down the line

        // IMPORTANT!!!
        // NOTE: Make sure to burn the frxETH somewhere down the line
    }

    // ====================================
    // Internal Functions
    // ====================================

    /// @notice Checks if msg.sender is current timelock address or the operator
    function _requireIsTimelockOrOperator() internal view {
        if (!((msg.sender == timelockAddress) || (msg.sender == operatorAddress))) revert NotTimelockOrOperator();
    }

    /// @notice Checks if msg.sender is current timelock address, operator, or fee recipient
    function _requireIsTimelockOperatorOrFeeRecipient() internal view {
        if (!((msg.sender == timelockAddress) || (msg.sender == operatorAddress) || (msg.sender == feeRecipient))) {
            revert NotTimelockOperatorOrFeeRecipient();
        }
    }

    /// @notice ERC721: caller is not token owner or approved
    error Erc721CallerNotOwnerOrApproved();

    /// @notice When timelock/operator tries collecting more fees than they are due
    /// @param collectAmount How much fee the ounsender is trying to collect
    /// @param accruedAmount How much fees are actually collectable
    error ExceedsCollectedFees(uint128 collectAmount, uint128 accruedAmount);

    /// @notice When someone tries setting the queue length above the max
    /// @param providedLength The provided queue length
    /// @param maxLength The maximum queue length
    error ExceedsMaxQueueLengthSecs(uint64 providedLength, uint256 maxLength);

    /// @notice When someone tries to create a redemption NFT using too much frxETH
    error ExceedsMaxFrxEthPerNFT();

    /// @notice When someone tries setting the redemption fee above MAX_REDEMPTION_FEE
    /// @param providedFee The provided redemption fee
    /// @param maxFee The maximum redemption fee
    error ExceedsMaxRedemptionFee(uint64 providedFee, uint64 maxFee);

    /// @notice Not enough ETH locally + Ether Router + AMOs to do the redemption
    /// @param available The amount of ETH actually available
    /// @param requested The amount of ETH requested
    error InsufficientEth(uint120 requested, uint120 available);

    /// @notice Invalid ETH transfer during recoverEther
    error InvalidEthTransfer();

    /// @notice NFT is not mature enough to redeem yet
    /// @param currentTime Current time.
    /// @param maturity Time of maturity
    error NotMatureYet(uint256 currentTime, uint64 maturity);

    /// @notice Thrown if the sender is not the timelock, operator, or fee recipient
    error NotTimelockOperatorOrFeeRecipient();

    /// @notice Thrown if the sender is not the timelock or the operator
    error NotTimelockOrOperator();

    /// @notice Other (earlier) people are ahead of you in the queue. ttlEthServed + (available ETH) must be >= ttlEthRequestedSnapshot + requestedAmount
    /// @param ttlEthRequestedSnapshot The NFT's snapshot of ttlEthRequested
    /// @param requestedAmount The actual amount being requested
    /// @param maxTtlEthServed What ttlEthServed would be if everyone redeemed who could, with the available balance from contracts, AMOs, etc.
    error QueuePosition(uint120 ttlEthRequestedSnapshot, uint120 requestedAmount, uint120 maxTtlEthServed);

    /// @notice When you try to redeem more than the NFT entitles you to
    /// @param requested The amount of ETH requested
    /// @param entitledTo The amount of ETH the NFT entitles you to
    error RedeemingTooMuch(uint120 requested, uint120 entitledTo);
}
