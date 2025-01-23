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
// =========================== EtherRouter ============================
// ====================================================================
// Manages ETH and ETH-like tokens (frxETH, rETH, stETH, etc) in different AMOs and moves them between there
// and the Lending Pool
// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna

// Reviewer(s) / Contributor(s)
// Dennis: https://github.com/denett
// Sam Kazemian: https://github.com/samkazemian

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Timelock2Step } from "frax-std/access-control/v2/Timelock2Step.sol";
import { RedemptionQueueV2Role } from "../access-control/RedemptionQueueV2Role.sol";
import { LendingPoolRole, LendingPool } from "../access-control/LendingPoolRole.sol";
import { OperatorRole } from "frax-std/access-control/v2/OperatorRole.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IfrxEthV2AMO } from "./interfaces/IfrxEthV2AMO.sol";
import { IfrxEthV2AMOHelper } from "./interfaces/IfrxEthV2AMOHelper.sol";
import { PublicReentrancyGuard } from "frax-std/access-control/v2/PublicReentrancyGuard.sol";

/// @title Recieves and gives back ETH from the lending pool. Distributes idle ETH to various AMOs for use, such as LP formation.
/// @author Frax Finance
/// @notice Controlled by Frax governance
contract EtherRouter is LendingPoolRole, RedemptionQueueV2Role, OperatorRole, Timelock2Step, PublicReentrancyGuard {
    using SafeERC20 for ERC20;

    // ========================================================
    // STATE VARIABLES
    // ========================================================

    // AMO addresses
    /// @notice Array of AMOs
    address[] public amosArray;

    /// @notice Mapping is also used for faster verification
    mapping(address => bool) public amos; //

    /// @notice For caching getConsolidatedEthFrxEthBalance
    // mapping(address => bool) public staleStatusCEFEBals;
    mapping(address => CachedConsEFxBalances) public cachedConsEFxEBals;

    /// @notice Address where all ETH deposits will go to
    address public depositToAmoAddr;

    /// @notice Address where requestEther will pull from first
    address public primaryWithdrawFromAmoAddr;

    /// @notice Address of frxETH
    ERC20 public immutable frxETH;

    // ========================================================
    // STRUCTS
    // ========================================================

    /// @notice Get frxETH/sfrxETH and ETH/LSD/WETH balances
    /// @param isStale If the cache is stale or not
    /// @param amoAddress Address of the AMO for this cache
    /// @param ethFree Free and clear ETH/LSD/WETH
    /// @param ethInLpBalanced ETH/LSD/WETH in LP (balanced withdrawal)
    /// @param ethTotalBalanced Free and clear ETH/LSD/WETH + ETH/LSD/WETH in LP (balanced withdrawal)
    /// @param frxEthFree Free and clear frxETH/sfrxETH
    /// @param frxEthInLpBalanced frxETH/sfrxETH in LP (balanced withdrawal)
    struct CachedConsEFxBalances {
        bool isStale;
        address amoAddress;
        uint96 ethFree;
        uint96 ethInLpBalanced;
        uint96 ethTotalBalanced;
        uint96 frxEthFree;
        uint96 frxEthInLpBalanced;
    }

    // ========================================================
    // CONSTRUCTOR
    // ========================================================

    /// @notice Constructor for the EtherRouter
    /// @param _timelockAddress The timelock address
    /// @param _operatorAddress The operator address
    /// @param _frxEthAddress The address of the frxETH ERC20
    constructor(
        address _timelockAddress,
        address _operatorAddress,
        address _frxEthAddress
    )
        RedemptionQueueV2Role(payable(address(0)))
        LendingPoolRole(payable(address(0)))
        OperatorRole(_operatorAddress)
        Timelock2Step(_timelockAddress)
    {
        frxETH = ERC20(_frxEthAddress);
    }

    // ====================================
    // INTERNAL FUNCTIONS
    // ====================================

    /// @notice Checks if msg.sender is current timelock address or the operator
    function _requireIsTimelockOrOperator() internal view {
        if (!((msg.sender == timelockAddress) || (msg.sender == operatorAddress))) revert NotTimelockOrOperator();
    }

    /// @notice Checks if msg.sender is the lending pool or the redemption queue
    function _requireSenderIsLendingPoolOrRedemptionQueue() internal view {
        if (!((msg.sender == address(lendingPool)) || (msg.sender == address(redemptionQueue)))) {
            revert NotLendingPoolOrRedemptionQueue();
        }
    }

    // ========================================================
    // VIEWS
    // ========================================================

    /// @notice Get frxETH/sfrxETH and ETH/LSD/WETH balances
    /// @param _forceLive Force a live recalculation of the AMO values
    /// @param _previewUpdateCache Calculate, but do not write, updated cache values
    /// @return _rtnTtlBalances frxETH/sfrxETH and ETH/LSD/WETH balances
    /// @return _cachesToUpdate Caches to be updated, if specified in _previewUpdateCache
    function _getConsolidatedEthFrxEthBalanceViewCore(
        bool _forceLive,
        bool _previewUpdateCache
    )
        internal
        view
        returns (CachedConsEFxBalances memory _rtnTtlBalances, CachedConsEFxBalances[] memory _cachesToUpdate)
    {
        // Initialize _cachesToUpdate
        CachedConsEFxBalances[] memory _cachesToUpdateLocal = new CachedConsEFxBalances[](amosArray.length);

        // Add ETH sitting in this contract first
        // frxETH/sfrxETH should never be here
        // _rtnTtlBalances.isStale = false
        _rtnTtlBalances.ethFree += uint96(address(this).balance);
        _rtnTtlBalances.ethTotalBalanced += uint96(address(this).balance);

        // Loop through all the AMOs and sum
        for (uint256 i = 0; i < amosArray.length; ) {
            address _amoAddress = amosArray[i];
            // Skip removed AMOs
            if (_amoAddress != address(0)) {
                // Pull the cache entry
                CachedConsEFxBalances memory _cacheEntry = cachedConsEFxEBals[_amoAddress];

                // If the caller wants to force a live calc, or the cache is stale
                if (_cacheEntry.isStale || _forceLive) {
                    IfrxEthV2AMOHelper.ShowAmoBalancedAllocsPacked memory _packedBals = IfrxEthV2AMOHelper(
                        IfrxEthV2AMO(_amoAddress).amoHelper()
                    ).getConsolidatedEthFrxEthBalancePacked(_amoAddress);

                    // Add to the return totals
                    _rtnTtlBalances.ethFree += _packedBals.amoEthFree;
                    _rtnTtlBalances.ethInLpBalanced += _packedBals.amoEthInLpBalanced;
                    _rtnTtlBalances.ethTotalBalanced += _packedBals.amoEthTotalBalanced;
                    _rtnTtlBalances.frxEthFree += _packedBals.amoFrxEthFree;
                    _rtnTtlBalances.frxEthInLpBalanced += _packedBals.amoFrxEthInLpBalanced;

                    // If the cache should be updated (per the input params)
                    if (_previewUpdateCache) {
                        // Push to the return array
                        // Would have rather wrote to storage here, but the compiler complained about the view "mutability"
                        _cachesToUpdateLocal[i] = CachedConsEFxBalances(
                            false,
                            _amoAddress,
                            _packedBals.amoEthFree,
                            _packedBals.amoEthInLpBalanced,
                            _packedBals.amoEthTotalBalanced,
                            _packedBals.amoFrxEthFree,
                            _packedBals.amoFrxEthInLpBalanced
                        );
                    }
                } else {
                    // Otherwise, just read from the cache
                    _rtnTtlBalances.ethFree += _cacheEntry.ethFree;
                    _rtnTtlBalances.ethInLpBalanced += _cacheEntry.ethInLpBalanced;
                    _rtnTtlBalances.ethTotalBalanced += _cacheEntry.ethTotalBalanced;
                    _rtnTtlBalances.frxEthFree += _cacheEntry.frxEthFree;
                    _rtnTtlBalances.frxEthInLpBalanced += _cacheEntry.frxEthInLpBalanced;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Update the return value
        _cachesToUpdate = _cachesToUpdateLocal;
    }

    /// @notice Get frxETH/sfrxETH and ETH/LSD/WETH balances
    /// @param _forceLive Force a live recalculation of the AMO values
    /// @param _updateCache Whether to update the cache
    /// @return _rtnBalances frxETH/sfrxETH and ETH/LSD/WETH balances
    function getConsolidatedEthFrxEthBalance(
        bool _forceLive,
        bool _updateCache
    ) external returns (CachedConsEFxBalances memory _rtnBalances) {
        CachedConsEFxBalances[] memory _cachesToUpdate;
        // Determine the route
        if (_updateCache) {
            // Fetch the return balances as well as the new balances to cache
            (_rtnBalances, _cachesToUpdate) = _getConsolidatedEthFrxEthBalanceViewCore(_forceLive, true);

            // Loop through the caches and store them
            for (uint256 i = 0; i < _cachesToUpdate.length; ) {
                // Get the address of the AMO
                address _amoAddress = _cachesToUpdate[i].amoAddress;

                // Skip caches that don't need to be updated
                if (_amoAddress != address(0)) {
                    // Update storage
                    cachedConsEFxEBals[_amoAddress] = _cachesToUpdate[i];
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            // Don't care about updating the cache, so return early
            (_rtnBalances, ) = _getConsolidatedEthFrxEthBalanceViewCore(_forceLive, false);
        }
    }

    /// @notice Get frxETH/sfrxETH and ETH/LSD/WETH balances
    /// @param _forceLive Force a live recalculation of the AMO values
    /// @return _rtnBalances frxETH/sfrxETH and ETH/LSD/WETH balances
    function getConsolidatedEthFrxEthBalanceView(
        bool _forceLive
    ) external view returns (CachedConsEFxBalances memory _rtnBalances) {
        // Return the view-only component
        (_rtnBalances, ) = _getConsolidatedEthFrxEthBalanceViewCore(_forceLive, false);
    }

    // ========================================================
    // CALLED BY LENDING POOL
    // ========================================================

    /// @notice Lending Pool or Minter or otherwise -> ETH -> This Ether Router
    function depositEther() external payable {
        // Do nothing for now except accepting the ETH
    }

    /// @notice Use a private transaction. Router will deposit ETH first into the redemption queue, if there is a shortage. Any leftover ETH goes to the default depositToAmoAddr.
    /// @param _amount Amount to sweep. Will use contract balance if = 0
    /// @param _depositAndVault Whether you want to just dump the ETH in the Curve AMO, or if you want to wrap and vault it too
    function sweepEther(uint256 _amount, bool _depositAndVault) external {
        _requireIsTimelockOrOperator();

        // Add interest first
        lendingPool.addInterest(false);

        // Use the entire contract balance if _amount is 0
        if (_amount == 0) _amount = address(this).balance;

        // See if the redemption queue has a shortage
        (, uint256 _rqShortage) = redemptionQueue.ethShortageOrSurplus();

        // Take care of any shortage first
        if (_amount <= _rqShortage) {
            // Give all you can to help address the shortage
            (bool sent, ) = payable(redemptionQueue).call{ value: _amount }("");
            if (!sent) revert EthTransferFailedER(0);

            emit EtherSwept(address(redemptionQueue), _amount);
        } else {
            // First fulfill the shortage, if any
            if (_rqShortage > 0) {
                (bool sent, ) = payable(redemptionQueue).call{ value: _rqShortage }("");
                if (!sent) revert EthTransferFailedER(1);

                emit EtherSwept(address(redemptionQueue), _rqShortage);
            }

            // Calculate the remaining ETH
            uint256 _remainingEth = _amount - _rqShortage;

            // Make sure the AMO is not the zero address, then deposit to it
            if (depositToAmoAddr != address(0)) {
                // Send ETH to the AMO. Either 1) Leave it alone, or 2) Deposit it into cvxLP + vault it
                if (_depositAndVault) {
                    // Drop in, deposit, and vault
                    IfrxEthV2AMO(depositToAmoAddr).depositEther{ value: _remainingEth }();
                } else {
                    // Drop in only
                    (bool sent, ) = payable(depositToAmoAddr).call{ value: _remainingEth }("");
                    if (!sent) revert EthTransferFailedER(2);
                }

                // Mark the getConsolidatedEthFrxEthBalance cache as stale for this AMO
                cachedConsEFxEBals[depositToAmoAddr].isStale = true;
            }

            emit EtherSwept(depositToAmoAddr, _remainingEth);
        }

        // Update the stored utilization rate
        lendingPool.updateUtilization();
    }

    /// @notice See how ETH would flow if requestEther were called
    /// @param _ethRequested Amount of ETH requested
    /// @return _currEthInRouter How much ETH is currently in this contract
    /// @return _rqShortage How much the ETH shortage in the redemption queue is, if any
    /// @return _pullFromAmosAmount How much ETH would need to be pulled from various AMO(s)
    function previewRequestEther(
        uint256 _ethRequested
    ) public view returns (uint256 _currEthInRouter, uint256 _rqShortage, uint256 _pullFromAmosAmount) {
        // See how much ETH is already in this contract
        _currEthInRouter = address(this).balance;

        // See if the redemption queue has a shortage
        (, _rqShortage) = redemptionQueue.ethShortageOrSurplus();

        // Determine where to get the ETH from
        if ((_ethRequested + _rqShortage) <= _currEthInRouter) {
            // Do nothing, the ETH will be pulled from existing funds in this contract
        } else {
            // Calculate the extra amount needed from various AMO(s)
            _pullFromAmosAmount = _ethRequested + _rqShortage - _currEthInRouter;
        }
    }

    /// @notice AMO(s) -> ETH -> (Lending Pool or Redemption Queue). Instruct the router to get ETH from various AMO(s) (free and vaulted)
    /// @param _recipient Recipient of the ETH
    /// @param _ethRequested Amount of ETH requested
    /// @param _bypassFullRqShortage If someone wants to redeem and _rqShortage is too large, send back what you can
    /// @dev Need to pay off any shortage in the redemption queue first
    function requestEther(
        address payable _recipient,
        uint256 _ethRequested,
        bool _bypassFullRqShortage
    ) external nonReentrant {
        // Only the LendingPool or RedemptionQueue can call
        _requireSenderIsLendingPoolOrRedemptionQueue();

        // Add interest
        lendingPool.addInterestPrivileged(false);
        // if (msg.sender == address(redemptionQueue)) {
        //     lendingPool.addInterestPrivileged(false);
        // }
        // else if (msg.sender == address(lendingPool)) {
        //     lendingPool.addInterest(false);

        // }
        // else {
        //     revert NotLendingPoolOrRedemptionQueue();
        // }

        // See where the ETH is and where it needs to go
        (uint256 _currEthInRouter, uint256 _rqShortage, uint256 _pullFromAmosAmount) = previewRequestEther(
            _ethRequested
        );

        // Pull the extra amount needed from the AMO(s) first, if necessary
        uint256 _remainingEthToPull = _pullFromAmosAmount;

        // If _bypassFullRqShortage is true, we don't care about the full RQ shortage
        if (_bypassFullRqShortage) {
            if (_ethRequested <= _currEthInRouter) {
                // The ETH will be pulled from existing funds in this contract
                _remainingEthToPull = 0;
            } else {
                // Calculate the extra amount needed from various AMO(s)
                _remainingEthToPull = _ethRequested - _currEthInRouter;
            }
        }

        // Start pulling from the AMOs, with primaryWithdrawFromAmoAddr being preferred
        if (_remainingEthToPull > 0) {
            // Order the amos
            address[] memory _sortedAmos = new address[](amosArray.length);

            // Handle primaryWithdrawFromAmoAddr
            if (primaryWithdrawFromAmoAddr != address(0)) {
                // primaryWithdrawFromAmoAddr should be first
                _sortedAmos[0] = primaryWithdrawFromAmoAddr;

                // Loop through all the AMOs and fill _sortedAmos
                uint256 _nextIdx = 1; // [0] is always primaryWithdrawFromAmoAddr
                for (uint256 i = 0; i < amosArray.length; ++i) {
                    // Don't double add primaryWithdrawFromAmoAddr
                    if (amosArray[i] == primaryWithdrawFromAmoAddr) continue;

                    // Push the remaining AMOs in
                    _sortedAmos[_nextIdx] = amosArray[i];

                    // Increment the next index to insert at
                    ++_nextIdx;
                }
            } else {
                _sortedAmos = amosArray;
            }

            // Loop through the AMOs and pull out ETH
            for (uint256 i = 0; i < _sortedAmos.length; ) {
                if (_sortedAmos[i] != address(0)) {
                    // Pull Ether from an AMO. May return a 0, partial, or full amount
                    (uint256 _ethOut, ) = IfrxEthV2AMO(_sortedAmos[i]).requestEtherByRouter(_remainingEthToPull);

                    // Account for the collected Ether
                    _remainingEthToPull -= _ethOut;

                    // If ETH was removed, mark the getConsolidatedEthFrxEthBalance cache as stale for this AMO
                    if (_ethOut > 0) cachedConsEFxEBals[_sortedAmos[i]].isStale = true;

                    // Stop looping if it collected enough
                    if (_remainingEthToPull == 0) break;
                    unchecked {
                        ++i;
                    }
                }
            }
        }

        // Fail early if you didn't manage to collect enough, but see if it is a dust amount first
        if (_remainingEthToPull > 0) revert NotEnoughEthPulled(_remainingEthToPull);

        // Give the shortage ETH to the redemption queue, if necessary and not bypassed
        if (!_bypassFullRqShortage && (_rqShortage > 0)) {
            (bool sent, ) = payable(redemptionQueue).call{ value: _rqShortage }("");
            if (!sent) revert EthTransferFailedER(2);
        }

        // Give remaining ETH to the recipient (could be the redemption queue)
        (bool sent, ) = payable(_recipient).call{ value: _ethRequested }("");
        if (!sent) revert EthTransferFailedER(3);

        // Update the stored utilization rate
        lendingPool.updateUtilization();

        emit EtherRequested(payable(_recipient), _ethRequested, _rqShortage);
    }

    /// @notice Needs to be here to receive ETH
    receive() external payable {
        // Do nothing for now.
    }

    // ========================================================
    // RESTRICTED GOVERNANCE FUNCTIONS
    // ========================================================

    // Adds an AMO
    /// @param _amoAddress Address of the AMO to add
    function addAmo(address _amoAddress) external {
        _requireSenderIsTimelock();
        if (_amoAddress == address(0)) revert ZeroAddress();

        // Need to make sure at least that getConsolidatedEthFrxEthBalance is present
        // This will revert if it isn't there
        IfrxEthV2AMOHelper(IfrxEthV2AMO(_amoAddress).amoHelper()).getConsolidatedEthFrxEthBalance(_amoAddress);

        // Make sure the AMO isn't already here
        if (amos[_amoAddress]) revert AmoAlreadyExists();

        // Update state
        amos[_amoAddress] = true;
        amosArray.push(_amoAddress);

        emit FrxEthAmoAdded(_amoAddress);
    }

    // Removes an AMO
    /// @param _amoAddress Address of the AMO to remove
    function removeAmo(address _amoAddress) external {
        _requireSenderIsTimelock();
        if (_amoAddress == address(0)) revert ZeroAddress();
        if (!amos[_amoAddress]) revert AmoAlreadyOffOrMissing();

        // Delete from the mapping
        delete amos[_amoAddress];

        // 'Delete' from the array by setting the address to 0x0
        for (uint256 i = 0; i < amosArray.length; ) {
            if (amosArray[i] == _amoAddress) {
                amosArray[i] = address(0); // This will leave a null in the array and keep the indices the same
                break;
            }
            unchecked {
                ++i;
            }
        }

        emit FrxEthAmoRemoved(_amoAddress);
    }

    /// @notice Set preferred AMO addresses to deposit to / withdraw from
    /// @param _depositToAddress New address for the ETH deposit destination
    /// @param _withdrawFromAddress New address for the primary ETH withdrawal source
    function setPreferredDepositAndWithdrawalAMOs(address _depositToAddress, address _withdrawFromAddress) external {
        _requireIsTimelockOrOperator();

        // Make sure they are actually AMOs
        if (!amos[_depositToAddress] || !amos[_withdrawFromAddress]) revert InvalidAmo();

        // Set the addresses
        depositToAmoAddr = _depositToAddress;
        primaryWithdrawFromAmoAddr = _withdrawFromAddress;

        emit PreferredDepositAndWithdrawalAmoAddressesSet(_depositToAddress, _withdrawFromAddress);
    }

    /// @notice Sets the lending pool, where ETH is taken from / given to
    /// @param _newAddress New address for the lending pool
    function setLendingPool(address _newAddress) external {
        _requireSenderIsTimelock();
        _setLendingPool(payable(_newAddress));
    }

    /// @notice Change the Operator address
    /// @param _newOperatorAddress Operator address
    function setOperatorAddress(address _newOperatorAddress) external {
        _requireSenderIsTimelock();
        _setOperator(_newOperatorAddress);
    }

    /// @notice Sets the redemption queue, where frxETH is redeemed for ETH. Only callable once
    /// @param _newAddress New address for the redemption queue
    function setRedemptionQueue(address _newAddress) external {
        _requireSenderIsTimelock();

        // Only can set once
        if (payable(redemptionQueue) != payable(0)) revert RedemptionQueueAddressAlreadySet();

        _setFraxEtherRedemptionQueueV2(payable(_newAddress));
    }

    // ==============================================================================
    // Recovery Functions
    // ==============================================================================

    /// @notice For taking lending interest profits, or removing excess ETH. Proceeds go to timelock.
    /// @param _amount Amount of ETH to recover
    function recoverEther(uint256 _amount) external {
        _requireSenderIsTimelock();

        (bool _success, ) = address(timelockAddress).call{ value: _amount }("");
        if (!_success) revert InvalidRecoverEtherTransfer();

        emit EtherRecovered(_amount);
    }

    /// @notice For emergencies if someone accidentally sent some ERC20 tokens here. Proceeds go to timelock.
    /// @param _tokenAddress Address of the ERC20 to recover
    /// @param _tokenAmount Amount of the ERC20 to recover
    function recoverErc20(address _tokenAddress, uint256 _tokenAmount) external {
        _requireSenderIsTimelock();

        ERC20(_tokenAddress).safeTransfer({ to: timelockAddress, value: _tokenAmount });

        emit Erc20Recovered(_tokenAddress, _tokenAmount);
    }

    // ========================================================
    // ERRORS
    // ========================================================

    /// @notice When you are trying to add an AMO that already exists
    error AmoAlreadyExists();

    /// @notice When you are trying to remove an AMO that is already removed or doesn't exist
    error AmoAlreadyOffOrMissing();

    /// @notice When an Ether transfer fails
    /// @param step A marker in the code where it is failing
    error EthTransferFailedER(uint256 step);

    /// @notice When you are trying to interact with an invalid AMO
    error InvalidAmo();

    /// @notice Invalid ETH transfer during recoverEther
    error InvalidRecoverEtherTransfer();

    /// @notice If requestEther was unable to pull enough ETH from AMOs to satify a request
    /// @param remainingEth The amount remaining that was unable to be pulled
    error NotEnoughEthPulled(uint256 remainingEth);

    /// @notice Thrown if the sender is not the lending pool or the redemption queue
    error NotLendingPoolOrRedemptionQueue();

    /// @notice Thrown if the sender is not the timelock or the operator
    error NotTimelockOrOperator();

    /// @notice Thrown if the redemption queue address was already set
    error RedemptionQueueAddressAlreadySet();

    /// @notice When an provided address is address(0)
    error ZeroAddress();

    // ========================================================
    // EVENTS
    // ========================================================

    /// @notice When recoverEther is called
    /// @param amount The amount of Ether recovered
    event EtherRecovered(uint256 amount);

    /// @notice When recoverErc20 is called
    /// @param tokenAddress The address of the ERC20 token being recovered
    /// @param tokenAmount The quantity of the token
    event Erc20Recovered(address tokenAddress, uint256 tokenAmount);

    /// @notice When Ether is requested and sent out
    /// @param requesterAddress Address of the requester
    /// @param amountToRequester Amount of ETH sent to the requester
    /// @param amountToRedemptionQueue Amount of ETH sent to the redemption queue
    event EtherRequested(address requesterAddress, uint256 amountToRequester, uint256 amountToRedemptionQueue);

    /// @notice When Ether is moved from this contract into the redemption queue or AMO(s)
    /// @param destAddress Where the ETH was swept into
    /// @param amount Amount of the swept ETH
    event EtherSwept(address destAddress, uint256 amount);

    /// @notice When an AMO is added
    /// @param amoAddress The address of the added AMO
    event FrxEthAmoAdded(address amoAddress);

    /// @notice When an AMO is removed
    /// @param amoAddress The address of the removed AMO
    event FrxEthAmoRemoved(address amoAddress);

    /// @notice When the preferred AMO addresses to deposit to / withdraw from are set
    /// @param depositToAddress Which AMO incoming ETH should be sent to
    /// @param withdrawFromAddress New address for the primary ETH withdrawal source
    event PreferredDepositAndWithdrawalAmoAddressesSet(address depositToAddress, address withdrawFromAddress);
}
