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
// ========================= BeaconOracleRole =========================
// ====================================================================
// Access control for the Beacon Oracle

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Drake Evans: https://github.com/DrakeEvans

// Reviewer(s) / Contributor(s)
// Travis Moore: https://github.com/FortisFortuna
// Dennis: https://github.com/denett

import { Timelock2Step } from "frax-std/access-control/v2/Timelock2Step.sol";
import { BeaconOracle } from "../BeaconOracle.sol";

abstract contract BeaconOracleRole {
    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    BeaconOracle public beaconOracle;

    /// @notice constructor
    /// @param _beaconOracle Address of Beacon Oracle
    constructor(address _beaconOracle) {
        beaconOracle = BeaconOracle(_beaconOracle);
    }

    // ==============================================================================
    // Configuration Setters
    // ==============================================================================

    /// @notice Sets a new Beacon Oracle
    /// @param _beaconOracle Address for the new Beacon Oracle
    function _setBeaconOracle(address _beaconOracle) internal {
        emit SetBeaconOracle(address(beaconOracle), _beaconOracle);
        beaconOracle = BeaconOracle(_beaconOracle);
    }

    // ==============================================================================
    // Internal Checks
    // ==============================================================================

    /// @notice Checks if an address is the Beacon Oracle
    /// @param _address Address to test
    function _isBeaconOracle(address _address) internal view returns (bool) {
        return (_address == address(beaconOracle));
    }

    /// @notice Reverts if the address is not the Beacon Oracle
    /// @param _address Address to test
    function _requireIsBeaconOracle(address _address) internal view {
        if (!_isBeaconOracle(_address)) {
            revert AddressIsNotBeaconOracle(address(beaconOracle), _address);
        }
    }

    /// @notice Reverts if msg.sender is not the Beacon Oracle
    function _requireSenderIsBeaconOracle() internal view {
        _requireIsBeaconOracle(msg.sender);
    }

    // ==============================================================================
    // Events
    // ==============================================================================

    /// @notice The ```SetBeaconOracle``` event fires when the Beacon Oracle address changes
    /// @param oldBeaconOracle The old address
    /// @param newBeaconOracle The new address
    event SetBeaconOracle(address indexed oldBeaconOracle, address indexed newBeaconOracle);

    // ==============================================================================
    // Errors
    // ==============================================================================

    /// @notice Emitted when the test address is not the Beacon Oracle
    error AddressIsNotBeaconOracle(address beaconOracleAddress, address actualAddress);
}
