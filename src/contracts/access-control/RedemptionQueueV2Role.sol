// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ======================== RedemptionQueueV2Role =======================
// ====================================================================
// Access control for the Frax Ether Redemption Queue

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna

// Reviewer(s) / Contributor(s)
// Dennis: https://github.com/denett

import { FraxEtherRedemptionQueueV2 } from "../frxeth-redemption-queue-v2/FraxEtherRedemptionQueueV2.sol";

abstract contract RedemptionQueueV2Role {
    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    FraxEtherRedemptionQueueV2 public redemptionQueue;

    /// @notice constructor
    /// @param _redemptionQueue Address of Redemption Queue
    constructor(address payable _redemptionQueue) {
        redemptionQueue = FraxEtherRedemptionQueueV2(_redemptionQueue);
    }

    // ==============================================================================
    // Configuration Setters
    // ==============================================================================

    /// @notice Sets a new Redemption Queue
    /// @param _redemptionQueue Address for the new Redemption Queue.
    function _setFraxEtherRedemptionQueueV2(address payable _redemptionQueue) internal {
        emit SetFraxEtherRedemptionQueueV2(address(redemptionQueue), _redemptionQueue);
        redemptionQueue = FraxEtherRedemptionQueueV2(_redemptionQueue);
    }

    // ==============================================================================
    // Internal Checks
    // ==============================================================================

    /// @notice Checks if an address is the Redemption Queue
    /// @param _address Address to test
    function _isFraxEtherRedemptionQueueV2(address _address) internal view returns (bool) {
        return (_address == address(redemptionQueue));
    }

    /// @notice Reverts if the address is not the Redemption Queue
    /// @param _address Address to test
    function _requireIsFraxEtherRedemptionQueueV2(address _address) internal view {
        if (!_isFraxEtherRedemptionQueueV2(_address)) {
            revert AddressIsNotFraxEtherRedemptionQueueV2(address(redemptionQueue), _address);
        }
    }

    /// @notice Reverts if msg.sender is not the Redemption Queue
    function _requireSenderIsFraxEtherRedemptionQueueV2() internal view {
        _requireIsFraxEtherRedemptionQueueV2(msg.sender);
    }

    // ==============================================================================
    // Events
    // ==============================================================================

    /// @notice The ```SetFraxEtherRedemptionQueueV2``` event fires when the Redemption Queue address changes
    /// @param oldFraxEtherRedemptionQueueV2 The old address
    /// @param newFraxEtherRedemptionQueueV2 The new address
    event SetFraxEtherRedemptionQueueV2(
        address indexed oldFraxEtherRedemptionQueueV2,
        address indexed newFraxEtherRedemptionQueueV2
    );

    // ==============================================================================
    // Errors
    // ==============================================================================

    /// @notice Emitted when the test address is not the Redemption Queue
    error AddressIsNotFraxEtherRedemptionQueueV2(address redemptionQueueAddress, address actualAddress);
}
