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
// ========================== EtherRouterRole =========================
// ====================================================================
// Access control for the Ether Router

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Drake Evans: https://github.com/DrakeEvans

// Reviewer(s) / Contributor(s)
// Travis Moore: https://github.com/FortisFortuna
// Dennis: https://github.com/denett

import { EtherRouter } from "../ether-router/EtherRouter.sol";

abstract contract EtherRouterRole {
    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    EtherRouter public etherRouter;

    /// @notice constructor
    /// @param _etherRouter Address of Ether Router
    constructor(address payable _etherRouter) {
        etherRouter = EtherRouter(_etherRouter);
    }

    // ==============================================================================
    // Configuration Setters
    // ==============================================================================

    /// @notice Sets a new Ether Router
    /// @param _etherRouter Address for the new Ether Router.
    function _setEtherRouter(address payable _etherRouter) internal {
        emit SetEtherRouter(address(etherRouter), _etherRouter);
        etherRouter = EtherRouter(_etherRouter);
    }

    // ==============================================================================
    // Internal Checks
    // ==============================================================================

    /// @notice Checks if an address is the Ether Router
    /// @param _address Address to test
    function _isEtherRouter(address _address) internal view returns (bool) {
        return (_address == address(etherRouter));
    }

    /// @notice Reverts if the address is not the Ether Router
    /// @param _address Address to test
    function _requireIsEtherRouter(address _address) internal view {
        if (!_isEtherRouter(_address)) {
            revert AddressIsNotEtherRouter(address(etherRouter), _address);
        }
    }

    /// @notice Reverts if msg.sender is not the Ether Router
    function _requireSenderIsEtherRouter() internal view {
        _requireIsEtherRouter(msg.sender);
    }

    // ==============================================================================
    // Events
    // ==============================================================================

    /// @notice The ```SetEtherRouter``` event fires when the Ether Router address changes
    /// @param oldEtherRouter The old address
    /// @param newEtherRouter The new address
    event SetEtherRouter(address indexed oldEtherRouter, address indexed newEtherRouter);

    // ==============================================================================
    // Errors
    // ==============================================================================

    /// @notice Emitted when the test address is not the Ether Router
    error AddressIsNotEtherRouter(address etherRouterAddress, address actualAddress);
}
