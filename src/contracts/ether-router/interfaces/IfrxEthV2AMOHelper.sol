// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

interface IfrxEthV2AMOHelper {
    struct PoolInfo {
        bool hasCvxVault; // If there is a cvxLP vault
        bool hasStkCvxFxsVault; // If there is a stkcvxLP vault
        uint8 frxEthIndex; // coins() index of frxETH/sfrxETH
        uint8 ethIndex; // coins() index of ETH/stETH/WETH
        address rewardsContractAddress; // Address for the Convex BaseRewardPool for the cvxLP
        address fxsPersonalVaultAddress; // Address for the stkcvxLP vault, if present
        address poolAddress; // Where the actual tokens are in the pool
        address lpTokenAddress; // The LP token address. Sometimes the same as poolAddress
        address[2] poolCoins; // The addresses of the coins in the pool
        uint32 lpDepositPid; // _convexBaseRewardPool.pid
        LpAbiType lpAbiType; // General pool parameter
        FrxSfrxType frxEthType; // frxETH and sfrxETH
        EthType ethType; // ETH, WETH, and LSDs
        uint256 lpDeposited; // Total LP deposited
        uint256 lpMaxAllocation; // Max LP allowed for this AMO
    }

    struct ShowAmoBalancedAllocsPacked {
        uint96 amoEthFree;
        uint96 amoEthInLpBalanced;
        uint96 amoEthTotalBalanced;
        uint96 amoFrxEthFree;
        uint96 amoFrxEthInLpBalanced;
    }

    enum LpAbiType {
        LSDETH, // frxETH/ETH, rETH/ETH using IPoolLSDETH
        TWOLSDSTABLE, // frxETH/rETH using IPool2LSDStable
        TWOCRYPTO, // ankrETH/frxETH using IPool2Crypto
        LSDWETH // frxETH/WETH using IPoolLSDWETH
    }

    enum FrxSfrxType {
        NONE, // neither frxETH or sfrxETH
        FRXETH, // frxETH
        SFRXETH // sfrxETH
    }

    enum EthType {
        NONE, // ankrETH/frxETH
        RAWETH, // frxETH/ETH
        STETH, // frxETH/stETH
        WETH // frxETH/WETH
    }

    function acceptOwnership() external;

    function calcBalancedFullLPExit(address _curveAmoAddress) external view returns (uint256[2] memory _withdrawables);

    function calcBalancedFullLPExitWithParams(
        address _curveAmo,
        address _poolAddress,
        PoolInfo memory _poolInfo
    ) external view returns (uint256[2] memory _withdrawables);

    function calcMiscBalancedInfo(
        address _curveAmoAddress,
        uint256 _desiredCoinIdx,
        uint256 _desiredCoinAmt
    )
        external
        view
        returns (
            uint256 _lpAmount,
            uint256 _undesiredCoinAmt,
            uint256[2] memory _coinAmounts,
            uint256[2] memory _lpPerCoinsBalancedE18,
            uint256 _lp_virtual_price
        );

    function calcMiscBalancedInfoWithParams(
        address _curveAmoAddress,
        address _poolAddress,
        PoolInfo memory _poolInfo,
        uint256 _desiredCoinIdx,
        uint256 _desiredCoinAmt
    )
        external
        view
        returns (
            uint256 _lpAmount,
            uint256 _undesiredCoinAmt,
            uint256[2] memory _coinAmounts,
            uint256[2] memory _lpPerCoinsBalancedE18,
            uint256 _lp_virtual_price
        );

    function calcOneCoinsFullLPExit(address _curveAmoAddress) external view returns (uint256[2] memory _withdrawables);

    function calcOneCoinsFullLPExitWithParams(
        address _curveAmo,
        address _poolAddress,
        PoolInfo memory _poolInfo
    ) external view returns (uint256[2] memory _withdrawables);

    function calcTknsForLPBalanced(
        address _curveAmoAddress,
        uint256 _lpAmount
    ) external view returns (uint256[2] memory _withdrawables);

    function calcTknsForLPBalancedWithParams(
        address _poolAddress,
        PoolInfo memory _poolInfo,
        uint256 _lpAmount
    ) external view returns (uint256[2] memory _withdrawables);

    function chainlinkEthUsdDecimals() external view returns (uint256);

    function oracleFrxEthUsdDecimals() external view returns (uint256);

    function getCurveInfoPack(
        address _curveAmoAddress
    ) external view returns (address _curveAmo, address _poolAddress, PoolInfo memory _poolInfo);

