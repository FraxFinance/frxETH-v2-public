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
// =========================== CurveLsdAmo ============================
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
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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
// import "forge-std/console2.sol";

/// @notice Used for the constructor
/// @param timelockAddress Address of the governance timelock
/// @param operatorAddress Address of the operator
/// @param amoHelperAddress Address of the Curve AMO Helper
/// @param frxEthMinterAddress Address of the frxETH Minter
/// @param etherRouter Address of the Ether Router
/// @param poolConfigData Pool config data for the Curve LP
/// @param cvxAndStkcvxData Config data for the cvxLP and stkcvxLP
struct CurveLsdAmoConstructorParams {
    address timelockAddress;
    address operatorAddress;
    address amoHelperAddress;
    address frxEthMinterAddress;
    address payable etherRouterAddress;
    bytes poolConfigData;
    bytes cvxAndStkcvxData;
}

contract CurveLsdAmo is EtherRouterRole, OperatorRole, Timelock2Step, WhitelistedExecutor, PublicReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCastLibrary for int128; // Compiler complained about the comma in `using SafeCastLibrary for int128, uint256;`
    using SafeCastLibrary for uint256;

    /* ============================================= STATE VARIABLES ==================================================== */

    // Addresses
    address public frxEthMinterAddress;
    address public poolAddress;
    address private constant CVXCRV_ADDRESS = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address private constant CRV_ADDRESS = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address private constant FXS_ADDRESS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;

    // Slippages and Max Pool Ratio
    uint256 public depositWithdrawSlippageRouterE6 = 600; // 600 / 1000000 = 0.06%
    uint256 public depositWithdrawSlippageTimelockOperatorE6 = 1000; // 1000 / 1000000 = 0.1% (Slightly more forgiving)
    uint256 public extraWithdrawalLpPctE6 = 100; // 100 / 1000000 = 0.01% (Mainly for rounding issues)
    uint256 public swapSlippageE6 = 600; // 600 / 1000000 = 0.06%
    uint256 public minTkn0ToTkn1RatioE6 = 150_000; // 15% (e.g. 15 tkn0 to 85 tkn1). Used to limit sandwiching in _depositToCurveLP
    uint256 public maxTkn0ToTkn1RatioE6 = 850_000; // 85% (e.g. 85 tkn0 to 15 tkn1). Used to limit sandwiching in _depositToCurveLP

    // Token Instances
    CurveLsdAmoHelper public amoHelper;
    IMinCurvePool public pool;
    IFrxEth private constant frxETH = IFrxEth(0x5E8422345238F34275888049021821E8E08CAa1f);
    ISfrxEth private constant sfrxETH = ISfrxEth(0xac3E018457B222d93114458476f3E3416Abbe38F);
    IWETH private constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IstETH private constant stETH = IstETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IERC20 private constant CVX = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    // Convex-related
    IConvexBooster private convexBooster = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IConvexFxsBooster private convexFXSBooster = IConvexFxsBooster(0xD8Bd5Cdd145ed2197CB16ddB172DF954e3F28659);
    IConvexClaimZap private convexClaimZap = IConvexClaimZap(0x4890970BB23FCdF624A0557845A29366033e6Fa2);

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

    struct PoolInfo {
        bool hasCvxVault; // If there is a cvxLP vault
        bool hasStkCvxFxsVault; // If there is a stkcvxLP vault
        uint8 frxEthIndex; // coins() index of frxETH/sfrxETH
        uint8 ethIndex; // coins() index of ETH/stETH/WETH
        address rewardsContractAddress; // Address for the Convex BaseRewardPool for the cvxLP
        address fxsPersonalVaultAddress; // Address for the stkcvxLP vault, if present
        // address poolAddress; // Where the actual tokens are in the pool
        address lpTokenAddress; // The LP token address. Sometimes the same as poolAddress
        address[2] poolCoins; // The addresses of the coins in the pool
        uint32 lpDepositPid; // _convexBaseRewardPool.pid
        LpAbiType lpAbiType; // General pool parameter
        FrxSfrxType frxEthType; // frxETH and sfrxETH
        EthType ethType; // ETH, WETH, and LSDs
        uint256 lpDeposited; // Total LP
        uint256 lpMaxAllocation; // Max token allocation per pool
    }

    // PoolInfo struct
    PoolInfo private poolInfo;

    // FXS Personal Vault
    bytes32[] private vaultKekIds;
    mapping(bytes32 => uint256) public kekIdTotalDeposit;

    /* =============================================== CONSTRUCTOR ====================================================== */

    /// @notice constructor
    /// @param _params CurveLsdAmoConstructorParams
    constructor(
        CurveLsdAmoConstructorParams memory _params
    )
        OperatorRole(_params.operatorAddress)
        Timelock2Step(_params.timelockAddress)
        EtherRouterRole(_params.etherRouterAddress)
    {
        frxEthMinterAddress = _params.frxEthMinterAddress;
        amoHelper = CurveLsdAmoHelper(_params.amoHelperAddress);

        // Configure the pool
        _addOrSetPool(_params.poolConfigData);

        // Decode
        (address _baseRewardPoolAddress, uint256 _convexPid) = abi.decode(_params.cvxAndStkcvxData, (address, uint256));

        // Configure the cvxLP and stkcvxLP vaults
        if (_baseRewardPoolAddress != address(0)) {
            // Configure the cvxLP vault
            _setPoolVault(_baseRewardPoolAddress);

            // Configure the stkcvx vault (not cvxLP). Pid is for stkcvxLP, not cvxLP
            _createFxsVault(_convexPid);
        }

        // Make sure get_virtual_price() exists on the pool
        pool.get_virtual_price();
    }

    /* ================================================ MODIFIERS ======================================================= */

    /// @notice Makes sure the function ends within the budget
    modifier onBudget() {
        _;
        PoolInfo memory p = poolInfo;
        if (p.lpDeposited > p.lpMaxAllocation) {
            revert OverLpBudget();
        }
    }

    /* ============================================== INTERNAL FUNCTIONS =================================================== */

    /// @notice Checks if msg.sender is the timelock address, operator, or Ether Router
    function _requireIsTimelockOperatorOrEthRouter() internal view {
        if (
            !((msg.sender == timelockAddress) ||
                (msg.sender == operatorAddress) ||
                (msg.sender == address(etherRouter)))
        ) revert NotTimelockOperatorOrEtherRouter();
    }

    /// @notice Checks if msg.sender is the timelock address or the operator
    function _requireIsTimelockOrOperator() internal view {
        if (!((msg.sender == timelockAddress) || (msg.sender == operatorAddress))) revert NotTimelockOrOperator();
    }

    /// @notice Checks if the CVX vault exists
    function _requireHasCVXVault() internal view {
        if (!poolInfo.hasCvxVault) revert PoolNoCVXVault();
    }

    /// @notice Checks if the FXS vault exists
    function _requirehasStkCvxFxsVault() internal view {
        if (!poolInfo.hasStkCvxFxsVault) revert PoolNoFXSVault();
    }

    /* ========================================================================================================== */
    /* ================================================== VIEWS ================================================= */
    /* ========================================================================================================== */

    /// @notice Show full Curve Pool parameters
    function getFullPoolInfo() external view returns (PoolInfo memory) {
        return poolInfo;
    }

    /// @notice Get the array of kek_ids
    function getVaultKekIds() external view returns (bytes32[] memory) {
        return vaultKekIds;
    }

    /* ========================================================================================================== */
    /* ============================================ DEPOSIT FUNCTIONS =========================================== */
    /* ========================================================================================================== */

    /// @notice Ether Router sends ETH and it will be invested into the defaultFXSVault's cvxLP booster
    /// @dev If you want to do this manually, do depositToCurveLP() first, then depositToCvxLPVault()
    function depositEther() external payable {
        // Deposit in the default strategy
        // Also checks to make sure only the Ether Router is sending this to avoid griefs and confusion
        _investEthInDefaultCvxLPVault(msg.value, false);
    }

    /// @notice (Internal) Curve LP -> cvxLP (in Convex's vault). Deposit Pool LP tokens, convert them to Convex LP, and deposit into their vault
    /// @param _poolLpIn Amount of LP for deposit
    function _depositCurveLPToVaultedCvxLP(uint256 _poolLpIn) internal {
        _requireHasCVXVault();

        // Approve the isMetaPool LP tokens for the vault contract
        ERC20 _poolLpToken = ERC20(poolInfo.lpTokenAddress);
        _poolLpToken.approve(address(convexBooster), _poolLpIn);

        // Deposit the isMetaPool LP into the vault contract
        convexBooster.deposit(poolInfo.lpDepositPid, _poolLpIn, true);

        emit DepositToCvxLPVault(_poolLpIn);
    }

    /// @notice Curve LP direct to -> stkcvxLP (in the Frax farm). Deposit Pool LP tokens, convert them to Convex LP, and deposit into their vault
    /// @param _poolLpIn Amount of LP for deposit
    /// @param _kekId The kek_id to deposit more into. Leave as 0x if you want to create a new one.
    /// @return _kekIdReturned lock stake ID
    function depositCurveLPToVaultedStkCvxLP(
        uint256 _poolLpIn,
        bytes32 _kekId
    ) external returns (bytes32 _kekIdReturned) {
        _requireIsTimelockOrOperator();
        _requirehasStkCvxFxsVault();

        // Approve the LP tokens for the vault contract
        ERC20 _poolLpToken = ERC20(poolInfo.lpTokenAddress);
        _poolLpToken.approve(poolInfo.fxsPersonalVaultAddress, _poolLpIn);

        // Instantiate the FXS vault contract
        IFxsPersonalVault _fxsVault = IFxsPersonalVault(poolInfo.fxsPersonalVaultAddress);

        // Either create a new kek_id or add to an existing one
        if (_kekId == bytes32(0)) {
            // Use a new kek_id
            // Only stake for the minimum lock time
            uint256 _minSecs = IFraxFarm(_fxsVault.stakingAddress()).lock_time_min();

            // Need to lock for at least 1 second or there could be divide-by-zero problems down the road
            if (_minSecs == 0) _minSecs = 1;

            // Create a new kek_id
            _kekIdReturned = _fxsVault.stakeLockedCurveLp(_poolLpIn, _minSecs);
            vaultKekIds.push(_kekIdReturned);
            kekIdTotalDeposit[_kekIdReturned] = _poolLpIn;
        } else {
            // Use the existing kek_id
            _kekIdReturned = _kekId;

            // Add to an existing stake
            if (_poolLpIn > 0) {
                kekIdTotalDeposit[_kekId] += _poolLpIn;
                _fxsVault.lockAdditionalCurveLp(_kekId, _poolLpIn);
            }
        }
    }

    /// @notice (External) 2 coins -> LP. Function to deposit tokens to specific Curve Pool
    /// @param _ethIn Amount of Eth to deposit
    /// @param _useOneCoin Whether to use balanced (false), or oneCoin (true) withdrawal routes
    /// @return _lpOut The actual amount of LP out
    /// @return _nonEthUsed The amount of the non-ETH token used
    function depositToCurveLP(uint256 _ethIn, bool _useOneCoin) public returns (uint256 _lpOut, uint256 _nonEthUsed) {
        _requireIsTimelockOrOperator();
        return _depositToCurveLP(msg.sender, _ethIn, _useOneCoin);
    }

    /// @notice (Internal) Function to deposit tokens to specific Curve Pool
    /// @param _caller Address that originally called the deposit flow. Affects slippage
    /// @param _ethIn Amount of Eth (or LSD/WETH) to deposit
    /// @param _useOneCoin Whether to use balanced (false), or oneCoin (true) withdrawal routes
    /// @return _lpOutActual The actual amount of LP out
    /// @return _nonEthUsed The amount of the non-ETH token used
    function _depositToCurveLP(
        address _caller,
        uint256 _ethIn,
        bool _useOneCoin
    ) internal onBudget returns (uint256 _lpOutActual, uint256 _nonEthUsed) {
        // Helper variable
        uint256 _ethIndex = poolInfo.ethIndex;

        // Need to estimate the amount of LP generated
        // --------------------------------------------------------
        // Calculate the balanced info (info used by both routes)
        (
            uint256 _lpMinOut,
            ,
            uint256[2] memory _coinsInBalanced,
            uint256[2] memory _lpPerCoinsBalancedE18,
            uint256 _lp_virtual_price
        ) = amoHelper.calcMiscBalancedInfoWithParams(address(this), poolAddress, poolInfo, _ethIndex, _ethIn);

        // console2.log("_coinsInBalanced[0]: %s", _coinsInBalanced[0]);
        // console2.log("_coinsInBalanced[1]: %s", _coinsInBalanced[1]);
        // console2.log("ratio: %s", (_coinsInBalanced[0] * 1e6) / (_coinsInBalanced[0] + _coinsInBalanced[1]));

        // Make sure the pool imbalance is tolerable
        {
            // Get the ratio of token0 to token1
            uint256 _ratioE6 = (_coinsInBalanced[0] * 1e6) / (_coinsInBalanced[0] + _coinsInBalanced[1]);

            // Revert if the ratio is out of acceptable bounds
            if ((_ratioE6 < minTkn0ToTkn1RatioE6) || (_ratioE6 > maxTkn0ToTkn1RatioE6)) revert PoolTooImbalanced();
        }

        // Choose the route
        uint256[2] memory _coinsInToUse;
        if (_useOneCoin) {
            // OneCoin
            _coinsInToUse[_ethIndex] = _ethIn;

            // _lpMinOut should be at least as good as if you were depositing balanced
            _lpMinOut = (_ethIn * 1e18) / _lp_virtual_price;
        } else {
            // Do nothing else, _lpMinOut is already good
            _coinsInToUse = _coinsInBalanced;
        }

        // Account for our extra buffer slippage
        if (_caller == address(etherRouter)) {
            _lpMinOut = _lpMinOut - ((_lpMinOut * depositWithdrawSlippageRouterE6) / (1e6));
        } else {
            _lpMinOut = _lpMinOut - ((_lpMinOut * depositWithdrawSlippageTimelockOperatorE6) / (1e6));
        }

        // If WETH or stETH is part of the pool, instead of ETH
        if (poolInfo.ethType == EthType.WETH) {
            // See how much WETH you currently have
            uint256 _currWeth = WETH.balanceOf(address(this));

            // Use existing WETH first
            if (_currWeth >= _ethIn) {
                // Do nothing and use existing WETH
            } else {
                // Convert ETH to WETH as needed

                // ETH -> WETH
                WETH.deposit{ value: _ethIn - _currWeth }();
            }
        } else if (poolInfo.ethType == EthType.STETH) {
            // ETH -> stETH

            // See how much stETH you already have
            uint256 _existingStEth = stETH.balanceOf(address(this));

            // See how much ETH you need to convert to stETH
            if (_existingStEth >= _ethIn) {
                // Do nothing, you have enough stETH already
            } else {
                // Exchange for what you need
                // Account for rebasing
                _coinsInToUse[_ethIndex] = convertEthToStEth(_ethIn - _existingStEth);
            }
        }

        // Do approvals
        // --------------------------------------------------------
        for (uint256 i = 0; i < 2; ) {
            // Only do approvals for ERC20s, not ETH
            if (!(poolInfo.ethType == EthType.RAWETH && (i == poolInfo.ethIndex))) {
                ERC20 _token = ERC20(poolInfo.poolCoins[i]);
                if (_coinsInToUse[i] > 0) {
                    _token.approve(poolAddress, 0); // For USDT and others
                    _token.approve(poolAddress, _coinsInToUse[i]);
                }
            }
            unchecked {
                ++i;
            }
        }

        // Avoid stack too deep
        {
            // Check for ETH
            // --------------------------------------------------------
            uint256 eth_value = 0;
            if (poolInfo.ethType == EthType.RAWETH) {
                eth_value = _coinsInToUse[poolInfo.ethIndex];
            }

            // ABIs are slightly different when ETH is involved
            // --------------------------------------------------------
            if (poolInfo.lpAbiType == LpAbiType.LSDETH) {
                _lpOutActual = IPoolLSDETH(poolAddress).add_liquidity{ value: eth_value }(_coinsInToUse, _lpMinOut);
            } else {
                // LSD/LSD Stable and LSD/LSD Volatile have similar ABIs for add_liquidity
                _lpOutActual = IPool2LSDStable(poolAddress).add_liquidity(_coinsInToUse, _lpMinOut);
            }
        }

        // Mark the _nonEthUsed
        // --------------------------------------------------------
        if (_ethIndex == 0) {
            _nonEthUsed = _coinsInToUse[1];
        } else {
            _nonEthUsed = _coinsInToUse[0];
        }

        // Increment the total LP deposited
        // --------------------------------------------------------
        poolInfo.lpDeposited += _lpOutActual;

        emit DepositToPool(_coinsInToUse, _lpOutActual, _caller != address(etherRouter));
    }

    /// @notice (External) (Curve LP -> cvxLP). Deposit Pool LP tokens, convert them to Convex LP, and deposit into their vault
    /// @param _poolLpIn Amount of LP for deposit
    function depositToCvxLPVault(uint256 _poolLpIn) external {
        _requireIsTimelockOrOperator();
        _depositCurveLPToVaultedCvxLP(_poolLpIn);
    }

    /// @notice Invest ETH in the designated default FXS vault's cvxLP (convexBooster)
    /// @param _ethIn The amount of ETH to invest
    /// @param _useOneCoin Whether to use balanced (false), or oneCoin (true) withdrawal routes
    /// @param _curve_lp_generated How much vanilla Curve LP was generated
    /// @param _frxEthUsed How much frxEth was used
    function _investEthInDefaultCvxLPVault(
        uint256 _ethIn,
        bool _useOneCoin
    ) internal returns (uint256 _curve_lp_generated, uint256 _frxEthUsed) {
        // Make sure only the Ether Router is sending this to avoid griefs and confusion
        _requireSenderIsEtherRouter();

        // Make the deposit
        (_curve_lp_generated, _frxEthUsed) = _depositToCurveLP(msg.sender, _ethIn, _useOneCoin);

        // Deposit the LP into the cvxLP vault
        // Note: We don't automatically want to go to the stkcvxLP personal vault as too many kekIds would be generated
        // stkcvxLP vaulting should be done manually, and not for the entire portion of "ready" funds.
        _depositCurveLPToVaultedCvxLP(_curve_lp_generated);
    }

    /// @notice Needs to be here to receive ETH
    receive() external payable {
        // Do nothing for now.
    }

    /* ========================================================================================================== */
    /* =========================================== WITHDRAW FUNCTIONS =========================================== */
    /* ========================================================================================================== */

    /// @notice Ether Router can pull out ETH by unwinding vaults and/or FXS Vaulted LP
    /// @param _caller The address that originally called for the request
    /// @param _recipient Recipient of the ETH
    /// @param _ethRequested ETH amount
    /// @param _useOneCoin Whether to use balanced (false), or oneCoin (true) withdrawal routes
    /// @param _minOneCoinOut If _useOneCoin is true, what should be the minimum coin out
    /// @return _ethOut Amount of ETH generated. Ignores LSDs
    /// @return _remainingEth Unfulfilled amount of ETH that the recipient still needs to get from somewhere else. Should be _ethRequested - _ethOut
    function _requestEther(
        address _caller,
        address payable _recipient,
        uint256 _ethRequested,
        bool _useOneCoin,
        uint256 _minOneCoinOut
    ) internal nonReentrant returns (uint256 _ethOut, uint256 _remainingEth) {
        // // Set helper variable
        // uint256 _ethIndex = poolInfo.ethIndex;

        // Look for free ETH/LSD/WETH first
        _remainingEth = _ethRequested;

        // Check how much free ETH you have first
        uint256 _currentEthBalance = address(this).balance;

        // If there is enough free ETH, send that, otherwise start scrounging in more places
        if (_ethRequested <= _currentEthBalance) {
            // Send the free ETH to the recipient directly
            // Should not fail unless recipient is not payable
            (bool sent, ) = payable(_recipient).call{ value: _ethRequested }("");
            if (!sent) revert EthTransferFailedAMO(0);

            // Account for the free ETH sent out
            _ethOut = _ethRequested;
            _remainingEth = 0;
        } else {
            // Send ANY free ETH first, even if it is partial
            if (_currentEthBalance > 0) {
                // Send the free ETH to the recipient directly
                (bool sent, ) = payable(_recipient).call{ value: _currentEthBalance }("");
                if (!sent) revert EthTransferFailedAMO(1);

                // Account for the ETH sent out
                _ethOut += _currentEthBalance;
                _remainingEth -= _currentEthBalance;
            }

            // If you have WETH or non-FRAX LSDs, convert them to ETH
            {
                // Start scrounging
                // Scrounge a little more than you need to account for dust
                uint256 _scroungedOut = scroungeEthFromEquivalents((_remainingEth * 1e6) / (1e6 - swapSlippageE6));
                // _remainingEth + ((_remainingEth * swapSlippageE6) / (1e6))

                // If there is excess ETH, just let it sit in contract. It can be used for subsequent actions
                if (_scroungedOut > _remainingEth) {
                    _scroungedOut = _remainingEth;
                }

                // Account for the ETH sent out
                _ethOut += _scroungedOut;
                _remainingEth -= _scroungedOut;

                // Send the free ETH to the recipient directly
                (bool sent, ) = payable(_recipient).call{ value: _scroungedOut }("");
                if (!sent) revert EthTransferFailedAMO(2);
            }

            // If you still need ETH, start unwinding LPs
            if (_remainingEth > 0) {
                // Calculate actual LP needed
                // ----------------------------------------------------------------------
                // Instantiate variables
                uint256 _lpNeeded;
                uint256 _withdrawnEth;
                uint256[2] memory _coinsOutMinToUse;
                uint256[2] memory _coinsOutActual;

                // Use the specified route (oneCoin vs balanced)
                if (_useOneCoin) {
                    // Calculate the amount of LP needed
                    // Assume stETH:ETH is 1:1
                    _coinsOutMinToUse[poolInfo.ethIndex] = _remainingEth;
                    _lpNeeded = IPoolLSDETH(poolAddress).calc_token_amount(_coinsOutMinToUse, false);

                    // Don't need to use _coinsOutMinToUse for the oneCoin route as it will be lower bound in _withdrawOneCoin
                    // Do nothing
                } else {
                    // Get balanced information
                    uint256[2] memory _lpPerCoinsBalancedE18;
                    (_lpNeeded, , , _lpPerCoinsBalancedE18, ) = amoHelper.calcMiscBalancedInfoWithParams(
                        address(this),
                        poolAddress,
                        poolInfo,
                        poolInfo.ethIndex,
                        _remainingEth
                    );

                    // See how much ETH equivalents are expected out
                    // _coinsOutMinToUse[poolInfo.ethIndex] = (_lpNeeded * 1e18) / _lpPerCoinsBalancedE18[poolInfo.ethIndex];
                }

                // Apply the extra LP amount (helps with rounding issues)
                _lpNeeded = _lpNeeded + ((_lpNeeded * extraWithdrawalLpPctE6) / (1e6));

                // Check free LP
                uint256 _freeLP = ERC20(poolInfo.lpTokenAddress).balanceOf(address(this));

                // Check cvxLP
                // Note: Ignore stkcvxLP as it will have to be manually unwound
                uint256 _cvxLP = IConvexBaseRewardPool(poolInfo.rewardsContractAddress).balanceOf(address(this));

                // Cap the amount of LP to withdraw based on how much is actually accessible
                if (_lpNeeded > (_freeLP + _cvxLP)) _lpNeeded = (_freeLP + _cvxLP);

                // Withdraw
                // ----------------------------------------------------------------------
                {
                    // Use as much LP as you can, even if it is < _lpNeeded
                    if (_lpNeeded > 0) {
                        // Determine how much cvxLP needs to be unwound
                        // Use free LP first
                        uint256 _cvxLpToUnwind;
                        if (_freeLP >= _lpNeeded) {
                            // You have enough free LP and don't need to unwind any cvxLP
                        } else {
                            // Use up what free LP you can and unwrap the rest
                            _cvxLpToUnwind = _lpNeeded - _freeLP;
                        }

                        // Unwrap cvxLP if needed
                        // Do the unwrap (vaulted cvxLP -> coins). Skip reward claim to save gas
                        if (_cvxLpToUnwind > 0) _withdrawAndUnwrapVaultedCvxLP(_cvxLpToUnwind, false);

                        // Do the LP withdrawal (LP -> coins)
                        if (_useOneCoin) {
                            // Do the withdrawal (oneCoin)
                            _coinsOutActual = _withdrawOneCoin(_caller, _lpNeeded, poolInfo.ethIndex, _minOneCoinOut);
                        } else {
                            // Do the withdrawal (balanced)
                            // Min outs of [0, 0] here will get corrected to the slippage-allowable amount downstream
                            _coinsOutActual = _withdrawBalanced(_caller, _lpNeeded, _coinsOutMinToUse);
                        }

                        // Note the amount of ETH withdrawn
                        _withdrawnEth = _coinsOutActual[poolInfo.ethIndex];
                    }
                }

                // Unwrap WETH or swap out LSDs for ETH
                // ----------------------------------------------------------------------
                if (poolInfo.ethType == EthType.WETH) {
                    // Unwrap any WETH that came out, if applicable
                    WETH.withdraw(_withdrawnEth);
                } else if (poolInfo.ethType == EthType.STETH) {
                    // Convert any stETH to ETH
                    uint256 _ethFromLsdConversion = convertStEthToEth(_withdrawnEth, false);

                    // Update _withdrawnEth to account for the conversion slippage
                    _withdrawnEth = _ethFromLsdConversion;
                }

                // Account for the ETH sent out
                // ----------------------------------------------------------------------
                if (_withdrawnEth >= _remainingEth) {
                    // Let any profit dust accumulate here. It will be sent out with the next requestEther anyways
                    // Otherwise under/overflows can start to appear
                    uint256 _remainingEthBefore = _remainingEth;
                    _ethOut += _remainingEth;
                    _remainingEth = 0;

                    // Give the ETH to the recipient
                    (bool sent, ) = payable(_recipient).call{ value: _remainingEthBefore }("");
                    if (!sent) revert EthTransferFailedAMO(3);
                } else {
                    // Give out as much as you can
                    _ethOut += _withdrawnEth;
                    _remainingEth -= _withdrawnEth;

                    // Give the ETH to the recipient
                    (bool sent, ) = payable(_recipient).call{ value: _withdrawnEth }("");
                    if (!sent) revert EthTransferFailedAMO(4);
                }
            }
        }

        // Sanity check
        if (_remainingEth != (_ethRequested - _ethOut)) {
            revert RequestEtherSanityCheck(_remainingEth, (_ethRequested - _ethOut));
        }
    }

    /// @notice Ether Router can pull out ETH by unwinding vaults and/or FXS Vaulted LP. Callable only by the Ether Router
    /// @param _ethRequested ETH amount
    /// @return _ethOut Amount of ETH generated. Ignores LSDs
    /// @return _remainingEth Unfulfilled amount of ETH that the recipient still needs to get from somewhere else. Should be _ethRequested - _ethOut
    function requestEtherByRouter(uint256 _ethRequested) external returns (uint256 _ethOut, uint256 _remainingEth) {
        _requireSenderIsEtherRouter();

        // Use balanced by default (never use oneCoin unless user-directed)
        return _requestEther(msg.sender, payable(etherRouter), _ethRequested, false, 0);
    }

    /// @notice Ether Router can pull out ETH by unwinding vaults and/or FXS Vaulted LP. Callable only by the timelock/operator
    /// @param _recipient Recipient of the ETH
    /// @param _ethRequested ETH amount
    /// @param _useOneCoin Whether to use balanced (false), or oneCoin (true) withdrawal routes
    /// @param _minOneCoinOut If _useOneCoin is true, what should be the minimum coin out
    /// @return _ethOut Amount of ETH generated. Ignores LSDs
    /// @return _remainingEth Unfulfilled amount of ETH that the recipient still needs to get from somewhere else. Should be _ethRequested - _ethOut
    function requestEtherByTimelockOrOperator(
        address payable _recipient,
        uint256 _ethRequested,
        bool _useOneCoin,
        uint256 _minOneCoinOut
    ) external returns (uint256 _ethOut, uint256 _remainingEth) {
        _requireIsTimelockOrOperator();

        // Recipient can only be timelock or operator
        if (!(_recipient == timelockAddress || _recipient == operatorAddress)) {
            revert InvalidRecipient();
        }

        // Can be balanced or oneCoin
        return _requestEther(msg.sender, _recipient, _ethRequested, _useOneCoin, _minOneCoinOut);
    }

    /// @notice stkcvxLP -> Curve LP. Withdraw Convex LP, convert it back to Pool LP tokens, and give them back to the sender
    /// @param _kekId lock stake ID
    /// @param _claimFxsToo Whether to claim FXS too
    function withdrawAndUnwrapFromFxsVault(bytes32 _kekId, bool _claimFxsToo) external {
        _requireIsTimelockOrOperator();
        _requirehasStkCvxFxsVault();

        kekIdTotalDeposit[_kekId] = 0;
        IFxsPersonalVault fxsVault = IFxsPersonalVault(poolInfo.fxsPersonalVaultAddress);
        fxsVault.withdrawLockedAndUnwrap(_kekId);

        // Optionally claim FXS
        if (_claimFxsToo) claimRewards(false, true);
    }

    /// @notice (cvxLP -> Curve LP). Internal for: Withdraw Convex LP, convert it back to Pool LP tokens, and give them back to the amo
    /// @param _amount Amount of cvxLP for withdraw
    /// @param _claim if claim rewards or not
    function _withdrawAndUnwrapVaultedCvxLP(uint256 _amount, bool _claim) internal {
        IConvexBaseRewardPool _convexBaseRewardPool = IConvexBaseRewardPool(poolInfo.rewardsContractAddress);

        _convexBaseRewardPool.withdrawAndUnwrap(_amount, _claim);

        emit WithdrawFromVault(_amount);
    }

    /// @notice (cvxLP -> Curve LP). External for: Withdraw Convex LP, convert it back to Pool LP tokens, and give them back to the amo
    /// @param _amount Amount of cvxLP for withdraw
    /// @param _claim if claim rewards or not
    function withdrawAndUnwrapVaultedCvxLP(uint256 _amount, bool _claim) external {
        _requireIsTimelockOrOperator();
        _requireHasCVXVault();
        _withdrawAndUnwrapVaultedCvxLP(_amount, _claim);
    }

    /// @notice Function to withdraw tokens from specific Curve Pool based on current pool ratio
    /// @param _lpIn Amount of LP token
    /// @param _minAmounts Min amounts of coin out
    /// @return _amountsReceived Coin amounts received
    function withdrawBalanced(
        uint256 _lpIn,
        uint256[2] memory _minAmounts
    ) external returns (uint256[2] memory _amountsReceived) {
        _requireIsTimelockOrOperator();

        // Call the internal function
        _amountsReceived = _withdrawBalanced(msg.sender, _lpIn, _minAmounts);
    }

    /// @notice Function to withdraw all tokens from specific Curve Pool based on current pool ratio
    /// @param _minAmounts Min amounts of coin out
    /// @param _useOneCoin If true, withdrawOneCoin would be used
    /// @return _amountsReceived Coin amounts received
    function withdrawAll(
        uint256[2] memory _minAmounts,
        bool _useOneCoin
    ) external returns (uint256[2] memory _amountsReceived) {
        _requireIsTimelockOrOperator();

        // Get this contracts LP token balance
        ERC20 _lpToken = ERC20(poolInfo.lpTokenAddress);
        uint256 _allLP = _lpToken.balanceOf(address(this));

        // Different routes
        if (_useOneCoin) {
            // Determine the coin index and minOut
            uint256 _minAmountOutFromUser;
            uint256 _oneCoinIndex;
            if ((_minAmounts[0] > 0 && _minAmounts[1] > 0) || (_minAmounts[0] == 0 && _minAmounts[1] == 0)) {
                // _minAmounts should be either [<value>, 0] or [0, <value>]
                revert MinAmountsIncorrect();
            } else if (_minAmounts[0] > 0) {
                _oneCoinIndex = 0;
                _minAmountOutFromUser = _minAmounts[0];
            } else {
                _oneCoinIndex = 1;
                _minAmountOutFromUser = _minAmounts[1];
            }

            // Call the internal function
            _amountsReceived = _withdrawOneCoin(msg.sender, _allLP, _oneCoinIndex, _minAmountOutFromUser);
        } else {
            // Call the internal function
            _amountsReceived = _withdrawBalanced(msg.sender, _allLP, _minAmounts);
        }
    }

    /// @notice Function to withdraw tokens from specific Curve Pool based on current pool ratio
    /// @param _caller Originating caller
    /// @param _lpIn Amount of LP token
    /// @param _minAmountsFromUser Min amounts of coin out
    /// @return _amountsReceived Coin amounts received
    function _withdrawBalanced(
        address _caller,
        uint256 _lpIn,
        uint256[2] memory _minAmountsFromUser
    ) internal returns (uint256[2] memory _amountsReceived) {
        // Check permissions
        _requireIsTimelockOperatorOrEthRouter();

        // Get the index for ETH/LSDs/WETH
        uint256 _ethIndex = poolInfo.ethIndex;

        // ABI for TWOCRYPTO doesn't return coin amounts on remove_liquidity so need to check it with balanceOfs
        uint256[] memory _freeCoinBalancesBefore;
        if (poolInfo.lpAbiType == CurveLsdAmo.LpAbiType.TWOCRYPTO) {
            // Snapshot balances before
            _freeCoinBalancesBefore = amoHelper.showPoolFreeCoinBalancesWithParams(
                address(this),
                poolAddress,
                poolInfo
            );
        }

        // Different routes for Ether Router vs Timelock/Operator
        uint256[2] memory _minAmountsToUse; // 2 coins
        if (_caller == address(etherRouter)) {
            // Ether Router
            // -------------------------------------

            // Should be safe to use 0/0 minOuts here (per Dennis). A manipulated pool should give more value anyways than a non-manipulated one
            // Redundant for clarity
            _minAmountsToUse[0] = 0;
            _minAmountsToUse[1] = 0;
        } else {
            // Timelock/Operator
            // -------------------------------------

            // Min out should at least adhere to the max slippage
            // ----------------------------------------------------------------------

            // Calculate LP per coins
            (, , , uint256[2] memory _lpPerCoinsBalancedE18, ) = amoHelper.calcMiscBalancedInfoWithParams(
                address(this),
                poolAddress,
                poolInfo,
                0, // not used
                0 // not used
            );

            // Get the zero slippage min out for ETH/LSDs/WETH
            uint256 _absMinOutEth = (_lpIn * 1e18) / _lpPerCoinsBalancedE18[_ethIndex];

            // We don't care about frxETH or sfrxETH slippage when withdrawing balanced. If it is frontrun, it will always be favorable
            _minAmountsToUse[poolInfo.frxEthIndex] = 0;

            // Get the absolute smallest min out
            _absMinOutEth = _absMinOutEth - ((_absMinOutEth * depositWithdrawSlippageTimelockOperatorE6) / (1e6));

            // Override the min out if the user-supplied value is less than that from the contract slippage settings
            // E.g. user can be more strict, but not less, than the contract max slippage
            if (_absMinOutEth > _minAmountsFromUser[_ethIndex]) _minAmountsToUse[_ethIndex] = _absMinOutEth;
            else _minAmountsToUse[_ethIndex] = _minAmountsFromUser[_ethIndex];
        }

        // Remove the liquidity
        if (poolInfo.lpAbiType == CurveLsdAmo.LpAbiType.TWOCRYPTO) {
            // remove_liquidity does not have a return value here
            pool.remove_liquidity(_lpIn, _minAmountsToUse);

            // Snapshot balances after
            uint256[] memory _freeCoinBalancesAfter = amoHelper.showPoolFreeCoinBalancesWithParams(
                address(this),
                poolAddress,
                poolInfo
            );

            // Track the change in asset balances
            for (uint256 i = 0; i < 2; ) {
                _amountsReceived[i] = _freeCoinBalancesAfter[i] - _freeCoinBalancesBefore[i];
                unchecked {
                    ++i;
                }
            }
        } else {
            // remove_liquidity returns uint256[2]
            _amountsReceived = IPoolLSDETH(address(pool)).remove_liquidity(_lpIn, _minAmountsToUse);
        }

        // Track the change in LP
        if (_lpIn > poolInfo.lpDeposited) poolInfo.lpDeposited = 0;
        else poolInfo.lpDeposited -= _lpIn;

        emit WithdrawFromPool(_lpIn, _amountsReceived, _caller != address(etherRouter));
    }

    /// @notice Function to withdraw one token from specific Curve Pool
    /// @param _lpIn Amount of LP token
    /// @param _coinIndex Curve Pool target/output coin index
    /// @param _minAmountOutFromUser Min amount of target coin out. Will be overidden to contract level min (based on depositWithdrawSlippageRouterE6) if too low
    /// @return _amountsOut Coin amounts out
    function withdrawOneCoin(
        uint256 _lpIn,
        uint256 _coinIndex,
        uint256 _minAmountOutFromUser
    ) external returns (uint256[2] memory _amountsOut) {
        _requireIsTimelockOrOperator();

        // Call the internal function
        return _withdrawOneCoin(msg.sender, _lpIn, _coinIndex, _minAmountOutFromUser);
    }

    /// @notice Function to withdraw one token from specific Curve Pool
    /// @param _caller The originating caller of the request
    /// @param _lpIn Amount of LP token
    /// @param _coinIndex Curve Pool target/output coin index
    /// @param _minAmountOutFromUser Min amount of target coin out. Will be overidden to contract level min (based on depositWithdrawSlippageRouterE6) if too low
    /// @return _amountsOut Coin amounts out
    function _withdrawOneCoin(
        address _caller,
        uint256 _lpIn,
        uint256 _coinIndex,
        uint256 _minAmountOutFromUser
    ) internal returns (uint256[2] memory _amountsOut) {
        uint256[2] memory _minAmountsToUse; // 2 coins

        // Get the amount of coins expected from the input lp
        // ABIs are slightly different
        uint256 _absMinCoinOut;
        if (
            poolInfo.lpAbiType == LpAbiType.LSDETH ||
            poolInfo.lpAbiType == LpAbiType.TWOLSDSTABLE ||
            poolInfo.lpAbiType == LpAbiType.LSDWETH
        ) {
            _absMinCoinOut = pool.calc_withdraw_one_coin(_lpIn, int128(int256(_coinIndex)));
        } else {
            _absMinCoinOut = pool.calc_withdraw_one_coin(_lpIn, _coinIndex);
        }

        // // Get the zero slippage min outs
        // uint256 _absMinCoinOut = (_lpIn * 1e18) / _lpPerCoinsBalancedE18[_coinIndex];

        // Get the absolute smallest min out based on the contract slippage settings. Depends on the caller
        if (_caller == address(etherRouter)) {
            _absMinCoinOut = _absMinCoinOut - ((_absMinCoinOut * depositWithdrawSlippageRouterE6) / (1e6));
        } else {
            _absMinCoinOut = _absMinCoinOut - ((_absMinCoinOut * depositWithdrawSlippageTimelockOperatorE6) / (1e6));
        }

        // Override the min out if the user-supplied value is less than that from the contract slippage settings
        // E.g. user can be more strict, but not less, than the contract max slippage
        // NOTE: If _minAmountOutFromUser has zero slippage, this may revert due to the Curve fee
        if (_absMinCoinOut > _minAmountOutFromUser) _minAmountsToUse[_coinIndex] = _absMinCoinOut;
        else _minAmountsToUse[_coinIndex] = _minAmountOutFromUser;

        // ABIs are slightly different
        if (
            poolInfo.lpAbiType == LpAbiType.LSDETH ||
            poolInfo.lpAbiType == LpAbiType.TWOLSDSTABLE ||
            poolInfo.lpAbiType == LpAbiType.LSDWETH
        ) {
            // Use int128 for index
            IPoolLSDETH pool = IPoolLSDETH(poolAddress);

            // Uses int128
            int128 _index = _coinIndex.toInt128();
            _amountsOut[_coinIndex] = pool.remove_liquidity_one_coin(_lpIn, _index, _minAmountsToUse[_coinIndex]);
        } else {
            IPool2Crypto pool = IPool2Crypto(poolAddress);

            // Uses uint256
            _amountsOut[_coinIndex] = pool.remove_liquidity_one_coin(_lpIn, _coinIndex, _minAmountsToUse[_coinIndex]);
        }

        // Sanity check: Make sure the pool imbalance is tolerable and combat sandwiching
        {
            // console2.log("pool address: %s", address(pool));
            // console2.log("pool.balances(0): %s", pool.balances(0));
            // console2.log("pool.balances(1): %s", pool.balances(1));
            // console2.log("ratio: %s", (pool.balances(0) * 1e6) / (pool.balances(0) + pool.balances(1)));

            // Get the ratio of token0 to token1
            uint256 _ratioE6 = (pool.balances(0) * 1e6) / (pool.balances(0) + pool.balances(1));

            // Revert if the ratio is out of acceptable bounds
            if ((_ratioE6 < minTkn0ToTkn1RatioE6) || (_ratioE6 > maxTkn0ToTkn1RatioE6)) revert PoolTooImbalanced();
        }

        // Account for the used LP
        if (_lpIn > poolInfo.lpDeposited) poolInfo.lpDeposited = 0;
        else poolInfo.lpDeposited -= _lpIn;

        emit WithdrawFromPool(_lpIn, _amountsOut, false);

        return _amountsOut;
    }

    /* ========================================================================================================== */
    /* ====================================== SWAPS, CONVERSIONS, and BURNS ===================================== */
    /* ========================================================================================================== */

    /// @notice Burns excess frxETH
    /// @param _frxEthIn Amount of frxETH to burn
    function burnFrxEth(uint256 _frxEthIn) external {
        _requireIsTimelockOrOperator();

        // Burn the frxETH
        frxETH.burn(_frxEthIn);
    }

    /// @notice Converts ETH to WETH
    /// @param _ethIn Amount of ETH in
    function wrapEthToWeth(uint256 _ethIn) external payable {
        _requireIsTimelockOperatorOrEthRouter();

        // Make sure the pool uses WETH
        if (poolInfo.ethType != EthType.WETH) revert InvalidPoolOperation();

        // ETH -> WETH
        WETH.deposit{ value: _ethIn }();
    }

    /// @notice Converts WETH to ETH
    /// @param _wethIn Amount of WETH in
    function unwrapWethToEth(uint256 _wethIn) external payable {
        _requireIsTimelockOperatorOrEthRouter();

        // Make sure the pool uses WETH
        if (poolInfo.ethType != EthType.WETH) revert InvalidPoolOperation();

        // WETH -> ETH
        WETH.withdraw(_wethIn);
    }

    /// @notice Converts ETH to stETH
    /// @param _ethIn Amount of ETH in
    /// @return _stEthOutActual Actual amount of output stETH
    function convertEthToStEth(uint256 _ethIn) public payable returns (uint256 _stEthOutActual) {
        _requireIsTimelockOperatorOrEthRouter();

        // Make sure the pool uses stETH
        if (poolInfo.ethType != EthType.STETH) revert InvalidPoolOperation();

        // ETH -> stETH
        // ====================================================
        uint256 _stETHBalBefore = stETH.balanceOf(address(this));
        {
            stETH.submit{ value: _ethIn }(address(this));
        }
        uint256 _stETHBalAfter = stETH.balanceOf(address(this));

        // Check slippage, should be 1:1 but sometimes it can be off by a few wei
        uint256 _absoluteMinOut = ((_ethIn * (1e6 - swapSlippageE6)) / 1e6);
        _stEthOutActual = _stETHBalAfter - _stETHBalBefore;
        if (_stEthOutActual < _absoluteMinOut) {
            revert EthLsdConversionSlippage(_stETHBalAfter - _stETHBalBefore, _absoluteMinOut);
        }
    }

    /// @notice Converts stETH to ETH. Chooses between 2 pre-set Curve pools. May not convert anything if the prices are bad
    /// @param _stEthIn Amount of stETH in
    /// @param _revertInsteadOfNoOp If true, this function will revert (instead of no-op) if the slippage is too bad
    /// @return _ethOutActual Actual amount of output Eth
    function convertStEthToEth(uint256 _stEthIn, bool _revertInsteadOfNoOp) public returns (uint256 _ethOutActual) {
        _requireIsTimelockOperatorOrEthRouter();

        // Make sure the pool uses stETH
        if (poolInfo.ethType != EthType.STETH) revert InvalidPoolOperation();

        // stETH -> ETH
        // ====================================================
        {
            // Info
            // --------
            // Route 0
            // Curve stETH/ETH Original [IstETHETH]: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022
            // Coin0 = ETH, Coin1 = stETH
            // --------
            // Route 1
            // Curve stETH/ETH NG [I2PoolNoLendingNG]: 0x21E27a5E5513D6e65C4f830167390997aA84843a
            // Coin0 = ETH, Coin1 = stETH

            // See which route gives the best proceeds
            uint256[2] memory _ethOutEstimated;
            _ethOutEstimated[0] = IstETHETH(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).get_dy(1, 0, _stEthIn);
            _ethOutEstimated[1] = I2PoolNoLendingNG(0x21E27a5E5513D6e65C4f830167390997aA84843a).get_dy(1, 0, _stEthIn);

            // // Apply slippage
            // _ethOutEstimated[0] = (_ethOutEstimated[0] * (1e6 - swapSlippageE6)) / 1e6;
            // _ethOutEstimated[1] = (_ethOutEstimated[1] * (1e6 - swapSlippageE6)) / 1e6;

            // Get the 1:1 min out assuming slippage only
            uint256 _absoluteMinOut = ((_stEthIn * (1e6 - swapSlippageE6)) / 1e6);

            // TODO
            // _absoluteMinOut MIGHT BE WRONG HERE. YOU SET A LOOSE SLIPPAGE IN THE TEST AND IT STILL FAILED
            // EITHER THAT, OR SOME LOGIC BELOW IS WRONG

            // Go with the better pool, or skip altogether if you would get a bad price
            if ((_absoluteMinOut > _ethOutEstimated[0]) && (_absoluteMinOut > _ethOutEstimated[1])) {
                // If the slippage is too bad, either revert or no-op
                if (_revertInsteadOfNoOp) {
                    if (_ethOutEstimated[0] > _ethOutEstimated[1]) {
                        // _ethOutEstimated[0] is higher
                        revert EthLsdConversionSlippage(_ethOutEstimated[0], _absoluteMinOut);
                    } else {
                        // _ethOutEstimated[1] is higher
                        revert EthLsdConversionSlippage(_ethOutEstimated[1], _absoluteMinOut);
                    }
                } else {
                    // Do nothing. Do not execute the trade.
                }
            } else if (_ethOutEstimated[0] > _ethOutEstimated[1]) {
                // Go with route 0
                // Approve
                stETH.approve(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, _stEthIn);

                // Do the exchange
                _ethOutActual = IstETHETH(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).exchange(
                    1,
                    0,
                    _stEthIn,
                    _ethOutEstimated[0]
                );
            } else {
                // Go with route 1
                // Approve
                stETH.approve(0x21E27a5E5513D6e65C4f830167390997aA84843a, _stEthIn);

                // Do the exchange
                _ethOutActual = I2PoolNoLendingNG(0x21E27a5E5513D6e65C4f830167390997aA84843a).exchange(
                    1,
                    0,
                    _stEthIn,
                    _ethOutEstimated[1]
                );
            }
        }
    }

    /// @notice Swaps frxETH for sfrxETH or vice versa
    /// @param _tknsIn Amount of input token
    /// @param _frxEthIsInput If frxETH is the input token. If false, sfrxETH is.
    /// @return _tknsOut Amount of output tokens
    function exchangeFrxEthSfrxEth(uint256 _tknsIn, bool _frxEthIsInput) public returns (uint256 _tknsOut) {
        _requireIsTimelockOperatorOrEthRouter();

        // Make sure the pool uses sfrxETH
        if (poolInfo.frxEthType != FrxSfrxType.SFRXETH) revert InvalidPoolOperation();

        // Determine the route
        if (_frxEthIsInput) {
            // Approve
            frxETH.approve(address(sfrxETH), _tknsIn);

            // Stake for sfrxETH
            _tknsOut = sfrxETH.deposit(_tknsIn, address(this));
        } else {
            // Unstake sfrxETH for frxETH
            _tknsOut = sfrxETH.redeem(_tknsIn, address(this), address(this));
        }
    }

    /// @notice Function to use Curve Pool to swap two tokens
    /// @param _inIndex256 Curve Pool input coin index
    /// @param _outIndex256 Curve Pool output coin index
    /// @param _inAmount Amount of input coin
    /// @param _actualOut Actual amount of output coin
    /// @param _minOutFromUser User-supplied minOut. Cannot be less than the minOut calculated from the contract's swapSlippageE6
    function poolSwap(
        uint256 _inIndex256,
        uint256 _outIndex256,
        uint256 _inAmount,
        uint256 _minOutFromUser
    ) external returns (uint256 _actualOut) {
        _requireIsTimelockOrOperator();

        // Instantiate variables
        uint256 _minOutToUse;

        // Some ABIs use int128
        int128 _inIndex128 = _inIndex256.toInt128();
        int128 _outIndex128 = _outIndex256.toInt128();

        // ABI differences, plus payability
        if (poolInfo.lpAbiType == LpAbiType.LSDETH) {
            // Instantiate the pool
            IPoolLSDETH _pool = IPoolLSDETH(poolAddress);

            // Calculate _minOutToUse, and add in the acceptable slippage
            // Market price: manipulatable
            // _minOutToUse = _pool.get_dy(_inIndex128, _outIndex128, _inAmount); // DO NOT USE
            // Assume 1:1 ETH to LSD for this check
            _minOutToUse = (_inAmount * (1e6 - swapSlippageE6)) / 1e6;

            // User minOut can be more strict, but not less, than the contract max slippage
            if (_minOutFromUser >= _minOutToUse) _minOutToUse = _minOutFromUser;
            else revert PoolSwapMinOut(_minOutFromUser, _minOutToUse);

            // If you are selling ETH for frxETH
            if (_inIndex256 == poolInfo.ethIndex) {
                // Do the exchange with value
                _actualOut = _pool.exchange{ value: _inAmount }(_inIndex128, _outIndex128, _inAmount, _minOutToUse);
            } else {
                // Approve the "in" token
                ERC20 _token = ERC20(poolInfo.poolCoins[_inIndex256]);
                _token.approve(poolAddress, 0); // For USDT and others
                _token.approve(poolAddress, _inAmount);

                // Do the exchange without value
                // Shown for clarity
                _actualOut = _pool.exchange{ value: 0 }(_inIndex128, _outIndex128, _inAmount, _minOutToUse);
            }
        } else if (poolInfo.lpAbiType == LpAbiType.TWOLSDSTABLE || poolInfo.lpAbiType == LpAbiType.LSDWETH) {
            // Instantiate the pool
            IPool2LSDStable _pool = IPool2LSDStable(poolAddress);

            // Calculate _minOutToUse, and add in the acceptable slippage
            // _minOutToUse = _pool.get_dy(_inIndex128, _outIndex128, _inAmount);
            // Assume 1:1 pricing for the two tokens in this check
            _minOutToUse = (_inAmount * (1e6 - swapSlippageE6)) / 1e6;

            // User minOut can be more strict, but not less, than the contract max slippage
            if (_minOutFromUser >= _minOutToUse) _minOutToUse = _minOutFromUser;
            else revert PoolSwapMinOut(_minOutFromUser, _minOutToUse);

            // Approve the "in" token
            ERC20 _token = ERC20(poolInfo.poolCoins[_inIndex256]);
            _token.approve(poolAddress, 0); // For USDT and others
            _token.approve(poolAddress, _inAmount);

            // Do the exchange. Not payable so cannot recycle into above "if" statement
            _actualOut = _pool.exchange(_inIndex128, _outIndex128, _inAmount, _minOutToUse);
        } else if (poolInfo.lpAbiType == LpAbiType.TWOCRYPTO) {
            // Instantiate the pool
            IPool2Crypto _pool = IPool2Crypto(poolAddress);

            // Calculate _minOutToUse, and add in the acceptable slippage
            _minOutToUse = _pool.get_dy(_inIndex256, _outIndex256, _inAmount);
            _minOutToUse = (_minOutToUse * (1e6 - swapSlippageE6)) / 1e6;

            // User minOut can be more strict, but not less, than the contract max slippage
            if (_minOutFromUser >= _minOutToUse) _minOutToUse = _minOutFromUser;
            else revert PoolSwapMinOut(_minOutFromUser, _minOutToUse);

            // Approve the "in" token
            ERC20 _token = ERC20(poolInfo.poolCoins[_inIndex256]);
            _token.approve(poolAddress, 0); // For USDT and others
            _token.approve(poolAddress, _inAmount);

            // Do the exchange
            _actualOut = _pool.exchange(_inIndex256, _outIndex256, _inAmount, _minOutToUse);
        }

        emit Swap(_inIndex256, _outIndex256, _inAmount, _minOutToUse);
    }

    /// @notice Unwind WETH or LSDs for ETH
    /// @param _desiredEth The amount of ETH you are seeking
    /// @return _actualOut The amount of ETH that was successfully scrounged
    function scroungeEthFromEquivalents(uint256 _desiredEth) public returns (uint256 _actualOut) {
        _requireIsTimelockOperatorOrEthRouter();

        // Determine what to look for
        if (poolInfo.ethType == EthType.WETH) {
            // See how much WETH you actually have
            uint256 _bal = WETH.balanceOf(address(this));

            // Either withdraw all of it, or a partial amount
            if (_bal >= _desiredEth) {
                // You have enough, only withdraw what you need
                WETH.withdraw(_desiredEth);

                // WETH -> ETH is always 1:1
                _actualOut = _desiredEth;
            } else {
                // Withdraw all you have
                WETH.withdraw(_bal);

                // WETH -> ETH is always 1:1
                _actualOut = _bal;
            }
        } else if (poolInfo.ethType == EthType.STETH) {
            // See how much stETH you actually have
            uint256 _bal = stETH.balanceOf(address(this));

            // Either withdraw all of it, or a partial amount
            // Assume 1:1 stETH/ETH for this check
            if (_bal >= _desiredEth) {
                // You have enough, only exchange for what you need
                _actualOut = convertStEthToEth(_desiredEth, false);
            } else {
                // Exchange all you can
                _actualOut = convertStEthToEth(_bal, false);
            }

            // For _bal >= _desiredEth: You will probably have either a small shortage or profit due to slippage
            // If there is excess ETH, just let it sit in contract. It can be used for subsequent actions
            if (_actualOut > _desiredEth) {
                _actualOut = _desiredEth;
            }
        }
    }

    /* ========================================================================================================== */
    /* ============================================= REWARDS RELATED ============================================ */
    /* ========================================================================================================== */

    /// @notice Claim CVX, CRV, and FXS rewards
    /// @param _claimCvxLPVault Claim convex vault rewards (vaulted cvxLP)
    /// @param _claimStkCvxLPVault Claim FXS personal vault rewards (vaulted stkcvxLP)
    function claimRewards(bool _claimCvxLPVault, bool _claimStkCvxLPVault) public {
        _requireIsTimelockOrOperator();

        if (_claimCvxLPVault) {
            address[] memory rewardContracts = new address[](1);
            rewardContracts[0] = poolInfo.rewardsContractAddress;
            uint256[] memory chefIds = new uint256[](0);

            convexClaimZap.claimRewards(rewardContracts, chefIds, false, false, false, 0, 0);
        }
        if (_claimStkCvxLPVault) {
            if (poolInfo.hasStkCvxFxsVault) {
                IFxsPersonalVault fxsVault = IFxsPersonalVault(poolInfo.fxsPersonalVaultAddress);
                fxsVault.getReward();
            }
        }
    }

    /// @notice Withdraw rewards
    /// @param _crvAmount CRV Amount to withdraw
    /// @param _cvxAmount CVX Amount to withdraw
    /// @param _cvxCRVAmount cvxCRV Amount to withdraw
    /// @param _fxsAmount FXS Amount to withdraw
    /// @param _recipient Recipient address for the rewards
    function withdrawRewards(
        uint256 _crvAmount,
        uint256 _cvxAmount,
        uint256 _cvxCRVAmount,
        uint256 _fxsAmount,
        address _recipient
    ) external {
        _requireIsTimelockOrOperator();
        if (!(_recipient == timelockAddress || _recipient == operatorAddress)) {
            revert InvalidRecipient();
        }
        if (_crvAmount > 0) IERC20(CRV_ADDRESS).safeTransfer(_recipient, _crvAmount);
        if (_cvxAmount > 0) IERC20(address(CVX)).safeTransfer(_recipient, _cvxAmount);
        if (_cvxCRVAmount > 0) IERC20(CVXCRV_ADDRESS).safeTransfer(_recipient, _cvxCRVAmount);
        if (_fxsAmount > 0) IERC20(FXS_ADDRESS).safeTransfer(_recipient, _fxsAmount);
    }

    /* ========================================================================================================== */
    /* ======================================= INTERNAL SETTERS & CREATORS ====================================== */
    /* ========================================================================================================== */

    /// @notice Add new Curve Pool
    /// @param _poolConfigData config data for a new pool
    function _addOrSetPool(bytes memory _poolConfigData) internal {
        (
            uint8 _frxEthIndex,
            uint8 _ethIndex,
            address _poolAddress,
            address _lpTokenAddress,
            LpAbiType _lpAbiType,
            FrxSfrxType _frxEthType,
            EthType _ethType
        ) = abi.decode(_poolConfigData, (uint8, uint8, address, address, LpAbiType, FrxSfrxType, EthType));

        {
            poolAddress = _poolAddress;
            pool = IMinCurvePool(poolAddress);
            address[2] memory _poolCoins;
            _poolCoins[0] = pool.coins(0);
            _poolCoins[1] = pool.coins(1);
            poolInfo = PoolInfo({
                hasCvxVault: false,
                hasStkCvxFxsVault: false,
                frxEthIndex: _frxEthIndex,
                ethIndex: _ethIndex,
                rewardsContractAddress: address(0),
                fxsPersonalVaultAddress: address(0),
                // poolAddress: _poolAddress,
                lpTokenAddress: _lpTokenAddress,
                poolCoins: _poolCoins,
                lpDepositPid: 0,
                lpAbiType: _lpAbiType,
                frxEthType: _frxEthType,
                ethType: _ethType,
                lpDeposited: 0,
                lpMaxAllocation: 0
            });
        }
    }

    /// @notice Create a personal vault for that pool (i.e. the stkcvxLP personal vault address)
    /// @param _pid Pool id in FXS booster pool registry
    /// @return _fxsPersonalVaultAddress The address of the created vault
    function _createFxsVault(uint256 _pid) internal returns (address _fxsPersonalVaultAddress) {
        _requireHasCVXVault();
        poolInfo.hasStkCvxFxsVault = true;
        _fxsPersonalVaultAddress = convexFXSBooster.createVault(_pid);
        poolInfo.fxsPersonalVaultAddress = _fxsPersonalVaultAddress;
        IFxsPersonalVault fxsVault = IFxsPersonalVault(_fxsPersonalVaultAddress);
        if (poolInfo.lpTokenAddress != fxsVault.curveLpToken()) revert LPNotMatchingFromPID();
    }

    /// @notice Set Curve Pool Convex vault (i.e. the cvxLP address)
    /// @param _rewardsContractAddress Convex Rewards Contract Address (BaseRewardPool)
    function _setPoolVault(address _rewardsContractAddress) internal {
        poolInfo.hasCvxVault = true;
        IConvexBaseRewardPool _convexBaseRewardPool = IConvexBaseRewardPool(_rewardsContractAddress);
        poolInfo.lpDepositPid = uint32(_convexBaseRewardPool.pid());
        poolInfo.rewardsContractAddress = _rewardsContractAddress;
    }

    /* ========================================================================================================== */
    /* ===================================== RESTRICTED GOVERNANCE FUNCTIONS ==================================== */
    /* ========================================================================================================== */

    /// @notice Change the Ether Router address
    /// @param _newEtherRouterAddress Ether Router address
    function setEtherRouterAddress(address payable _newEtherRouterAddress) external {
        _requireSenderIsTimelock();
        _setEtherRouter(_newEtherRouterAddress);
    }

    /// @notice Add / Remove a function selector for an execution target address
    /// @param _targetAddress Target address
    /// @param _selector The selector
    /// @param _enabled Whether the selector is enabled or disabled
    function setExecuteSelector(address _targetAddress, bytes4 _selector, bool _enabled) external {
        _requireSenderIsTimelock();

        _setExecuteSelector(_targetAddress, _selector, _enabled);
    }

    /// @notice Add / Remove an execution target address
    /// @param _targetAddress Target address
    /// @param _enabled Whether the target address as a whole is enabled or disabled
    function setExecuteTarget(address _targetAddress, bool _enabled) external {
        _requireSenderIsTimelock();

        _setExecuteTarget(_targetAddress, _enabled);
    }

    /// @notice Change the Operator address
    /// @param _newOperatorAddress Operator address
    function setOperatorAddress(address _newOperatorAddress) external {
        _requireSenderIsTimelock();
        _setOperator(_newOperatorAddress);
    }

    /// @notice Set Curve Pool max LP
    /// @param _maxLP Maximum LP the AMO can have
    function setMaxLP(uint256 _maxLP) external {
        _requireSenderIsTimelock();

        // Set the max
        poolInfo.lpMaxAllocation = _maxLP;

        emit PoolAllocationsSet(poolInfo.lpMaxAllocation);
    }

    /// @notice Set Curve Pool accounting params for LP transfer
    /// @param _lpAmount Amount of LP
    /// @param _isDeposit is this a LP deposit or withdraw
    function setPoolManualLPTrans(uint256 _lpAmount, bool _isDeposit) external onBudget {
        _requireSenderIsTimelock();

        // Either add or subtract
        if (_isDeposit) {
            poolInfo.lpDeposited += _lpAmount;
        } else {
            poolInfo.lpDeposited -= _lpAmount;
        }

        // Dummy coin amounts
        uint256[2] memory _coinAmounts;

        // Emit events, marking them as manually set tx's
        if (_isDeposit) {
            emit DepositToPool(_coinAmounts, _lpAmount, true);
        } else {
            emit WithdrawFromPool(_lpAmount, _coinAmounts, true);
        }
    }

    /// @notice Set the default slippages
    /// @param _depositWithdrawSlippageRouterE6 Max slippage for the Ether Router. E.g. 100000 = 10%, 100 = 0.01%
    /// @param _depositWithdrawSlippageTimelockOperatorE6 Max slippage for the Timelock or Operator. E.g. 100000 = 10%, 100 = 0.01%
    /// @param _extraWithdrawalLpPctE6 Extra percent of LP to use when withdrawing. Helps with rounding issues. E.g. 100000 = 10%, 100 = 0.01%
    /// @param _swapSlippageE6 Max swap slippage plus fee. E.g. 100000 = 10%, 100 = 0.01%
    /// @param _minTkn0ToTkn1RatioE6 Minimum ratio of token0 to token1 for _depositToCurveLP. Used to limit sandwiching. (e.g. 150000 -> 15 tkn0 to 85 tkn1).
    /// @param _maxTkn0ToTkn1RatioE6 Max ratio of token0 to token1 for _depositToCurveLP. Used to limit sandwiching. (e.g. 850000 -> 85 tkn0 to 15 tkn1).
    function setSlippages(
        uint256 _depositWithdrawSlippageRouterE6,
        uint256 _depositWithdrawSlippageTimelockOperatorE6,
        uint256 _extraWithdrawalLpPctE6,
        uint256 _swapSlippageE6,
        uint256 _minTkn0ToTkn1RatioE6,
        uint256 _maxTkn0ToTkn1RatioE6
    ) external {
        _requireSenderIsTimelock();
        depositWithdrawSlippageRouterE6 = _depositWithdrawSlippageRouterE6;
        depositWithdrawSlippageTimelockOperatorE6 = _depositWithdrawSlippageTimelockOperatorE6;
        extraWithdrawalLpPctE6 = _extraWithdrawalLpPctE6;
        swapSlippageE6 = _swapSlippageE6;
        minTkn0ToTkn1RatioE6 = _minTkn0ToTkn1RatioE6;
        maxTkn0ToTkn1RatioE6 = _maxTkn0ToTkn1RatioE6;
    }

    /// @notice Arbitrary execute. Must be approved by governance.
    /// @param _to Target address
    /// @param _value ETH value transferred, if any
    /// @param _data The calldata
    function whitelistedExecute(address _to, uint256 _value, bytes calldata _data) external returns (bytes memory) {
        _requireSenderIsTimelock();

        (bool _success, bytes memory _returnData) = _whitelistedExecute(_to, _value, _data);
        require(_success, "whitelisted transaction failed");

        return _returnData;
    }

    /* ========================================================================================================== */
    /* ================================================= EVENTS ================================================= */
    /* ========================================================================================================== */

    /// @notice The ```DepositToPool``` event fires when a deposit happens to a pair
    /// @param _coinsUsed Coins used to generate the LP
    /// @param _lpGenerated Actual amount of LP deposited
    /// @param _isManualTx Whether this accounting was set manually by the operator (true) or through an actual pool deposit (false)
    event DepositToPool(uint256[2] _coinsUsed, uint256 _lpGenerated, bool _isManualTx);

    /// @notice The ```DepositToCvxLPVault``` event fires when a deposit happens to a pair
    /// @param _lp Deposited LP amount
    event DepositToCvxLPVault(uint256 _lp);

    /// @notice The ```PoolAllocationsSet``` event fires when the max LP is set
    /// @param _maxLP Max allowed LP for the AMO
    event PoolAllocationsSet(uint256 _maxLP);

    /// @param _inIndex Curve Pool input coin index
    /// @param _outIndex Curve Pool output coin index
    /// @param _inAmount Amount of input coin
    /// @param _minOutAmount Min amount of output coin
    event Swap(uint256 _inIndex, uint256 _outIndex, uint256 _inAmount, uint256 _minOutAmount);

    /// @notice The ```WithdrawFromPool``` event fires when a withdrawal happens from a pool
    /// @param _lpUsed LP consumed for the withdrawal
    /// @param _coinsOut The coin amounts withdrawn
    /// @param _isManualTx Whether this accounting was set manually by the operator (true) or through an actual pool withdrawal (false)
    event WithdrawFromPool(uint256 _lpUsed, uint256[2] _coinsOut, bool _isManualTx);

    /// @notice The ```WithdrawFromVault``` event fires when a withdrawal happens from a pool
    /// @param _lp Withdrawn LP amount
    event WithdrawFromVault(uint256 _lp);

    /* ========================================================================================================== */
    /* ================================================= ERRORS ================================================= */
    /* ========================================================================================================== */

    /// @notice When your ETH <> LSD conversion output was not enough
    /// @param actualOut The actual out
    /// @param minOut The minOut based on contract slippage settings
    error EthLsdConversionSlippage(uint256 actualOut, uint256 minOut);

    /// @notice When an Ether transfer fails in requestEther
    /// @param step A marker in the code where it is failing
    error EthTransferFailedAMO(uint256 step);

    /// @notice When you are trying to perform an operation that this pool does not support
    error InvalidPoolOperation();

    /// @notice When the recipient of rewards, ether, etc is invalid or not authorized
    error InvalidRecipient();

    /// @notice When the LP address generated in createFxsVault's fxsVault.curveLpToken() doesn't match the one you supplied as an argument
    error LPNotMatchingFromPID();

    /// @notice When an action would put a constituent token of an LP over the budgeted amount
    error OverLpBudget();

    /// @notice When minAmounts has 2 nonzero entries or 2 zero entries for a oneCoin operation
    error MinAmountsIncorrect();

    /// @notice When msg.sender is not the owner, operator, or Ether Router
    error NotTimelockOperatorOrEtherRouter();

    /// @notice Thrown if the sender is not the timelock or the operator
    error NotTimelockOrOperator();

    /// @notice When the pool is too imbalanced (maxTkn0ToTkn1RatioE6)
    error PoolTooImbalanced();

    /// @notice When the cvxLP vault address was not provided previously with setPoolVault
    error PoolNoCVXVault();

    /// @notice When the stkcvxLP vault address was not generated previously with createFxsVault
    error PoolNoFXSVault();

    /// @notice When the provide LP pool has not been approved yet
    error PoolNotApproved();

    /// @notice When your poolSwap minOut was not enough
    /// @param minOutFromUser The user supplied minOut
    /// @param minOut The minOut based on contract slippage settings
    error PoolSwapMinOut(uint256 minOutFromUser, uint256 minOut);

    /// @notice When the requestEther function return values look wrong
    /// @param remainingEth0 _remainingEth
    /// @param remainingEth1 (_ethRequested - _ethOut)
    error RequestEtherSanityCheck(uint256 remainingEth0, uint256 remainingEth1);
}
