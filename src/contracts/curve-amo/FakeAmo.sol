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
// ============================= FakeAmo ==============================
// ====================================================================
// Invests ETH and frxETH provided by the Lending Pool (via the Ether Router) on Convex to earn yield for the IncentivesPool
// IMPORTANT: Make sure the Curve Pair does not have the remove_liquidity raw_call for ETH [https://chainsecurity.com/curve-lp-oracle-manipulation-post-mortem/]
// or if it does, the read reentrancy is handled properly
// Only handles these types of pairs, with 2 tokens (LSD = rETH, frxETH, stETH, etc):
// 1) <A LSD>/ETH
// 2) <A LSD>/<Another LSD>
// One LP/cvxLP/stkcvxLP set per AMO

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna
// Amirnader Aghayeghazvini: https://github.com/amirnader-ghazvini

// Reviewer(s) / Contributor(s)
// Dennis: https://github.com/denett
// Sam Kazemian: https://github.com/samkazemian

import { CurveLsdAmoHelper } from "./CurveLsdAmoHelper.sol";
import { EtherRouterRole } from "../access-control/EtherRouterRole.sol";
import { I2PoolNoLendingNG } from "./interfaces/curve/I2PoolNoLendingNG.sol";
import { IConvexBaseRewardPool } from "./interfaces/convex/IConvexBaseRewardPool.sol";
import { IConvexBooster } from "./interfaces/convex/IConvexBooster.sol";
import { IConvexClaimZap } from "./interfaces/convex/IConvexClaimZap.sol";
import { IConvexFxsBooster } from "./interfaces/convex/IConvexFxsBooster.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IFraxFarm } from "./interfaces/frax/IFraxFarm.sol";
import { IFrxEth } from "../interfaces/IFrxEth.sol";
import { IFrxEthEthCurvePool } from "./interfaces/frax/IFrxEthEthCurvePool.sol";
import { IFxsPersonalVault } from "./interfaces/convex/IFxsPersonalVault.sol";
import { IMinCurvePool } from "./interfaces/curve/IMinCurvePool.sol";
import { IPool2Crypto } from "./interfaces/curve/IPool2Crypto.sol";
import { IPool2LSDStable } from "./interfaces/curve/IPool2LSDStable.sol";
import { IPoolLSDETH } from "./interfaces/curve/IPoolLSDETH.sol";
import { ISfrxEth } from "../interfaces/ISfrxEth.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { IstETH } from "./interfaces/lsd/IstETH.sol";
import { IstETHETH } from "./interfaces/curve/IstETHETH.sol";
import { OperatorRole } from "frax-std/access-control/v2/OperatorRole.sol";
import { PublicReentrancyGuard } from "frax-std/access-control/v2/PublicReentrancyGuard.sol";
import { SafeCastLibrary } from "../libraries/SafeCastLibrary.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Timelock2Step } from "frax-std/access-control/v2/Timelock2Step.sol";
import { WhitelistedExecutor } from "./WhitelistedExecutor.sol";

contract FakeAmo is OperatorRole, Timelock2Step, PublicReentrancyGuard {
    CurveLsdAmoHelper public amoHelper;

    /// @notice constructor
    /// @param _ownerAddress Address of CurveAMO Operator
    /// @param _amoHelper Address of AMO Helper
    constructor(address _ownerAddress, address _amoHelper) OperatorRole(_ownerAddress) Timelock2Step(_ownerAddress) {
        amoHelper = CurveLsdAmoHelper(_amoHelper);
    }

    /// @notice Mocked
    function depositEther() external payable {
        // Do nothing for now.
    }

    /// @notice Needs to be here to receive ETH
    fallback() external payable {
        // This function is executed on a call to the contract if none of the other
        // functions match the given function signature, or if no data is supplied at all
    }

    /// @notice Needs to be here to receive ETH
    receive() external payable {
        // Do nothing for now.
    }

    /// @notice Recover ETH
    /// @param _amount Amount of ETH to recover
    function recoverEther(uint256 _amount) external {
        _requireSenderIsTimelock();

        (bool _success, ) = address(timelockAddress).call{ value: _amount }("");
        if (!_success) revert InvalidRecoverEtherTransfer();

        emit EtherRecovered(_amount);
    }

    /// @notice When recoverEther is called
    /// @param amount The amount of Ether recovered
    event EtherRecovered(uint256 amount);

    /// @notice Invalid ETH transfer during recoverEther
    error InvalidRecoverEtherTransfer();
}