    function getEstLpPriceEthOrUsdE18(
        address _curveAmoAddress
    ) external view returns (uint256 _inEthE18, uint256 _inUsdE18);

    function getEstLpPriceEthOrUsdE18WithParams(
        address _curveAmo,
        address _poolAddress,
        PoolInfo memory _poolInfo
    ) external view returns (uint256 _inEthE18, uint256 _inUsdE18);

    function getEthPriceE18() external view returns (uint256);

    function getFrxEthPriceE18() external view returns (uint256);

    function lpInVaults(
        address _curveAmoAddress
    ) external view returns (uint256 inCvxRewPool, uint256 inStkCvxFarm, uint256 totalVaultLP);

    function lpInVaultsWithParams(
        address _curveAmo,
        PoolInfo memory _poolInfo
    ) external view returns (uint256 inCvxRewPool, uint256 inStkCvxFarm, uint256 totalVaultLP);

    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function priceFeedEthUsd() external view returns (address);

    function priceFeedfrxEthUsd() external view returns (address);

    function renounceOwnership() external;

    function setOracles(address _frxethOracle, address _ethOracle) external;

    function showAllocationsSkipOneCoin(
        address _curveAmoAddress
    ) external view returns (uint256[10] memory _allocations);

    function showAllocationsWithParams(
        address _curveAmo,
        address _poolAddress,
        PoolInfo memory _poolInfo,
        bool _skipOneCoinCalcs
    ) external view returns (uint256[10] memory _allocations);

    function showAmoMaxLP(address _curveAmoAddress) external view returns (uint256 _lpMaxAllocation);

    function showAmoMaxLPWithParams(PoolInfo memory _poolInfo) external view returns (uint256 _lpMaxAllocation);

    function showCVXRewards(address _curveAmoAddress) external view returns (uint256 _cvxRewards);

    function showPoolAccounting(
        address _curveAmoAddress
    )
        external
        view
        returns (uint256[] memory _freeCoinBalances, uint256 _depositedLp, uint256[5] memory _poolAndVaultAllocations);

    function showPoolAccountingWithParams(
        address _curveAmo,
        address _poolAddress,
        PoolInfo memory _poolInfo
    )
        external
        view
        returns (uint256[] memory _freeCoinBalances, uint256 _depositedLp, uint256[5] memory _poolAndVaultAllocations);

    function showPoolFreeCoinBalances(
        address _curveAmoAddress
    ) external view returns (uint256[] memory _freeCoinBalances);

    function showPoolFreeCoinBalancesWithParams(
        address _curveAmoAddress,
        address _poolAddress,
        PoolInfo memory _poolInfo
    ) external view returns (uint256[] memory _freeCoinBalances);

    function showPoolLPTokenAddress(address _curveAmoAddress) external view returns (address _lpTokenAddress);

    function showPoolLPTokenAddressWithParams(
        PoolInfo memory _poolInfo
    ) external view returns (address _lpTokenAddress);

    function showPoolRewards(
        address _curveAmoAddress
    )
        external
        view
        returns (
            uint256 _crvReward,
            uint256[] memory _extraRewardAmounts,
            address[] memory _extraRewardTokens,
            uint256 _extraRewardsLength
        );

    function showPoolRewardsWithParams(
        address _curveAmo,
        PoolInfo memory _poolInfo
    )
        external
        view
        returns (
            uint256 _crvReward,
            uint256[] memory _extraRewardAmounts,
            address[] memory _extraRewardTokens,
            uint256 _extraRewardsLength
        );

    function showPoolVaults(
        address _curveAmoAddress
    ) external view returns (uint256 _lpDepositPid, address _rewardsContractAddress, address _fxsPersonalVaultAddress);

    function showPoolVaultsWithParams(
        PoolInfo memory _poolInfo
    ) external view returns (uint256 _lpDepositPid, address _rewardsContractAddress, address _fxsPersonalVaultAddress);

    function transferOwnership(address newOwner) external;

    function showAllocations(address _curveAmoAddress) external view returns (uint256[10] memory);

    function dollarBalancesOfEths(
        address _curveAmoAddress
    ) external view returns (uint256 frxETHValE18, uint256 ethValE18, uint256 ttlValE18);

    function getConsolidatedEthFrxEthBalance(
        address _curveAmoAddress
    ) external view returns (uint256, uint256, uint256, uint256, uint256);

    function getConsolidatedEthFrxEthBalancePacked(
        address _curveAmoAddress
    ) external view returns (ShowAmoBalancedAllocsPacked memory);
}
