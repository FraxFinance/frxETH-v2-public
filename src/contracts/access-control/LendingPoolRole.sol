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
// ========================== LendingPoolRole =========================
// ====================================================================
// Access control for the Lending Pool

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Drake Evans: https://github.com/DrakeEvans

// Reviewer(s) / Contributor(s)
// Travis Moore: https://github.com/FortisFortuna
// Dennis: https://github.com/denett

import { LendingPool } from "../lending-pool/LendingPool.sol";

abstract contract LendingPoolRole {
    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    LendingPool public lendingPool;

    /// @notice constructor
    /// @param _lendingPool Address of Lending Pool
    constructor(address payable _lendingPool) {
        lendingPool = LendingPool(_lendingPool);
    }

    // ==============================================================================
    // Configuration Setters
    // ==============================================================================

    /// @notice Sets a new Lending Pool
    /// @param _lendingPool Address for the new Lending Pool.
    function _setLendingPool(address payable _lendingPool) internal {
        emit SetLendingPool(address(lendingPool), _lendingPool);
        lendingPool = LendingPool(_lendingPool);
    }

    // ==============================================================================
    // Internal Checks
    // ==============================================================================

    /// @notice Checks if an address is the Lending Pool
    /// @param _address Address to test
    function _isLendingPool(address _address) internal view returns (bool) {
        return (_address == address(lendingPool));
    }

    /// @notice Reverts if the address is not the Lending Pool
    /// @param _address Address to test
    function _requireIsLendingPool(address _address) internal view {
        if (!_isLendingPool(_address)) {
            revert AddressIsNotLendingPool(address(lendingPool), _address);
        }
    }

    /// @notice Reverts if msg.sender is not the Lending Pool
    function _requireSenderIsLendingPool() internal view {
        _requireIsLendingPool(msg.sender);
    }

    // ==============================================================================
    // Events
    // ==============================================================================

    /// @notice The ```SetLendingPool``` event fires when the Lending Pool address changes
    /// @param oldLendingPool The old address
    /// @param newLendingPool The new address
    event SetLendingPool(address indexed oldLendingPool, address indexed newLendingPool);

    // ==============================================================================
    // Errors
    // ==============================================================================

    /// @notice Emitted when the test address is not the Lending Pool
    error AddressIsNotLendingPool(address lendingPoolAddress, address actualAddress);
}
