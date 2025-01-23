// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Pool for an LSD and ETH
// Example frxETH/ETH
// Pool: https://etherscan.io/address/0xa1f8a6807c402e4a15ef4eba36528a3fed24e577#code
// LP: https://etherscan.io/address/0xf43211935c781d5ca1a41d2041f397b8a7366c7a
// [0]: ETH, [1]: frxETH
// Convex Booster: 0xF403C135812408BFbE8713b5A23a04b3D48AAE31
// Convex BaseRewardPool: 0xbD5445402B0a287cbC77cb67B2a52e2FC635dce4
// Convex PID: 36
// Curve PID: 128

interface IPoolLSDETH {
    function A() external view returns (uint256);

    function A_precise() external view returns (uint256);

    function add_liquidity(uint256[2] memory _amounts, uint256 _min_mint_amount) external payable returns (uint256);

    function admin_actions_deadline() external view returns (uint256);

    function admin_balances(uint256 i) external view returns (uint256);

    function admin_fee() external view returns (uint256);

    function apply_new_fee() external;

    function apply_transfer_ownership() external;

    function balances(uint256 arg0) external view returns (uint256);

    function calc_token_amount(uint256[2] memory _amounts, bool _is_deposit) external view returns (uint256);

    function calc_withdraw_one_coin(uint256 _token_amount, int128 i) external view returns (uint256);

    function coins(uint256 arg0) external view returns (address);

    function commit_new_fee(uint256 _new_fee, uint256 _new_admin_fee) external;

    function commit_transfer_ownership(address _owner) external;

    function donate_admin_fees() external;

    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external payable returns (uint256);

    function fee() external view returns (uint256);

    function future_A() external view returns (uint256);

    function future_A_time() external view returns (uint256);

    function future_admin_fee() external view returns (uint256);

    function future_fee() external view returns (uint256);

    function future_owner() external view returns (address);

    function get_dy(int128 i, int128 j, uint256 _dx) external view returns (uint256);

    function get_p() external view returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function initial_A() external view returns (uint256);

    function initial_A_time() external view returns (uint256);

    function kill_me() external;

    function lp_token() external view returns (address);

    function ma_exp_time() external view returns (uint256);

    function ma_last_time() external view returns (uint256);

    function owner() external view returns (address);

    function price_oracle() external view returns (uint256);

    function ramp_A(uint256 _future_A, uint256 _future_time) external;

    function remove_liquidity(uint256 _amount, uint256[2] memory _min_amounts) external returns (uint256[2] memory);

    function remove_liquidity_imbalance(
        uint256[2] memory _amounts,
        uint256 _max_burn_amount
    ) external returns (uint256);

    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount) external returns (uint256);

    function revert_new_parameters() external;

    function revert_transfer_ownership() external;

    function set_ma_exp_time(uint256 _ma_exp_time) external;

    function stop_ramp_A() external;

    function transfer_ownership_deadline() external view returns (uint256);

    function unkill_me() external;

    function withdraw_admin_fees() external;
}
