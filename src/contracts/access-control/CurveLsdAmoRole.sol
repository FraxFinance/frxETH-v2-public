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
// ========================== CurveLsdAmoRole =========================
// ====================================================================
// Access control for the Curve LSD AMO

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Drake Evans: https://github.com/DrakeEvans

// Reviewer(s) / Contributor(s)
// Travis Moore: https://github.com/FortisFortuna
// Dennis: https://github.com/denett

import { CurveLsdAmo } from "../curve-amo/CurveLsdAmo.sol";

abstract contract CurveLsdAmoRole {
    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    CurveLsdAmo public curveLsdAmo;

    /// @notice constructor
    /// @param _curveLsdAmo Address of Curve LSD AMO
    constructor(address payable _curveLsdAmo) {
        curveLsdAmo = CurveLsdAmo(_curveLsdAmo);
    }

    // ==============================================================================
    // Configuration Setters
    // ==============================================================================

    /// @notice Sets a new Curve LSD AMO
    /// @param _curveLsdAmo Address for the new Curve LSD AMO. Must be payable.
    function _setCurveLsdAmo(address payable _curveLsdAmo) internal {
        emit SetCurveLsdAmo(payable(address(curveLsdAmo)), _curveLsdAmo);
        curveLsdAmo = CurveLsdAmo(_curveLsdAmo);
    }

    // ==============================================================================
    // Internal Checks
    // ==============================================================================

    /// @notice Checks if an address is the Curve LSD AMO
    /// @param _address Address to test
    function _isCurveLsdAmo(address payable _address) internal view returns (bool) {
        return (_address == payable(address(curveLsdAmo)));
    }

    /// @notice Reverts if the address is not the Curve LSD AMO
    /// @param _address Address to test
    function _requireIsCurveLsdAmo(address payable _address) internal view {
        if (!_isCurveLsdAmo(_address)) {
            revert AddressIsNotCurveLsdAmo(payable(address(curveLsdAmo)), _address);
        }
    }

    /// @notice Reverts if msg.sender is not the Curve LSD AMO
    function _requireSenderIsCurveLsdAmo() internal view {
        _requireIsCurveLsdAmo(payable(msg.sender));
    }

    // ==============================================================================
    // Events
    // ==============================================================================

    /// @notice The ```SetCurveLsdAmo``` event fires when the Curve LSD AMO address changes
    /// @param oldCurveLsdAmo The old address
    /// @param newCurveLsdAmo The new address
    event SetCurveLsdAmo(address indexed oldCurveLsdAmo, address indexed newCurveLsdAmo);

    // ==============================================================================
    // Errors
    // ==============================================================================

    /// @notice Emitted when the test address is not the Curve LSD AMO
    error AddressIsNotCurveLsdAmo(address curveLsdAmoAddress, address actualAddress);
}
