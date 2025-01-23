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
// ======================== CurveLsdAmoHelper =========================
// ====================================================================

// Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna
// Amirnader Aghayeghazvini: https://github.com/amirnader-ghazvini

// Reviewer(s) / Contributor(s)
// Drake Evans: https://github.com/DrakeEvans
// Dennis: https://github.com/denett

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { CurveLsdAmo } from "./CurveLsdAmo.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IConvexBaseRewardPool } from "./interfaces/convex/IConvexBaseRewardPool.sol";
import { IFraxFarm } from "./interfaces/frax/IFraxFarm.sol";
import { IFrxEth } from "../interfaces/IFrxEth.sol";
import { IFxsPersonalVault } from "./interfaces/convex/IFxsPersonalVault.sol";
import { IMinCurvePool } from "./interfaces/curve/IMinCurvePool.sol";
import { IPool2Crypto } from "./interfaces/curve/IPool2Crypto.sol";
import { IPool2LSDStable } from "./interfaces/curve/IPool2LSDStable.sol";
import { IPoolLSDETH } from "./interfaces/curve/IPoolLSDETH.sol";
import { ISfrxEthUsdDualOracle } from "./interfaces/frax/ISfrxEthUsdDualOracle.sol";
import { ISfrxEth } from "../interfaces/ISfrxEth.sol";
import { IVirtualBalanceRewardPool } from "./interfaces/convex/IVirtualBalanceRewardPool.sol";
import { IcvxRewardPool } from "./interfaces/convex/IcvxRewardPool.sol";
import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "forge-std/console2.sol";

/// @notice Get frxETH/sfrxETH and ETH/LSD/WETH balances
/// @param amoEthFree Free and clear ETH/LSD/WETH
/// @param amoEthInLpBalanced ETH/LSD/WETH in LP (balanced withdrawal)
/// @param amoEthTotalBalanced Free and clear ETH/LSD/WETH + ETH/LSD/WETH in LP (balanced withdrawal)
/// @param amoFrxEthFree Free and clear frxETH/sfrxETH
/// @param amoFrxEthInLpBalanced frxETH/sfrxETH in LP (balanced withdrawal)
struct ShowAmoBalancedAllocsPacked {
    uint96 amoEthFree;
    uint96 amoEthInLpBalanced;
    uint96 amoEthTotalBalanced;
    uint96 amoFrxEthFree;
    uint96 amoFrxEthInLpBalanced;
}

