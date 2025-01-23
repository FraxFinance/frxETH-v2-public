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
// ======================== WhitelistedExecutor =======================
// ====================================================================
// Can send arbitratry calldata to a whitelisted target with a whitelisted selector
// Frax Finance: https://github.com/FraxFinance

abstract contract WhitelistedExecutor {
    /* ============================================= STATE VARIABLES ==================================================== */

    // Whitelisted Execute
    /// @notice The execution target contracts and their whitelist status
    mapping(address => bool) public executeTargets;

    /// @notice The selector's status for an execution target
    mapping(address => mapping(bytes4 => bool)) public executeSelectors;

    /* ====================================== RESTRICTED GOVERNANCE FUNCTIONS =========================================== */

    /// @notice Add / Remove an execution target address
    /// @param _targetAddress Target address
    /// @param _enabled Whether the target address as a whole is enabled or disabled
    function _setExecuteTarget(address _targetAddress, bool _enabled) internal {
        executeTargets[_targetAddress] = _enabled;

        emit SetExecuteTarget(_targetAddress, _enabled);
    }

    /// @notice Add / Remove a function selector for an execution target address
    /// @param _targetAddress Target address
    /// @param _selector The selector
    /// @param _enabled Whether the selector is enabled or disabled
    function _setExecuteSelector(address _targetAddress, bytes4 _selector, bool _enabled) internal {
        if (!executeTargets[_targetAddress]) revert UnauthorizedTarget();
        executeSelectors[_targetAddress][_selector] = _enabled;

        emit SetExecuteSelector(_targetAddress, _selector, _enabled);
    }

    /// @notice Whitelisted calls
    /// @param _to Target address
    /// @param _value ETH value transferred, if any
    /// @param _data The calldata
    function _whitelistedExecute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) internal returns (bool, bytes memory) {
        // Make sure the target is allowed
        if (!executeTargets[_to]) revert UnauthorizedTarget();

        // Extract the selector and make sure it is valid
        bytes4 selector = bytes4(_data[:4]);
        if (!executeSelectors[_to][selector]) revert UnauthorizedSelector();

        (bool success, bytes memory result) = _to.call{ value: _value }(_data);

        emit WhitelistedExecute(_to, _value, _data);

        return (success, result);
    }

    /* ================================================= ERRORS ========================================================= */

    /// @notice If the selector is not whitelisted
    error UnauthorizedSelector();

    /// @notice If the target address is not whitelisted
    error UnauthorizedTarget();

    /* ================================================= EVENTS ========================================================= */

    /// @notice The ```SetTarget``` event fires when a target address for the executor is added or removed
    /// @param _targetAddress The target address
    /// @param _enabled Whether the target is enabled or disabled
    event SetExecuteTarget(address _targetAddress, bool _enabled);

    /// @notice The ```SetOperator``` event fires when the operatorAddress is set
    /// @param _targetAddress The target address
    /// @param _selector The function selector
    /// @param _enabled Whether the target's specific selector is enabled or disabled
    event SetExecuteSelector(address _targetAddress, bytes4 _selector, bool _enabled);

    /// @notice The ```whitelistedExecute``` event fires when whitelistedExecute is called
    /// @param _to Target address
    /// @param _value ETH value transferred, if any
    /// @param _data The calldata
    event WhitelistedExecute(address _to, uint256 _value, bytes _data);
}
