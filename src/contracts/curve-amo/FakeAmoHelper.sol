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
// ========================== FakeAmoHelper ===========================
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

contract FakeAmoHelper is Ownable2Step {
    /// @notice constructor
    /// @param _ownerAddress Address of CurveAMO Operator
    constructor(address _ownerAddress) Ownable(_ownerAddress) {}

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
        // Do nothing
    }

    /// @notice Lending pool can pull out ETH/LSD/WETH by unwinding vaults and/or FXS Vaulted LP. Uint96 / packed version
    /// @param _curveAmoAddress Address of the Curve AMO
    /// @return _allocsPacked Returned allocations in condensed form
    /// @dev used by the lending pool to determine utilization rates
    function getConsolidatedEthFrxEthBalancePacked(
        address _curveAmoAddress
    ) external view returns (ShowAmoBalancedAllocsPacked memory _allocsPacked) {
        // Do nothing
    }
}
