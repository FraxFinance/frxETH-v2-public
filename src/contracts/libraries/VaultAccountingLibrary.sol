// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

struct VaultAccount {
    uint256 amount; // Total amount, analogous to market cap
    uint256 shares; // Total shares, analogous to shares outstanding
}

/// @title VaultAccount Library
/// @author Drake Evans (Frax Finance) github.com/drakeevans, modified from work by @Boring_Crypto github.com/boring_crypto
/// @notice Provides a library for use with the VaultAccount struct, provides convenient math implementations
/// @dev Uses uint128 to save on storage
library VaultAccountingLibrary {
    /// @notice Calculates the shares value in relationship to `amount` and `total`. Optionally rounds up.
    /// @dev Given an amount, return the appropriate number of shares
    function _toShares(
        VaultAccount memory _total,
        uint256 _amount,
        bool _roundUp
    ) internal pure returns (uint256 _shares) {
        if (_total.amount == 0) {
            _shares = _amount;
        } else {
            // May round down to 0 temporarily
            _shares = (_amount * _total.shares) / _total.amount;

            // Optionally round up to prevent certain attacks.
            if (_roundUp && (_shares * _total.amount < _amount * _total.shares)) {
                _shares = _shares + 1;
            }
        }
    }

    /// @notice Calculates the amount value in relationship to `shares` and `total`
    /// @dev Given a number of shares, returns the appropriate amount
    function _toAmount(
        VaultAccount memory _total,
        uint256 _shares,
        bool _roundUp
    ) internal pure returns (uint256 _amount) {
        // bool _roundUp = false;
        if (_total.shares == 0) {
            _amount = _shares;
        } else {
            // Rounds down for safety
            _amount = (_shares * _total.amount) / _total.shares;

            // Optionally round up to prevent certain attacks.
            if (_roundUp && (_amount * _total.shares < _shares * _total.amount)) {
                _amount = _amount + 1;
            }
        }
    }
}
