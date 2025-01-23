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
// ======================== FraxEtherMinterRole =======================
// ====================================================================
// Access control for the Frax Ether Minter

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Drake Evans: https://github.com/DrakeEvans

// Reviewer(s) / Contributor(s)
// Travis Moore: https://github.com/FortisFortuna
// Dennis: https://github.com/denett

import { FraxEtherMinter } from "../frax-ether-minter/FraxEtherMinter.sol";

abstract contract FraxEtherMinterRole {
    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    FraxEtherMinter public fraxEtherMinter;

    /// @notice constructor
    /// @param _fraxEtherMinter Address of Frax Ether Minter
    constructor(address payable _fraxEtherMinter) {
        fraxEtherMinter = FraxEtherMinter(_fraxEtherMinter);
    }

    // ==============================================================================
    // Configuration Setters
    // ==============================================================================

    /// @notice Sets a new Frax Ether Minter
    /// @param _fraxEtherMinter Address for the new Frax Ether Minter. Must be payable.
    function _setFraxEtherMinter(address payable _fraxEtherMinter) internal {
        emit SetFraxEtherMinter(address(fraxEtherMinter), _fraxEtherMinter);
        fraxEtherMinter = FraxEtherMinter(_fraxEtherMinter);
    }

    // ==============================================================================
    // Internal Checks
    // ==============================================================================

    /// @notice Checks if an address is the Frax Ether Minter
    /// @param _address Address to test
    function _isFraxEtherMinter(address _address) internal view returns (bool) {
        return (_address == address(fraxEtherMinter));
    }

    /// @notice Reverts if the address is not the Frax Ether Minter
    /// @param _address Address to test
    function _requireIsFraxEtherMinter(address _address) internal view {
        if (!_isFraxEtherMinter(_address)) {
            revert AddressIsNotFraxEtherMinter(address(fraxEtherMinter), _address);
        }
    }

    /// @notice Reverts if msg.sender is not the Frax Ether Minter
    function _requireSenderIsFraxEtherMinter() internal view {
        _requireIsFraxEtherMinter(msg.sender);
    }

    // ==============================================================================
    // Events
    // ==============================================================================

    /// @notice The ```SetFraxEtherMinter``` event fires when the Frax Ether Minter address changes
    /// @param oldFraxEtherMinter The old address
    /// @param newFraxEtherMinter The new address
    event SetFraxEtherMinter(address indexed oldFraxEtherMinter, address indexed newFraxEtherMinter);

    // ==============================================================================
    // Errors
    // ==============================================================================

    /// @notice Emitted when the test address is not the Frax Ether Minter
    error AddressIsNotFraxEtherMinter(address fraxEtherMinterAddress, address actualAddress);
}