contract CurveLsdAmoHelper is Ownable2Step {
    /* ============================================= STATE VARIABLES ==================================================== */

    // Constants (ERC20)
    IFrxEth private constant frxETH = IFrxEth(0x5E8422345238F34275888049021821E8E08CAa1f);
    ISfrxEth private constant sfrxETH = ISfrxEth(0xac3E018457B222d93114458476f3E3416Abbe38F);
    ERC20 private constant stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Curve AMO
    IcvxRewardPool private constant CVX_REWARD_POOL = IcvxRewardPool(0xCF50b810E57Ac33B91dCF525C6ddd9881B139332);

    // Oracles
    ISfrxEthUsdDualOracle public priceFeedfrxEthUsd;
    AggregatorV3Interface public priceFeedEthUsd;
    uint256 public oracleFrxEthUsdDecimals;
    uint256 public chainlinkEthUsdDecimals;
    uint256 public oracleTimeTolerance = 126_144_000; // 4 years (for tests)
    // uint256 public oracleTimeTolerance = 21600; // 6 hours

    /* ============================================= CONSTRUCTOR ==================================================== */

    /// @notice constructor
    /// @param _ownerAddress Address of CurveAMO Operator
    constructor(address _ownerAddress) Ownable(_ownerAddress) {
        // frxETH (Use ETH for now until the real chainlink one is live)
        priceFeedfrxEthUsd = ISfrxEthUsdDualOracle(0x3d3D868522b5a4035ADcb67BF0846D61597A6a6F);
        oracleFrxEthUsdDecimals = priceFeedfrxEthUsd.decimals();

        // ETH
        priceFeedEthUsd = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        chainlinkEthUsdDecimals = priceFeedEthUsd.decimals();
    }

    /* ================================================== VIEWS ========================================================= */

    // ----------------------- ALLOCATIONS -----------------------

    /// @notice Lending pool can pull out ETH/LSD/WETH by unwinding vaults and/or FXS Vaulted LP
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _amoEthFree Free and clear ETH/LSD/WETH
    /// @return _amoEthInLp ETH/LSD/WETH locked up in LP (balanced withdrawal)
    /// @return _amoEthTotalBalanced ETH/LSD/WETH locked up in LP (balanced withdrawal)
    /// @return _amoFrxEthFree Free and clear frxETH/sfrxETH
    /// @return _amoFrxEthInLpBalanced frxETH/sfrxETH in LP (balanced withdrawal)
    /// @dev used by the lending pool to determine utilization rates
    function getConsolidatedEthFrxEthBalance(
        address _curveAmoAddress
    )
        external
        view
        returns (
            uint256 _amoEthFree,
            uint256 _amoEthInLp,
            uint256 _amoEthTotalBalanced,
            uint256 _amoFrxEthFree,
            uint256 _amoFrxEthInLpBalanced
        )
    {
        uint256[10] memory allocs = showAllocationsSkipOneCoin(_curveAmoAddress);
        return (allocs[1], allocs[7], allocs[1] + allocs[7], allocs[0], allocs[6]);
    }

    /// @notice Lending pool can pull out ETH/LSD/WETH by unwinding vaults and/or FXS Vaulted LP. Uint96 / packed version
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _allocsPacked Returned allocations in condensed form
    /// @dev used by the lending pool to determine utilization rates
    function getConsolidatedEthFrxEthBalancePacked(
        address _curveAmoAddress
    ) external view returns (ShowAmoBalancedAllocsPacked memory _allocsPacked) {
        uint256[10] memory allocs = showAllocationsSkipOneCoin(_curveAmoAddress);
        _allocsPacked = ShowAmoBalancedAllocsPacked(
            uint96(allocs[1]),
            uint96(allocs[7]),
            uint96(allocs[1] + allocs[7]),
            uint96(allocs[0]),
            uint96(allocs[6])
        );
    }

    /// @notice Total USD value of frxETH/sfrxETH and ETH/LSD/WETH held. Uses CURRENT RATIO in LPs
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _frxETHValE18 frxETH value in USD
    /// @return _ethValE18 ETH/LSD/WETH value in USD
    /// @return _ttlValE18 Sum value
    function dollarBalancesOfEths(
        address _curveAmoAddress
    ) external view returns (uint256 _frxETHValE18, uint256 _ethValE18, uint256 _ttlValE18) {
        // Get the allocations
        uint256[10] memory allocations = showAllocations(_curveAmoAddress);

        // Get return values
        // showAllocations() already "converts" sfrxETH to equivalent frxETH at the proper ratio
        _frxETHValE18 = (allocations[8] * getFrxEthPriceE18()) / (1e18);
        _ethValE18 = (allocations[9] * getEthPriceE18()) / (1e18);
        _ttlValE18 = _frxETHValE18 + _ethValE18;
    }

    // ----------------------- ORACLE RELATED -----------------------

    /// @notice Gets the price of frxETH
    /// @return uint256 USD price in E18
    function getFrxEthPriceE18() public view returns (uint256) {
        // Fetch the USD per ETH price
        (, uint256 _updatedAt, uint256 _usdPerEth) = priceFeedfrxEthUsd.getEthUsdChainlinkPrice();
        if (!(_usdPerEth >= 0 && ((_updatedAt + oracleTimeTolerance) > block.timestamp))) revert InvalidOraclePrice();

        // console2.log("_isBadData: %s", _isBadData);
        // console2.log("_updatedAt: %s", _updatedAt);
        // console2.log("_usdPerEth: %s", _usdPerEth);
        // console2.log("block.timestamp: %s", block.timestamp);
        // console2.log("(_updatedAt + oracleTimeTolerance) > block.timestamp): %s", (_updatedAt + oracleTimeTolerance) > block.timestamp);

        // Update the _usdPerEth price to E18
        _usdPerEth = (_usdPerEth * (10 ** (18 - priceFeedfrxEthUsd.FRAX_USD_CHAINLINK_FEED_DECIMALS())));

        // Calculate the frxETH price
        return (priceFeedfrxEthUsd.getWethPerFrxEthCurveEma() * _usdPerEth) / priceFeedfrxEthUsd.decimals();
    }

    /// @notice Gets the price of ETH
    /// @return uint256 USD price in E18
    function getEthPriceE18() public view returns (uint256) {
        (uint80 _roundId, int256 _price, , uint256 _updatedAt, uint80 _answeredInRound) = priceFeedEthUsd
            .latestRoundData();
        if (!(_price >= 0 && ((_updatedAt + oracleTimeTolerance) > block.timestamp))) revert InvalidOraclePrice();

        return (uint256(_price) * 1e18) / (10 ** chainlinkEthUsdDecimals);
    }

    /// @notice Gets the estimated price of an LP token, in USD and in ETH. Assumes 1 ETH = 1 frxETH. Same as getEstLpPriceEthOrUsdE18WithParams but will pre-fetch pool info for you
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _inEthE18 LP price in ETH, E18
    /// @return _inUsdE18 LP price in USD, E18
    function getEstLpPriceEthOrUsdE18(
        address _curveAmoAddress
    ) public view returns (uint256 _inEthE18, uint256 _inUsdE18) {
        // Fetch the Curve AMO, the pool address, and the pool info
        (CurveLsdAmo _curveAmo, address _poolAddress, CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(
            _curveAmoAddress
        );

        // Get the estimated LP price
        return getEstLpPriceEthOrUsdE18WithParams(_curveAmo, _poolAddress, _poolInfo);
    }

    /// @notice Gets the estimated price of an LP token, in USD and in ETH. Assumes 1 ETH = 1 frxETH
    /// @param _curveAmo Address of the Curve AMO
    /// @param _poolAddress Address of the Curve pool
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @return _inEthE18 LP price in ETH, E18
    /// @return _inUsdE18 LP price in USD, E18
    function getEstLpPriceEthOrUsdE18WithParams(
        CurveLsdAmo _curveAmo,
        address _poolAddress,
        CurveLsdAmo.PoolInfo memory _poolInfo
    ) public view returns (uint256 _inEthE18, uint256 _inUsdE18) {
        // Estimate the LP price
        if (
            _poolInfo.lpAbiType == CurveLsdAmo.LpAbiType.LSDETH ||
            _poolInfo.lpAbiType == CurveLsdAmo.LpAbiType.TWOLSDSTABLE ||
            _poolInfo.lpAbiType == CurveLsdAmo.LpAbiType.LSDWETH
        ) {
            _inEthE18 = IPoolLSDETH(_poolAddress).get_virtual_price();
            _inUsdE18 = (_inEthE18 * getEthPriceE18()) / (1e18);
        } else if (_poolInfo.lpAbiType == CurveLsdAmo.LpAbiType.TWOCRYPTO) {
            _inEthE18 = IPool2Crypto(_poolAddress).lp_price();
            _inUsdE18 = (_inEthE18 * getEthPriceE18()) / (1e18);
        } else {
            revert InvalidLpAbiType();
        }
    }

    // --------------------------------------------------------------

    /// @notice Get Curve AMO struct, the pool address, and the pool info
    /// @param _curveAmoAddress Address of the Curve AMO
    function getCurveInfoPack(
        address _curveAmoAddress
    ) public view returns (CurveLsdAmo _curveAmo, address _poolAddress, CurveLsdAmo.PoolInfo memory _poolInfo) {
        // Fetch the Curve AMO
        _curveAmo = CurveLsdAmo(payable(_curveAmoAddress));

        // Fetch the pool address
        _poolAddress = _curveAmo.poolAddress();

        // Fetch the pool info
        _poolInfo = _curveAmo.getFullPoolInfo();
    }

    /// @notice Show allocations of a Curve AMO in frxETH and ETH. Same as showAllocationsWithParams but fetches info for you
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _allocations [Free frxETH in AMO, Free ETH in AMO, Total frxETH Deposited into Pools, Total ETH + WETH deposited into Pools, Total frxETH One Coin Withdrawable, Total ETH One Coin Withdrawable, Total frxETH Balanced Withdrawable, Total ETH Balanced Withdrawable, Total frxETH, Total ETH]
    function showAllocations(address _curveAmoAddress) public view returns (uint256[10] memory _allocations) {
        // Fetch the Curve AMO, the pool address, and the pool info
        (CurveLsdAmo _curveAmo, address _poolAddress, CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(
            _curveAmoAddress
        );

        // Get the allocations
        return showAllocationsWithParams(_curveAmo, _poolAddress, _poolInfo, false);
    }

    /// @notice Show allocations of a Curve AMO in frxETH and ETH. Ignores oneCoin values (set to 0)
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _allocations [Free frxETH in AMO, Free ETH in AMO, Total frxETH Deposited into Pools, Total ETH + WETH deposited into Pools, Total frxETH One Coin Withdrawable, Total ETH One Coin Withdrawable, Total frxETH Balanced Withdrawable, Total ETH Balanced Withdrawable, Total frxETH, Total ETH]
    function showAllocationsSkipOneCoin(
        address _curveAmoAddress
    ) public view returns (uint256[10] memory _allocations) {
        // Fetch the Curve AMO, the pool address, and the pool info
        (CurveLsdAmo _curveAmo, address _poolAddress, CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(
            _curveAmoAddress
        );

        // Get the allocations
        return showAllocationsWithParams(_curveAmo, _poolAddress, _poolInfo, true);
    }

    /// @notice Show allocations of a Curve AMO in frxETH and ETH/LSD/WETH
    /// @param _curveAmo Address of the Curve AMO
    /// @param _poolAddress Address of the Curve pool
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @param _skipOneCoinCalcs Save gas if you don't need oneCoin values
    /// @return _allocations [{0} Free frxETH/sfrxETH in AMO, {1} Free ETH/LSD/WETH in AMO, {2} Total frxETH/sfrxETH Deposited into Pools, {3} Total ETH/LSD/WETH deposited into Pools, {4} Total frxETH/sfrxETH One Coin Withdrawable, {5} Total ETH/LSD/WETH One Coin Withdrawable, {6} Total frxETH/sfrxETH Balanced Withdrawable, {7} Total ETH/LSD/WETH Balanced Withdrawable, {8} Total frxETH/sfrxETH, {9} Total ETH/LSD/WETH]
    function showAllocationsWithParams(
        CurveLsdAmo _curveAmo,
        address _poolAddress,
        CurveLsdAmo.PoolInfo memory _poolInfo,
        bool _skipOneCoinCalcs
    ) public view returns (uint256[10] memory _allocations) {
        // ------------Free frxETH/sfrxETH------------
        // [0] Free frxETH/sfrxETH in the AMO
        // Always look for frxETH
        _allocations[0] = frxETH.balanceOf(payable(_curveAmo));

        // Add in sfrxETH if applicable
        if (_poolInfo.frxEthType == CurveLsdAmo.FrxSfrxType.SFRXETH) {
            // Convert to frxETH equivalent
            _allocations[0] += sfrxETH.convertToAssets(sfrxETH.balanceOf(payable(_curveAmo)));
        }

        // ------------Free ETH/LSD/WETH------------
        // [1] Free ETH/LSD/WETH in the AMO
        // Always look for ETH
        _allocations[1] = payable(_curveAmo).balance;

        // Add in LSD/WETH if applicable, assume 1:1 with ETH
        if (_poolInfo.ethType == CurveLsdAmo.EthType.STETH) _allocations[1] += stETH.balanceOf(payable(_curveAmo));
        else if (_poolInfo.ethType == CurveLsdAmo.EthType.WETH) _allocations[1] += WETH.balanceOf(payable(_curveAmo));

        // ------------Withdrawables------------
        {
            // DISUSED
            // // Get the amount deposited into LPs
            // (, uint256[] memory _depositedAmounts, ) = showPoolAccountingWithParams(_curveAmo, _poolAddress, _poolInfo);
            // {
            //     // Account for frxETH/sfrxETH
            //     // [2] Total frxETH/sfrxETH deposited into Pools
            //     // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            //     if (_poolInfo.frxEthType == CurveLsdAmo.FrxSfrxType.FRXETH) {
            //         // frxETH
            //         _allocations[2] += _depositedAmounts[_poolInfo.frxEthIndex];
            //     } else if (_poolInfo.frxEthType == CurveLsdAmo.FrxSfrxType.SFRXETH) {
            //         // sfrxETH: convert to frxETH equivalent
            //         _allocations[2] += sfrxETH.convertToAssets(_depositedAmounts[_poolInfo.frxEthIndex]);
            //     }

            //     // Account for ETH/LSD/WETH
            //     // [3] Total ETH/LSD/WETH deposited into Pools
            //     // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            //     if (
            //         _poolInfo.ethType == CurveLsdAmo.EthType.RAWETH ||
            //         _poolInfo.ethType == CurveLsdAmo.EthType.STETH ||
            //         _poolInfo.ethType == CurveLsdAmo.EthType.WETH
            //     ) {
            //         _allocations[3] += _depositedAmounts[_poolInfo.ethIndex];
            //     }
            // }

            // Need to see if these will fail
            // Optionally skip if you want to save gas and don't need these
            if (!_skipOneCoinCalcs) {
                // ------------One Coin Withdrawables------------
                // Get the amount withdrawable from LPs assuming you pull out all IN ONE COIN
                uint256[2] memory _withdrawablesOne = calcOneCoinsFullLPExitWithParams(
                    _curveAmo,
                    _poolAddress,
                    _poolInfo
                );

                // Account for frxETH/sfrxETH
                // [4] Total withdrawable frxETH/sfrxETH from LPs as ONE COIN
                // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                if (_poolInfo.frxEthType == CurveLsdAmo.FrxSfrxType.FRXETH) {
                    // frxETH
                    _allocations[4] += _withdrawablesOne[_poolInfo.frxEthIndex];
                } else if (_poolInfo.frxEthType == CurveLsdAmo.FrxSfrxType.SFRXETH) {
                    // sfrxETH: convert to frxETH equivalent
                    _allocations[4] += sfrxETH.convertToAssets(_withdrawablesOne[_poolInfo.frxEthIndex]);
                }

                // Account for ETH/LSD/WETH
                // [5] Total withdrawable ETH/LSD/WETH from LPs as ONE COIN
                // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                if (
                    _poolInfo.ethType == CurveLsdAmo.EthType.RAWETH ||
                    _poolInfo.ethType == CurveLsdAmo.EthType.STETH ||
                    _poolInfo.ethType == CurveLsdAmo.EthType.WETH
                ) {
                    _allocations[5] += _withdrawablesOne[_poolInfo.ethIndex];
                }
            }

            {
                // ------------Balanced Withdrawables------------
                // Get the amount withdrawable from LPs assuming you pull out all AT THE CURRENT RATIO / BALANCED
                uint256[2] memory _withdrawablesBalanced = calcBalancedFullLPExitWithParams(
                    _curveAmo,
                    _poolAddress,
                    _poolInfo
                );

                // Account for frxETH/sfrxETH
                // [6] Total withdrawable frxETH/sfrxETH from LPs as BALANCED
                // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                if (_poolInfo.frxEthType == CurveLsdAmo.FrxSfrxType.FRXETH) {
                    // frxETH
                    _allocations[6] += _withdrawablesBalanced[_poolInfo.frxEthIndex];
                } else if (_poolInfo.frxEthType == CurveLsdAmo.FrxSfrxType.SFRXETH) {
                    // sfrxETH: convert to frxETH equivalent
                    _allocations[6] += sfrxETH.convertToAssets(_withdrawablesBalanced[_poolInfo.frxEthIndex]);
                }

                // Account for ETH/LSD/WETH
                // [7] Total withdrawable ETH/LSD/WETH from LPs as BALANCED
                // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                if (
                    _poolInfo.ethType == CurveLsdAmo.EthType.RAWETH ||
                    _poolInfo.ethType == CurveLsdAmo.EthType.STETH ||
                    _poolInfo.ethType == CurveLsdAmo.EthType.WETH
                ) {
                    _allocations[7] += _withdrawablesBalanced[_poolInfo.ethIndex];
                }
            }
        }

        // [8] Total frxETH/sfrxETH. Use BALANCED amounts
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        _allocations[8] = _allocations[0] + _allocations[6];
        // _allocations[2] = _allocations[8];

        // [9] Total ETH/LSD/WETH. Use BALANCED amounts
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        _allocations[9] = _allocations[1] + _allocations[7];
        // _allocations[3] = _allocations[9];
    }

    /// @notice Show allocations of CurveAMO into Curve Pool. Same as showPoolFreeCoinBalancesWithParams but will pre-fetch pool info for you
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _freeCoinBalances Balance of free coins (or ETH) in the AMO. Not in any LP
    function showPoolFreeCoinBalances(
        address _curveAmoAddress
    ) public view returns (uint256[] memory _freeCoinBalances) {
        // Fetch the Curve AMO, the pool address, and the pool info
        (, address _poolAddress, CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(_curveAmoAddress);

        // Get the constituent asset balances
        return showPoolFreeCoinBalancesWithParams(_curveAmoAddress, _poolAddress, _poolInfo);
    }

    /// @notice Show balances of a Curve LP's constituent tokens sitting in the CurveAMO uninvested
    /// @notice Used for before/after token balance checking during withdrawals
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @param _poolAddress Address of the Curve pool
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @return _freeCoinBalances Balances of constituent coins that are in the CurveAMO
    function showPoolFreeCoinBalancesWithParams(
        address _curveAmoAddress,
        address _poolAddress,
        CurveLsdAmo.PoolInfo memory _poolInfo
    ) public view returns (uint256[] memory _freeCoinBalances) {
        // Get the balances for the constituent tokens in the LP
        _freeCoinBalances = new uint256[](2);
        IMinCurvePool _pool = IMinCurvePool(_poolAddress);
        for (uint256 i = 0; i < 2; ) {
            address token_addr = _pool.coins(i);
            if (
                ((_poolInfo.ethType == CurveLsdAmo.EthType.RAWETH && (i == _poolInfo.ethIndex))) ||
                token_addr == ETH_ADDRESS
            ) {
                _freeCoinBalances[i] = _curveAmoAddress.balance;
            } else {
                ERC20 _token = ERC20(token_addr);
                _freeCoinBalances[i] = _token.balanceOf(_curveAmoAddress);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Show pool accounting info. Same as showPoolAccountingWithParams but will pre-fetch pool info for you
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _freeCoinBalances Balance of free coins (or ETH) in the AMO. Not in any LP
    /// @return _depositedLp LP deposited into the pool
    /// @return _poolAndVaultAllocations [Vanilla Curve LP balance, cvxLP in booster, stkcvxLP in farm, total in vaults, total of all]
    /// @dev At no point should naked cvxLP or stkcvxLP be sitting in the AMO. Only vanilla curve LP
    function showPoolAccounting(
        address _curveAmoAddress
    )
        public
        view
        returns (uint256[] memory _freeCoinBalances, uint256 _depositedLp, uint256[5] memory _poolAndVaultAllocations)
    {
        // Fetch the Curve AMO, the pool address, and the pool info
        (CurveLsdAmo _curveAmo, address _poolAddress, CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(
            _curveAmoAddress
        );

        // Get the pool accounting
        return showPoolAccountingWithParams(_curveAmo, _poolAddress, _poolInfo);
    }

    /// @notice Show pool accounting info
    /// @param _curveAmo Address of the Curve AMO
    /// @param _poolAddress Address of the Curve pool
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @return _freeCoinBalances Balance of free coins (or ETH) in the AMO. Not in any LP
    /// @return _depositedLp LP deposited
    /// @return _poolAndVaultAllocations [Vanilla Curve LP balance, cvxLP in booster, stkcvxLP in farm, total in vaults, total of all]
    /// @dev At no point should naked cvxLP or stkcvxLP be sitting in the AMO. Only vanilla curve LP
    function showPoolAccountingWithParams(
        CurveLsdAmo _curveAmo,
        address _poolAddress,
        CurveLsdAmo.PoolInfo memory _poolInfo
    )
        public
        view
        returns (uint256[] memory _freeCoinBalances, uint256 _depositedLp, uint256[5] memory _poolAndVaultAllocations)
    {
        // Get the asset balances
        _freeCoinBalances = showPoolFreeCoinBalancesWithParams(address(_curveAmo), _poolAddress, _poolInfo);
        _depositedLp = _poolInfo.lpDeposited;

        ERC20 _lpToken = ERC20(_poolInfo.lpTokenAddress);
        _poolAndVaultAllocations[0] = _lpToken.balanceOf(payable(_curveAmo)); // Current LP balance

        (uint256 inCvxRewPool, uint256 inStkCvxFarm, uint256 totalInVaults) = lpInVaultsWithParams(
            _curveAmo,
            _poolInfo
        ); // cvxLP in booster + stkcvxLP in farm
        _poolAndVaultAllocations[1] = inCvxRewPool;
        _poolAndVaultAllocations[2] = inStkCvxFarm;
        _poolAndVaultAllocations[3] = totalInVaults;
        _poolAndVaultAllocations[4] = _poolAndVaultAllocations[0] + totalInVaults;
    }

    /// @notice Show lp tokens deposited in Convex BaseRewardPool and Frax FXS farm. Same as lpInVaultsWithParams but will pre-fetch pool info for you
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return inCvxRewPool cvxLP in the Convex BaseRewardPool contract
    /// @return inStkCvxFarm stkcvxLP in the Frax FXS farm contract
    /// @return totalVaultLP Total cvxLP and stkcvxLP in their respective vaults
    function lpInVaults(
        address _curveAmoAddress
    ) public view returns (uint256 inCvxRewPool, uint256 inStkCvxFarm, uint256 totalVaultLP) {
        // Fetch the Curve AMO and the pool info
        (CurveLsdAmo _curveAmo, , CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(_curveAmoAddress);

        // Get the lp vault info
        return lpInVaultsWithParams(_curveAmo, _poolInfo);
    }

    /// @notice Show lp tokens deposited in Convex BaseRewardPool and Frax FXS farm
    /// @param _curveAmo Address of the Curve AMO
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @return inCvxRewPool cvxLP in the Convex BaseRewardPool contract
    /// @return inStkCvxFarm stkcvxLP in the Frax FXS farm contract
    /// @return totalVaultLP Total cvxLP and stkcvxLP in their respective vaults
    function lpInVaultsWithParams(
        CurveLsdAmo _curveAmo,
        CurveLsdAmo.PoolInfo memory _poolInfo
    ) public view returns (uint256 inCvxRewPool, uint256 inStkCvxFarm, uint256 totalVaultLP) {
        // cvxLP
        if (_poolInfo.hasCvxVault) {
            IConvexBaseRewardPool _convexBaseRewardPool = IConvexBaseRewardPool(_poolInfo.rewardsContractAddress);
            inCvxRewPool = _convexBaseRewardPool.balanceOf(address(_curveAmo));
        }

        // stkcvxLP
        if (_poolInfo.hasStkCvxFxsVault) {
            // bytes32[] memory _theseKeks = _curveAmo.getVaultKekIds();
            // for (uint256 i = 0; i < _theseKeks.length; ) {
            //     inStkCvxFarm += _curveAmo.kekIdTotalDeposit(_theseKeks[i]);
            //     unchecked {
            //         ++i;
            //     }
            // }
            IFxsPersonalVault fxsVault = IFxsPersonalVault(_poolInfo.fxsPersonalVaultAddress);
            IFraxFarm farm = IFraxFarm(fxsVault.stakingAddress());
            inStkCvxFarm = farm.lockedLiquidityOf(_poolInfo.fxsPersonalVaultAddress);
        }
        totalVaultLP = inCvxRewPool + inStkCvxFarm;
    }

    /// @notice Calculate expected token amounts if this AMO fully withdraws/exits from the indicated LP. Same as calcOneCoinsFullLPExitWithParams but will pre-fetch pool info for you
    /// @notice Using ONLY the indicated token 100%
    /// @notice NOT the same as calcBalancedFullLPExit because you are ignoring / not withdrawing other tokens
    /// @notice NOT necessarily frxETH and ETH/LSD/WETH
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _withdrawables Total withdrawable token0 directly from pool, Total withdrawable token1 directly from pool]
    function calcOneCoinsFullLPExit(address _curveAmoAddress) public view returns (uint256[2] memory _withdrawables) {
        // Fetch the Curve AMO, the pool address, and the pool info
        (CurveLsdAmo _curveAmo, address _poolAddress, CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(
            _curveAmoAddress
        );

        // Calculate the token amounts
        return calcOneCoinsFullLPExitWithParams(_curveAmo, _poolAddress, _poolInfo);
    }

    /// @notice Calculate expected token amounts if this AMO fully withdraws/exits from the indicated LP.
    /// @notice Using ONLY the indicated token 100%
    /// @notice NOT the same as calcBalancedFullLPExit because you are ignoring / not withdrawing other tokens
    /// @notice NOT necessarily frxETH and ETH/LSD/WETH
    /// @param _curveAmo Address of the Curve AMO
    /// @param _poolAddress Address of the Curve pool
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @return _withdrawables Total withdrawable token0 directly from pool, Total withdrawable token1 directly from pool]
    function calcOneCoinsFullLPExitWithParams(
        CurveLsdAmo _curveAmo,
        address _poolAddress,
        CurveLsdAmo.PoolInfo memory _poolInfo
    ) public view returns (uint256[2] memory _withdrawables) {
        // Get the LP token balance
        (, , uint256[5] memory _poolAndVaultAllocations) = showPoolAccountingWithParams(
            _curveAmo,
            _poolAddress,
            _poolInfo
        );
        uint256 _oneStepBurningLp = _poolAndVaultAllocations[4];

        // Different ABIs should not matter here
        if (_oneStepBurningLp == 0) {
            _withdrawables[0] = 0;
            _withdrawables[1] = 0;
        } else if (_poolInfo.lpAbiType == CurveLsdAmo.LpAbiType.TWOCRYPTO) {
            // Use uint256
            IPool2Crypto pool = IPool2Crypto(_poolAddress);
            _withdrawables[0] = pool.calc_withdraw_one_coin(_oneStepBurningLp, 0);
            _withdrawables[1] = pool.calc_withdraw_one_coin(_oneStepBurningLp, 1);
        } else {
            // Use int128
            IPoolLSDETH pool = IPoolLSDETH(_poolAddress);
            _withdrawables[0] = pool.calc_withdraw_one_coin(_oneStepBurningLp, 0);
            _withdrawables[1] = pool.calc_withdraw_one_coin(_oneStepBurningLp, 1);
        }
    }

    /// @notice Calculate expected token amounts if this AMO fully withdraws/exits from the indicated LP. Same as calcBalancedFullLPExitWithParams but will pre-fetch pool info for you
    /// @notice NOT necessarily frxETH and ETH/LSD/WETH
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _withdrawables Recieving amount of each token after full withdrawal based on current pool ratio
    function calcBalancedFullLPExit(address _curveAmoAddress) public view returns (uint256[2] memory _withdrawables) {
        // Fetch the Curve AMO, the pool address, and the pool info
        (CurveLsdAmo _curveAmo, address _poolAddress, CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(
            _curveAmoAddress
        );

        // Calculate the token amounts
        return calcBalancedFullLPExitWithParams(_curveAmo, _poolAddress, _poolInfo);
    }

    /// @notice Calculate expected token amounts if this AMO fully withdraws/exits from the indicated LP
    /// @notice NOT necessarily frxETH and ETH/LSD/WETH
    /// @param _curveAmo Address of the Curve AMO
    /// @param _poolAddress Address of the Curve pool
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @return _withdrawables Recieving amount of each token after full withdrawal based on current pool ratio
    function calcBalancedFullLPExitWithParams(
        CurveLsdAmo _curveAmo,
        address _poolAddress,
        CurveLsdAmo.PoolInfo memory _poolInfo
    ) public view returns (uint256[2] memory _withdrawables) {
        // Get the LP token balance
        (, , uint256[5] memory _poolAndVaultAllocations) = showPoolAccountingWithParams(
            _curveAmo,
            _poolAddress,
            _poolInfo
        );
        uint256 _oneStepBurningLp = _poolAndVaultAllocations[4];

        // Get the withdrawables
        _withdrawables = calcTknsForLPBalancedWithParams(_poolAddress, _poolInfo, _oneStepBurningLp);
    }

    // /// @notice Show Curve Pool parameters. Same as showPoolPartialInfoWithParams but will pre-fetch pool info for you
    // /// @param _curveAmoAddress Address of the Curve AMO
    // /// @return _lpAbiType ABI type of the pool
    // /// @return _frxEthType frxETH vs sfrxETH vs neither
    // /// @return _frxEthIndex The coin index of frxETH, if present
    // /// @return _ethType ETH vs LSD vs WETH vs neither
    // /// @return _ethIndex The coin index of ETH/LSD/WETH, if present
    // /// @return _hasCvxVault If there is a cvxLP vault
    // function showPoolPartialInfo(
    //     address _curveAmoAddress
    // )
    //     public
    //     view
    //     returns (
    //         CurveLsdAmo.LpAbiType _lpAbiType,
    //         CurveLsdAmo.FrxSfrxType _frxEthType,
    //         uint256 _frxEthIndex,
    //         CurveLsdAmo.EthType _ethType,
    //         uint256 _ethIndex,
    //         bool _hasCvxVault
    //     )
    // {
    //     // Fetch the pool info
    //     (, , CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(_curveAmoAddress);

    //     // Return the partial pool info
    //     return showPoolPartialInfoWithParams(_poolInfo);
    // }

    // /// @notice Show Curve Pool parameters
    // /// @param _poolInfo PoolInfo struct of the _poolAddress
    // /// @return _lpAbiType ABI type of the pool
    // /// @return _frxEthType If frxETH is present
    // /// @return _frxEthIndex The coin index of frxETH, if present
    // /// @return _ethType ETH vs LSD vs WETH vs neither
    // /// @return _ethIndex The coin index of ETH/LSD/WETH, if present
    // /// @return _hasCvxVault If there is a cvxLP vault
    // function showPoolPartialInfoWithParams(
    //     CurveLsdAmo.PoolInfo memory _poolInfo
    // )
    //     public
    //     view
    //     returns (
    //         CurveLsdAmo.LpAbiType _lpAbiType,
    //         CurveLsdAmo.FrxSfrxType _frxEthType,
    //         uint256 _frxEthIndex,
    //         CurveLsdAmo.EthType _ethType,
    //         uint256 _ethIndex,
    //         bool _hasCvxVault
    //     )
    // {
    //     _lpAbiType = _poolInfo.lpAbiType;
    //     _frxEthType = _poolInfo.frxEthType;
    //     _frxEthIndex = _poolInfo.frxEthIndex;
    //     _ethType = _poolInfo.ethType;
    //     _ethIndex = _poolInfo.ethIndex;
    //     _hasCvxVault = _poolInfo.hasCvxVault;
    // }

    /// @notice Show max LP for the AMO. Same as showAmoMaxLPWithParams but will pre-fetch pool info for you
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _lpMaxAllocation  Maximum LP the AMO can have
    function showAmoMaxLP(address _curveAmoAddress) public view returns (uint256 _lpMaxAllocation) {
        // Fetch the Curve AMO, the pool address, and the pool info
        (, , CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(_curveAmoAddress);

        // Return the max allocations
        return showAmoMaxLPWithParams(_poolInfo);
    }

    /// @notice Show max LP for the AMO
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @return _lpMaxAllocation Maximum LP the AMO can have
    function showAmoMaxLPWithParams(
        CurveLsdAmo.PoolInfo memory _poolInfo
    ) public view returns (uint256 _lpMaxAllocation) {
        _lpMaxAllocation = _poolInfo.lpMaxAllocation;
    }

    /// @notice Show Pool LP Token Address. Same as showPoolLPTokenAddressWithParams but will pre-fetch pool info for you
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _lpTokenAddress Address of the LP token for the provided Curve AMOs LP pool. Might be the same address as the pool
    function showPoolLPTokenAddress(address _curveAmoAddress) public view returns (address _lpTokenAddress) {
        // Fetch the Curve AMO, the pool address, and the pool info
        (, , CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(_curveAmoAddress);

        // Get the LP token address
        return showPoolLPTokenAddressWithParams(_poolInfo);
    }

    /// @notice Show Pool LP Token Address
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @return _lpTokenAddress Address of the LP token for the provided Curve AMOs LP pool. Might be the same address as the pool
    function showPoolLPTokenAddressWithParams(
        CurveLsdAmo.PoolInfo memory _poolInfo
    ) public view returns (address _lpTokenAddress) {
        _lpTokenAddress = _poolInfo.lpTokenAddress;
    }

    /// @notice Show all rewards of CurveAMO. Same as showPoolRewardsWithParams but will pre-fetch pool info for you
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _crvReward Pool CRV rewards
    /// @return _extraRewardAmounts [CRV claimable, CVX claimable, cvxCRV claimable]
    /// @return _extraRewardTokens [Token Address]
    /// @return _extraRewardsLength Length of the extra reward arrays
    function showPoolRewards(
        address _curveAmoAddress
    )
        public
        view
        returns (
            uint256 _crvReward,
            uint256[] memory _extraRewardAmounts,
            address[] memory _extraRewardTokens,
            uint256 _extraRewardsLength
        )
    {
        // Fetch the Curve AMO and the pool info
        (CurveLsdAmo _curveAmo, , CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(_curveAmoAddress);

        // Return the pool rewards
        return showPoolRewardsWithParams(_curveAmo, _poolInfo);
    }

    /// @notice Show all rewards of CurveAMO
    /// @param _curveAmo Address of the Curve AMO
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @return _crvReward Pool CRV rewards
    /// @return _extraRewardAmounts [CRV claimable, CVX claimable, cvxCRV claimable]
    /// @return _extraRewardTokens [Token Address]
    /// @return _extraRewardsLength Length of the extra reward arrays
    function showPoolRewardsWithParams(
        CurveLsdAmo _curveAmo,
        CurveLsdAmo.PoolInfo memory _poolInfo
    )
        public
        view
        returns (
            uint256 _crvReward,
            uint256[] memory _extraRewardAmounts,
            address[] memory _extraRewardTokens,
            uint256 _extraRewardsLength
        )
    {
        // Get the Base Reward pool
        IConvexBaseRewardPool _convexBaseRewardPool = IConvexBaseRewardPool(_poolInfo.rewardsContractAddress);

        // Calculate the amount of CRV claimable
        _crvReward = _convexBaseRewardPool.earned(address(_curveAmo));

        // Handle extra rewards
        _extraRewardsLength = _convexBaseRewardPool.extraRewardsLength();

        // Initialize the arrays
        _extraRewardAmounts = new uint256[](_extraRewardsLength);
        _extraRewardTokens = new address[](_extraRewardsLength);

        // Loop through the extra rewards
        for (uint256 i = 0; i < _extraRewardsLength; ) {
            IVirtualBalanceRewardPool _convexExtraRewardsPool = IVirtualBalanceRewardPool(
                _convexBaseRewardPool.extraRewards(i)
            );
            _extraRewardAmounts[i] = _convexExtraRewardsPool.earned(address(_curveAmo));
            _extraRewardTokens[i] = _convexExtraRewardsPool.rewardToken();
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Show all CVX rewards
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _cvxRewards
    function showCVXRewards(address _curveAmoAddress) public view returns (uint256 _cvxRewards) {
        _cvxRewards = CVX_REWARD_POOL.earned(_curveAmoAddress); // cvxCRV claimable
    }

    /// @notice Show Curve Pool parameters regarding vaults. Same as showPoolVaultsWithParams but will pre-fetch pool info for you
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _lpDepositPid
    /// @return _rewardsContractAddress
    /// @return _fxsPersonalVaultAddress
    function showPoolVaults(
        address _curveAmoAddress
    ) public view returns (uint256 _lpDepositPid, address _rewardsContractAddress, address _fxsPersonalVaultAddress) {
        // Fetch the pool info
        (, , CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(_curveAmoAddress);

        // Return the pool vault info
        return showPoolVaultsWithParams(_poolInfo);
    }

    /// @notice Show Curve Pool parameters regarding vaults
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @return _lpDepositPid
    /// @return _rewardsContractAddress
    /// @return _fxsPersonalVaultAddress
    function showPoolVaultsWithParams(
        CurveLsdAmo.PoolInfo memory _poolInfo
    ) public view returns (uint256 _lpDepositPid, address _rewardsContractAddress, address _fxsPersonalVaultAddress) {
        // Get the struct info
        _lpDepositPid = _poolInfo.lpDepositPid;
        _rewardsContractAddress = _poolInfo.rewardsContractAddress;
        _fxsPersonalVaultAddress = _poolInfo.fxsPersonalVaultAddress;
    }

    /// @notice Info for depositing/withdrawing a given amount of one coin, assuming you deposit/withdraw at the current ratio. Same as calcMiscBalancedInfoWithParams but will pre-fetch pool info for you
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @param _desiredCoinIdx The index of the token you have/want
    /// @param _desiredCoinAmt Amount of token you have/want
    /// @return _lpAmount LP Amount generated/needed
    /// @return _undesiredCoinAmt Amount of undesired coins needed/generated
    /// @return _coinAmounts _desiredCoinAmt and _undesiredCoinAmt in their proper indices
    /// @return _lpPerCoinsBalancedE18 Amount of LP pet each token (coin 0 and coin 1). Useful for checking add/remove liquidity oneCoin positive vs negative slippage
    /// @return _lp_virtual_price The virtual price of the LP token
    function calcMiscBalancedInfo(
        address _curveAmoAddress,
        uint256 _desiredCoinIdx,
        uint256 _desiredCoinAmt
    )
        public
        view
        returns (
            uint256 _lpAmount,
            uint256 _undesiredCoinAmt,
            uint256[2] memory _coinAmounts,
            uint256[2] memory _lpPerCoinsBalancedE18,
            uint256 _lp_virtual_price
        )
    {
        // Fetch the pool address and the pool info
        (, address _poolAddress, CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(_curveAmoAddress);

        // Get the LP and undesired coin amounts
        return
            calcMiscBalancedInfoWithParams(_curveAmoAddress, _poolAddress, _poolInfo, _desiredCoinIdx, _desiredCoinAmt);
    }

    /// @notice Info for depositing/withdrawing a given amount of one coin, assuming you deposit/withdraw at the current ratio
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @param _desiredCoinIdx The index of the token you need/want
    /// @param _desiredCoinAmt Amount of token you have/expect
    /// @return _lpAmount LP Amount generated/needed
    /// @return _undesiredCoinAmt Amount of undesired coin needed or generated
    /// @return _coinAmounts Helper array with the coin amounts needed
    /// @return _lpPerCoinsBalancedE18 Amount of LP that each token (coin 0 and coin 1). Useful for checking add/remove liquidity oneCoin positive vs negative slippage
    /// @return _lp_virtual_price The virtual price of the LP token
    function calcMiscBalancedInfoWithParams(
        address _curveAmoAddress,
        address _poolAddress,
        CurveLsdAmo.PoolInfo memory _poolInfo,
        uint256 _desiredCoinIdx,
        uint256 _desiredCoinAmt
    )
        public
        view
        returns (
            uint256 _lpAmount,
            uint256 _undesiredCoinAmt,
            uint256[2] memory _coinAmounts,
            uint256[2] memory _lpPerCoinsBalancedE18,
            uint256 _lp_virtual_price
        )
    {
        // Fetch the pool
        IMinCurvePool pool = IMinCurvePool(_poolAddress);

        // Get the total LP supply
        uint256 _lpTotalSupply = ERC20(_poolInfo.lpTokenAddress).totalSupply();

        // Get the undesired token index
        uint256 _undesiredCoinIdx = _desiredCoinIdx == 0 ? 1 : 0;

        // Calculate the amount of undesired tokens
        _undesiredCoinAmt = (_desiredCoinAmt * pool.balances(_undesiredCoinIdx)) / (pool.balances(_desiredCoinIdx));

        // Fill in the amount of LP per token
        // I.e. if you put in 1 coin0 AND <BALANCED X AMT> coin1, how much LP do you get. And vice versa.
        _lpPerCoinsBalancedE18[0] = (_lpTotalSupply * 1e18) / pool.balances(0);
        _lpPerCoinsBalancedE18[1] = (_lpTotalSupply * 1e18) / pool.balances(1);

        // Fill in the return array. Included as a shortcut for various downstream functions
        _coinAmounts[_desiredCoinIdx] = _desiredCoinAmt;
        _coinAmounts[_undesiredCoinIdx] = _undesiredCoinAmt;

        // Return the virtual_price too
        _lp_virtual_price = pool.get_virtual_price();

        // Calculate the amount of LP
        // OLD METHOD
        _lpAmount =
            (_desiredCoinAmt * (ERC20(_poolInfo.lpTokenAddress).totalSupply())) /
            (pool.balances(_desiredCoinIdx));
        // NEW METHOD
        // _lpAmount = ((_desiredCoinAmt + _undesiredCoinAmt) * 1e18) / _lp_virtual_price;
    }

    // Example with 1 ETH and 3.31... frxETH
    // USE BLOCK 19000000 FOR https://etherscan.io/address/0x9c3b46c0ceb5b9e304fcd6d88fc50f7dd24b31bc#code
    // -------------------------------------
    // balances(0) = 10180818140651672236120
    // balances(1) = 33743836110495904554204
    // get_virtual_price() = 1000405078153916664
    // totalSupply() = 43898012684596754787230
    // (0) -> (1) ratio = 301708973079233384 = 0.301708973079233384
    // (1) -> (0) ratio = 3314452300818327750 = 3.31445230081832775
    // _undesiredCoinAmt = 3314452300818327750
    // -------------------------------------
    // _lpPerCoinsBalancedE18[0] = (43898012684596754787230 * 1e18) / 10180818140651672236120;
    // = 4311835461367631435 = 4.31183546136763143579

    // _lpPerCoinsBalancedE18[1] = (43898012684596754787230 * 1e18) / 33743836110495904554204;
    // = 1300919449135850574 = 1.300919449135850574

    // -------------------------------------
    // calc_token_amount([1000000000000000000, 0], true) (all WETH)
    // 1000860158890189845 LP

    // calc_token_amount([1000000000000000000, 0], true) (all frxETH)
    // 998858143934587105 LP

    // calc_token_amount([1000000000000000000, 3314452300818327750], true) (1 WETH, 3.31...e18 frxETH (Balanced remainder))
    // 4311835461367631435 LP

    // -------------------------------------
    // OLD METHOD, 1 ETH BALANCED
    // _lpAmount =
    //         (_desiredCoinAmt * (ERC20(_poolInfo.lpTokenAddress).totalSupply())) /
    //         (pool.balances(_desiredCoinIdx));
    // _lpAmount =
    //         (1e18 * 43898012684596754787230) /
    //         (10180818140651672236120);
    // = 4311835461367631435 = 4.31183546136763143579

    // -------------------------------------
    // NEW METHOD (balance vs lpPerCoinsBalanced), 1 ETH BALANCED
    // _lpAmount = (_desiredCoinAmt + _undesiredCoinAmt) / _lp_virtual_price;
    // _lpAmount = ((1000000000000000000 + 3314452300818327750) * 1e18) / 1000405078153916664;
    // = 4312705318109681301 = 4.312705318109681301

    /// @notice Get the balances of the underlying tokens for the given amount of LP, assuming you withdraw at the current ratio. Same as calcTknsForLPBalancedWithParams but will pre-fetch pool info for you
    /// @notice May not necessarily = balanceOf(<underlying token address>) due to accumulated fees
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @param _lpAmount LP Amount
    /// @return _withdrawables Amount of each token expected
    function calcTknsForLPBalanced(
        address _curveAmoAddress,
        uint256 _lpAmount
    ) public view returns (uint256[2] memory _withdrawables) {
        // Fetch the pool address and the pool info
        (, address _poolAddress, CurveLsdAmo.PoolInfo memory _poolInfo) = getCurveInfoPack(_curveAmoAddress);

        // Get the token balances
        return calcTknsForLPBalancedWithParams(_poolAddress, _poolInfo, _lpAmount);
    }

    /// @notice Get the balances of the underlying tokens for the given amount of LP, assuming you withdraw at the current ratio
    /// @notice May not necessarily = balanceOf(<underlying token address>) due to accumulated fees
    /// @param _poolAddress Address of the Curve pool
    /// @param _poolInfo PoolInfo struct of the _poolAddress
    /// @param _lpAmount LP Amount
    /// @return _withdrawables Amount of each token expected
    function calcTknsForLPBalancedWithParams(
        address _poolAddress,
        CurveLsdAmo.PoolInfo memory _poolInfo,
        uint256 _lpAmount
    ) public view returns (uint256[2] memory _withdrawables) {
        // Get the total LP supply
        ERC20 _lpToken = ERC20(_poolInfo.lpTokenAddress);
        uint256 _lpTotalSupply = _lpToken.totalSupply();

        // Get the Curve pool
        IMinCurvePool pool = IMinCurvePool(_poolAddress);

        // Force an entrance to prevent a read reentrancy
        pool.get_virtual_price();

        for (uint256 i = 0; i < 2; ) {
            _withdrawables[i] = (pool.balances(i) * _lpAmount) / _lpTotalSupply;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Set the frxETH and ETH oracles
    /// @param _frxethOracle Address of the frxETH oracle
    /// @param _ethOracle Address of the ETH oracle
    function setOracles(address _frxethOracle, address _ethOracle) external onlyOwner {
        priceFeedfrxEthUsd = ISfrxEthUsdDualOracle(_frxethOracle);
        priceFeedEthUsd = AggregatorV3Interface(_ethOracle);

        // Set the Chainlink oracle decimals
        oracleFrxEthUsdDecimals = priceFeedfrxEthUsd.decimals();
        chainlinkEthUsdDecimals = priceFeedEthUsd.decimals();
    }

    /// @notice Sets max acceptable time since the updatedAt for the oracles
    /// @param _secsTolerance Tolerance in seconds
    function setOracleTimeTolerance(uint256 _secsTolerance) external onlyOwner {
        oracleTimeTolerance = _secsTolerance;
    }

    /* =========================================== ERRORS =========================================== */

    /// @notice When the oracle returns an invalid price
    error InvalidOraclePrice();

    /// @notice When getEstLpPriceEthOrUsdE18() is provided with an invalid LP to price
    error InvalidLpAbiType();
}
