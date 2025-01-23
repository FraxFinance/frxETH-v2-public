// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "frax-std/FraxTest.sol";
import "src/test/helpers/Helpers.sol";
import { CurveLsdAmo } from "src/contracts/curve-amo/CurveLsdAmo.sol";
import { CurveLsdAmoHelper } from "src/contracts/curve-amo/CurveLsdAmoHelper.sol";
import { BeaconOracle } from "src/contracts/BeaconOracle.sol";
import { EtherRouter } from "src/contracts/ether-router/EtherRouter.sol";
import { LendingPool, LendingPoolParams } from "src/contracts/lending-pool/LendingPool.sol";
import { VariableInterestRate } from "src/contracts/lending-pool/VariableInterestRate.sol";
import { IDepositContract, DepositContract } from "src/contracts/interfaces/IDepositContract.sol";
import { ValidatorPool } from "src/contracts/ValidatorPool.sol";
import { FraxEtherMinter, FraxEtherMinterParams, IFrxEth } from "src/contracts/frax-ether-minter/FraxEtherMinter.sol";
import {
    FraxEtherRedemptionQueueV2,
    FraxEtherRedemptionQueueCoreParams
} from "src/contracts/frxeth-redemption-queue-v2/FraxEtherRedemptionQueueV2.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    FraxUnifiedFarm_ERC20_Convex_frxETH
} from "src/contracts/curve-amo/flat-sources/FraxUnifiedFarm_ERC20_Convex_frxETH.sol";
import { VaultAccount } from "src/contracts/libraries/VaultAccountingLibrary.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { DecimalStringHelper } from "src/test/helpers/DecimalStringHelper.sol";
import "src/contracts/interfaces/IWETH.sol";
import "src/contracts/curve-amo/interfaces/curve/IPoolLSDETH.sol";
import "src/contracts/curve-amo/interfaces/curve/IPool2LSDStable.sol";
import "src/contracts/curve-amo/interfaces/curve/IPoolLSDWETH.sol";
import "src/contracts/curve-amo/interfaces/curve/IPool2Crypto.sol";
import "src/contracts/curve-amo/interfaces/convex/IConvexBaseRewardPool.sol";
import "src/contracts/curve-amo/interfaces/convex/IConvexBooster.sol";
import "src/contracts/curve-amo/interfaces/convex/IConvexClaimZap.sol";
import "src/contracts/curve-amo/interfaces/convex/IcvxRewardPool.sol";
import "src/test/helpers/LendingValidatorAncillaryFunctions.sol";
import "../Constants.sol" as ConstantsSBTS;

using SafeCast for uint256;

abstract contract SharedBaseTestState is FraxTest, ConstantsSBTS.Helper {
    using ArrayHelper for *;
    using SafeCast for uint256;
    using stdStorage for StdStorage;
    using DecimalStringHelper for uint256;
    using DecimalStringHelper for int256;

    uint256 constant HALF_PCT_DELTA = 0.005e18;
    uint256 constant ONE_PCT_DELTA = 0.01e18;
    uint256 constant TWO_PT_FIVE_PCT_DELTA = 0.025e18;
    uint256 constant FIVE_PCT_DELTA = 0.05e18;
    uint256 constant TWENTY_PCT_DELTA = 0.2e18;

    // Initial snapshots
    ValidatorDepositInfoSnapshot _validatorDepositInfoSnapshotInitial;
    ValidatorPoolAccountingSnapshot _validatorPoolAccountingSnapshotInitial;
    InitialSystemSnapshot _initialSystemSnapshot;

    // For testing
    uint256[10] totalNonValidatorEthSums;
    uint256[10] totalSystemEthSums;

    // AmoAccounting snapshots and deltas
    AmoAccounting[10] _amoAccountingFinals;
    AmoAccounting[10] _amoAccountingNets;

    // AmoPoolAccounting snapshots and deltas
    AmoPoolAccounting[10] _amoPoolAccountingFinals;
    AmoPoolAccounting[10] _amoPoolAccountingNets;

    // Various deltas
    DeltaValidatorDepositInfoSnapshot[10] _deltaValidatorDepositInfos;
    DeltaValidatorPoolAccountingSnapshot[10] _deltaValidatorPoolAccountings;
    DeltaSystemSnapshot[10] _deltaSystemSnapshots;

    // An unprivileged test user
    uint256 internal testUserPrivateKey;
    uint256 internal testUserPrivateKey2;
    address payable internal testUserAddress;
    address payable internal testUserAddress2;

    // AMO-related addresses
    CurveLsdAmoHelper public amoHelper;
    address public amoHelperAddress;
    CurveLsdAmo public curveLsdAmo;
    address payable public curveLsdAmoAddress;
    EtherRouter public etherRouter;
    address payable public etherRouterAddress;

    // Validator pool
    ValidatorPool public validatorPool;
    address payable public validatorPoolAddress;
    address payable public validatorPoolOwner;

    // Evil / fake validator pool
    ValidatorPool public evilValPool;
    address payable public evilValPoolAddress;
    address payable public evilValPoolOwner;

    // Fake deposit contract
    IDepositContract public depositContract = IDepositContract(0x00000000219ab540356cBB839Cbe05303d7705Fa);

    // Other contracts
    BeaconOracle public beaconOracle;
    address public beaconOracleAddress;
    LendingPool public lendingPool;
    address payable public lendingPoolAddress;
    VariableInterestRate public variableInterestRate;
    address public variableInterestRateAddress;

    // frxETHMinter-related
    FraxEtherMinter public fraxEtherMinter;
    address payable public fraxEtherMinterAddress;
    bytes[5] pubKeys;
    bytes[5] sigs;
    bytes32[5] ddRoots;
    bytes[5] withdrawalCreds;
    uint32 constant REWARDS_CYCLE_LENGTH = 1000;

    // Redemption Queue
    FraxEtherRedemptionQueueV2 public redemptionQueue;
    address payable public redemptionQueueAddress;

    // prettier-ignore
    bytes[] public validatorPublicKeys = new bytes[](0).concat(hex"997ffd9198463bb5a3f43212ffc96a19e3e9d629798e75cde4ea21043d682616cfc03af7d025d508f761328bd4b76b75").concat(hex"a529622c7845262390888c7e907a53367877d683a28e94a96323c833701a061cd34aaa6ed82389f0690b3c063a67678b").concat(hex"92fd82c005bccc00a1ee8aed9d66d3d1d165c3ee397f06cb5989110817ba35c983cdf2f8d965b5ed3792cb40cf6346a6").concat(hex"aecdd7f48a7299e964e56470ef5a596afdb0a4d6d12aa6f308c0740042dc794da862fd517cf44f9d86a023b2ffa9ae41").concat(hex"a4f1932c46cba49b994cec513fd360952b30937852d6a967be4cf10e08cc81976fd156f6a92f4ddb626cd19c4da90bcf").concat(hex"ac3a616dabf00408575a992bb396569a0743ca16d6b0aee94009eb249c7efd84159351378722a1aba962406a5d404003").concat(hex"9345476b082db3c0275db9bd6120b31a5dd4263ee7448417399a6692be40cffae1f73e98d9293e09c45f969af9487213").concat(hex"92d8b37ec392e9be8140940470bd4898beb72b5e4c700d1a5bd30e5a4bdcca4b08dfcd12edd520812939f14893f3fe91").concat(
        hex"ade01d28ec05ee37c1f946aa45662ca12522febcc4395bb0a6b2a7a655ecc3f44114f26dd760d5e7581c2e3827d78a23"
    ).concat(hex"831be7675152746b557bd40993806fba6a0067c04c9849523fe4a542d76578db19d62545989df94351cb3a8567cc487a").concat(hex"a8832987aff1d4f3a6082d16e253fa4b441e081b6086d1a637428bf8fdb3e9ba3210cc34e302829c18d3e0c5ced74450").concat(hex"807f8430f3a2e3f8d823c1ea62915ad87eb2887efb3922ab846022c0542597fa7391287526b0b6431c90b26a10e0f199").concat(hex"a30fb9078d43ef9dce6b19eb3c92b2d7e9e2ca55e6d35be16872636d5407084c3bf38ece51088e6c5fb283b0f6108c7b").concat(hex"90ecdee56f6f1e0a51f9377a1c55c9ec06818b58d03c2cd40347bc958c222ae763dff5b9e95515b7ab70d1d21ef7e71e").concat(hex"8e3e86a221e0ce2400d9fc6b2da8cab086905cb4f9d464a55f323bfa912dd68c2ca0a2b7a268ecb17eb7da160c61340d");

    // prettier-ignore
    bytes[] public validatorSignatures = new bytes[](0).concat(hex"8fef0dd8fa892c0b85180b51a3be62849f6b05976ae3f98967656bf1c37cb3ca91e19df8f1d0b9486a1247152b5de0d304eeb355bc01e8e06ef34cd5c54925224fa4a0cf7d42a751ade42080c5bcbd8cc5fd4b5fe7ade9f50098f1d816987868").concat(hex"b80cfb30ca6a7f3df09cfb8ce841140b39f0ef384b315a7294e294f7bfcb5407a3557b8e6668ce46a3278955157148461248d735efc00a3693ae6d662c3e7aa87585df48d1cbe043de304ac45e0f01193d0346e6914df3c173c3ae5fa89b03c6").concat(hex"82860f7006e8dc9dd84287b56b013da0e3d598047f85b72d862b3d2fc5fa208395cef0fc881e54c2fc250f2c1f3c537510090515b313244c0a4e3098312c4479163ad69ee4cd3d230e8cbd34de97c51c31dca60b40aa138c18c2e9918a2faf79").concat(hex"a63990b9d2a4781773f11d8b4750a1668213e292ed4a8f01b86d0a4ae011a5915e97bcd6a3ed0bb3fc589e07459b32d80c295171f73fe75e9b1299685ec6d79f84f0b8cff703a541958e27f1ca7ee126716cd0157b1d07896f4167ff1ebdbec2").concat(
        hex"8e67371cb156fd94b35fd0882c0f4960669cef4ee06a4a05ae5fe15df915d363315d76426316ec7cdf31e766be52adda0aaaa825834f7739637665335d344b0a9b162fecd4cfe96f1d6a1df2596af84c247120f70ba08bd3b826a0ff32b6c9f0"
    ).concat(hex"a95841a298be123f84798b4e236de4c8be8f54fec5639645fd1a3611b91afe4fa4f545a1e4b72ff0085070c756d6644d1551f574dc12cda9a84b480adc5f8f7b250233c1960c68b835976cb28cea3c63ade8919e7aa866e65b56071abc937bbb").concat(hex"b04b2da67234b41c864c7fd0bc25fd7a41b8f799a246760172b23458003be1acd8a82f8888971cfb20205bdf0b9db33405a83bc32e093638fee0de8f78f85011cb4eb6cb37294342832daf33daedd6edffe24398c9899b2c2ca63686bebcb58d").concat(hex"ae5c7cb23e3bb30ed43d0ebfbbe05ba8c21c5a2fd2235acef05ab9d42fa65c1d2d72d7cc552300d3b58b23f605c0cc8507054f3b82978cbb728899ba8244d94413bdd3007f72b7fa85f3c1650bc0e267a0a53cdcfab0e4e3e03723563aa203df").concat(hex"b62ad42b9cda31e2cd758625b1e0ce55106e9f32cd4d614f185a6a166aa43bef15e3f1d68bcb319111dee345f82a71530ba3d38b03b51a0086ab8d0adf0c57ac5bd8b29f36eb95dbe7bbd1a66737a552c3ab7b5064d75d82674aeee411c26572").concat(
        hex"88f3b3145f1af7bdefa7c822f129d779ea4fed8be07c7a24692cca9b5adcdfd21d277bf9664d239e72c1d45fac4e1646028ae3fbaef154b5cd2ac5efd0d573e4bf7ecabe0512e5abc00ff485e3ed8cba8bd2536d8ba89c9aa55004fde54c5808"
    ).concat(hex"8999a64a6ebf6c9d38f7536c3b3bcc8ab27ada8d074d60b1d5019b387a52a5c6be334cf4d37e62fb0ebd58462e5e307110a470e05fa54aa990f94d768a30e7fd0604042ed19b789200a939d1f5a9e4ec8fbe95ecf7ed283bb8f9a80578aea61a").concat(hex"83f7354ccc11bf057730de46867bc6d698949927ce0cd461bdd534f870acf2a8f336cd4f0e80982a079a2aae23094a98034ad8271549aedc59615057ecb205982a1ff8256e7b21d3e5017e65134a628a075d66e640458450330cd6684a11f3d6").concat(hex"a272bd0a8d6047415d0b25158d6a54a8aeded9f7d8924e3382c75ecaa8cb1de23b9ebf1eb0de81d2e32c9814f12e60af0c45ac13160f9623d90fe2b1f4d86e90e6f21b0ef3b8d3493b65e57133158b5e57ac9c0ceac54c741ee3bd466e4c1871").concat(hex"aa5dcaa5a9f44cc204dc8afbfc469d072a5b7397c2423c19da397edd342d0586e7ed5cd6c4f4fad15cd97c31ef168d25002e25195ae633d6b3c20039ac456089ffd51cece8891b60ff2ce71d7c86645129c41b56cebde366ad88317f62339436").concat(
        hex"8e7e9e4f85608b5e6463dfd4ad74c3f844f1f4f2a617506cd25ed01df13c2ce5f37a93789af197cc5c17d8516e37496712e7118312ffe8c7b009154542687e32c823c393b9c48242afa4b027442df5cea3d08558457b8c4c79a96c8515c86596"
    );

    uint128 public constant PARTIAL_DEPOSIT_AMOUNT = 8 ether;
    uint256 public constant ONE_YEAR_SECS = 31_556_736;
    uint64 internal constant FIFTY_BPS = 158_247_046;
    uint64 internal constant ONE_PERCENT = FIFTY_BPS * 2;
    uint64 internal constant ONE_BPS = FIFTY_BPS / 50;

    // Misc ERC20 addresses
    IERC20 public ankrETHERC20 = IERC20(0xE95A203B1a91a908F9B9CE46459d101078c2c3cb);
    IERC20 public fraxERC20 = IERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    IFrxEth public frxETH = IFrxEth(0x5E8422345238F34275888049021821E8E08CAa1f);
    IERC20 public fxsERC20 = IERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    IERC20 public crvERC20 = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public cvxERC20 = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public stETHERC20 = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IERC20 public usdcERC20 = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IWETH public WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // Curve pools
    // frxETH/ETH
    IPoolLSDETH public frxETHETH_Pool = IPoolLSDETH(0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577);
    IERC20 public frxETHETH_LP = IERC20(0xf43211935C781D5ca1a41d2041F397B8A7366C7A);
    IERC20 public cvxfrxETHETH_LP = IERC20(0xC07e540DbFecCF7431EA2478Eb28A03918c1C30E);
    IERC20 public stkcvxfrxETHETH_LP = IERC20(0x4659d5fF63A1E1EDD6D5DD9CC315e063c95947d0);
    address public cvxfrxETHETH_BaseRewardPool_address = 0xbD5445402B0a287cbC77cb67B2a52e2FC635dce4;

    // ankrETH/frxETH
    IPool2Crypto public ankrETHfrxETH_Pool = IPool2Crypto(0x41eA4045de2676727883aa0B4E43D7e32261f559);
    IERC20 public ankrETHfrxETH_LP = IERC20(0xa8e14F03124Ea156A4fc416537c82ff91a647D50);
    IERC20 public cvxankrETHfrxETH_LP = IERC20(0xDfE410FF58B1A5F578C7aE915281B7A9d7480891);
    IERC20 public stkcvxankrETHfrxETH_LP = IERC20(0x75A439b3F8106428b86198D8c306c57E9e7Bb3dC);
    address public cvxankrETHfrxETH_BaseRewardPool_address = 0xc18695D5824C49cF50E054953B3A5910c45597A0;

    // stETH/frxETH
    IPool2LSDStable public stETHfrxETH_Pool = IPool2LSDStable(0x4d9f9D15101EEC665F77210cB999639f760F831E);
    IERC20 public stETHfrxETH_LP = IERC20(0x4d9f9D15101EEC665F77210cB999639f760F831E);
    IERC20 public cvxstETHfrxETH_LP = IERC20(0x01492A2cB0Bd14034710475197B4169501B49Ead);
    IERC20 public stkcvxstETHfrxETH_LP = IERC20(0xc2eC3d1209FD1Fc512950825f34281EaF9aB13A2);
    address public cvxstETHfrxETH_BaseRewardPool_address = 0xC3D0B8170E105d6476fE407934492930CAc3BDAC;

    // frxETH/WETH
    IPoolLSDWETH public frxETHWETH_Pool = IPoolLSDWETH(0x9c3B46C0Ceb5B9e304FCd6D88Fc50f7DD24B31Bc);
    IERC20 public frxETHWETH_LP = IERC20(0x9c3B46C0Ceb5B9e304FCd6D88Fc50f7DD24B31Bc);
    IERC20 public cvxfrxETHWETH_LP = IERC20(0xAA71e0065A29F2529aBC0F615874009287966229);
    IERC20 public stkcvxfrxETHWETH_LP = IERC20(0x08061feC3FC09Aa2Eb4B4B72EA618034CBFD22b0);
    address public cvxfrxETHWETH_BaseRewardPool_address = 0xFafDE12dC476C4913e29F47B4747860C148c5E4f;
    FraxUnifiedFarm_ERC20_Convex_frxETH public stkcvxfrxETHWETH_Farm =
        FraxUnifiedFarm_ERC20_Convex_frxETH(0xB4fdD7444E1d86b2035c97124C46b1528802DA35);

    // NOTE: move these to script/constants.ts and then run `npm run generate:constants`
    // You can then inherit the ConstantsHelper contract to get access to these constants and have them labeled in the stack traces
    address internal constant AMO_MINTER_ADDRESS = 0xcf37B62109b537fa0Cb9A90Af4CA72f6fb85E241;
    address internal constant AMO_OWNER = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;
    address internal constant ANKRETH_WHALE = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant BEE_USER = 0x733371d7C15ACECF9e120dd037D6BcDb6E069148;
    address internal constant COMPTROLLER_ADDRESS = 0x168200cF227D4543302686124ac28aE0eaf2cA0B;
    address internal constant CURVEAMO_OPERATOR_ADDRESS = 0x8D8Cb63BcB8AD89Aa750B9f80Aa8Fa4CfBcC8E0C;
    address internal constant DEPOSIT_CONTRACT_ADDRESS = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant ETH_USD_CHAINLINK_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant FRAXLEND_WHITELIST_ADDRESS = 0x118C1462AA28bF2ea304f78f49C3388cfd93234e;
    address internal constant FRAXSWAP_ROUTER = 0xC14d550632db8592D1243Edc8B95b0Ad06703867;
    address internal constant FRAX_TIMELOCK = 0x8412ebf45bAC1B340BbE8F318b928C466c4E39CA;
    address internal constant FRXETH_COMPTROLLER = 0x8306300ffd616049FD7e4b0354a64Da835c1A81C;
    address internal constant FRXETH_ERC20 = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address internal constant FRXETH_OWNER = 0x8306300ffd616049FD7e4b0354a64Da835c1A81C;
    address internal constant FXS_WHALE = 0xc8418aF6358FFddA74e09Ca9CC3Fe03Ca6aDC5b0;
    address internal constant HELPER_ADDRESS = 0x05BB1C15BDb20936AABd31c12130A960d9AFe999;
    address internal constant STETH_WHALE = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant TIMELOCK_ADDRESS = 0x8412ebf45bAC1B340BbE8F318b928C466c4E39CA;
    address internal constant UNIV2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal VALIDATOR_OPERATOR = address(0); // Set in defaultSetup()
    address internal constant WALLET_WITH_CRVFRAX = 0xCFc25170633581Bf896CB6CDeE170e3E3Aa59503;
    address internal constant WALLET_WITH_USDC = 0xD6216fC19DB775Df9774a6E33526131dA7D19a2c;
    address internal constant WALLET_WITH_WETH = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28;
    address internal constant WBTC_FRAX_PAIR_ADDRESS = 0x32467a5fc2d72D21E8DCe990906547A2b012f382;
    address internal constant WETH_ERC20 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WETH_FRAX_PAIR_ADDRESS = 0x794F6B13FBd7EB7ef10d1ED205c9a416910207Ff;

    struct AmoPoolAccountingItems {
        AmoPoolAccounting initial;
        AmoPoolAccounting net;
        AmoPoolAccounting end;
    }

    struct AmoPoolAccounting {
        address curveAmoAddress;
        address poolAddress;
        uint256 coinCount;
        IERC20[] coins;
        uint256[] freeCoinBalances;
        uint256 lpDeposited;
        uint256 lpMaxAllocation;
        uint256 lpBalance;
        uint256 lpInCvxBooster;
        uint256 lpInStkCvxFarm;
        uint256 lpDepositedInVaults;
        uint256 lpTotalAllForms;
        uint256 totalOneStepWithdrawableFrxETH; // Total withdrawable frxETH as ONE COIN
        uint256 totalOneStepWithdrawableETH; // Total withdrawable ETH as ONE COIN
        uint256 totalBalancedWithdrawableFrxETH; // Total withdrawable frxETH at CURRENT RATIO
        uint256 totalBalancedWithdrawableETH; // Total withdrawable ETH at CURRENT RATIO
    }

    struct AmoAccounting {
        address curveAmoAddress;
        uint256 frxETHInContract;
        uint256 ethInContract;
        uint256 totalOneStepWithdrawableFrxETH;
        uint256 totalOneStepWithdrawableETH;
        uint256 totalBalancedWithdrawableFrxETH;
        uint256 totalBalancedWithdrawableETH;
        uint256 totalFrxETH;
        uint256 totalETH;
        uint256 dollarBalances_frxETH_val_e18;
        uint256 dollarBalances_ETH_val_e18;
    }

    struct AmoAccountingItems {
        AmoAccounting initial;
        AmoAccounting net;
        AmoAccounting end;
    }

    constructor() {
        super.labelConstants();
        labelConstants2();
    }

    function labelConstants2() public {
        vm.label(address(frxETHETH_Pool), "<frxETHETH_Pool>");
        vm.label(address(frxETHETH_LP), "<frxETHETH_LP>");
        vm.label(address(cvxfrxETHETH_LP), "<cvxfrxETHETH_LP>");
        vm.label(address(stkcvxfrxETHETH_LP), "<stkcvxfrxETHETH_LP>");
        vm.label(address(frxETHWETH_Pool), "<frxETHWETH_Pool>");
        vm.label(address(frxETHWETH_LP), "<frxETHWETH_LP>");
        vm.label(address(cvxfrxETHWETH_LP), "<cvxfrxETHWETH_LP>");
        vm.label(address(stkcvxfrxETHWETH_LP), "<stkcvxfrxETHWETH_LP>");
        vm.label(cvxfrxETHETH_BaseRewardPool_address, "<cvxfrxETHETH_BaseRewardPool>");
        vm.label(address(ankrETHfrxETH_Pool), "<ankrETHfrxETH_Pool>");
        vm.label(address(ankrETHfrxETH_LP), "<ankrETHfrxETH_LP>");
        vm.label(address(cvxankrETHfrxETH_LP), "<cvxankrETHfrxETH_LP>");
        vm.label(address(stkcvxankrETHfrxETH_LP), "<stkcvxankrETHfrxETH_LP>");
        vm.label(cvxankrETHfrxETH_BaseRewardPool_address, "<cvxankrETHfrxETH_BaseRewardPool>");
        vm.label(address(stETHfrxETH_Pool), "<stETHfrxETH_Pool>");
        vm.label(address(stETHfrxETH_LP), "<stETHfrxETH_LP>");
        vm.label(address(cvxstETHfrxETH_LP), "<cvxstETHfrxETH_LP>");
        vm.label(address(stkcvxstETHfrxETH_LP), "<stkcvxstETHfrxETH_LP>");
        vm.label(cvxstETHfrxETH_BaseRewardPool_address, "<cvxstETHfrxETH_BaseRewardPool>");
        vm.label(address(frxETHWETH_Pool), "<frxETHWETH_Pool>");
        vm.label(address(frxETHWETH_LP), "<frxETHWETH_LP>");
        vm.label(address(cvxfrxETHWETH_LP), "<cvxfrxETHWETH_LP>");
        vm.label(cvxfrxETHWETH_BaseRewardPool_address, "<cvxfrxETHWETH_BaseRewardPool>");
    }

    function initialPoolSnapshot(
        address payable _curveAmoAddrIn
    ) public view returns (AmoPoolAccounting memory _initialAmoPoolAccounting) {
        uint256 _coinCount = 2;
        uint256 _lpMaxAllocation = amoHelper.showAmoMaxLP(_curveAmoAddrIn);
        IERC20[] memory coins = new IERC20[](_coinCount);
        (
            uint256[] memory _freeCoinBalances,
            uint256 _depositedLp,
            uint256[5] memory _poolAndVaultAllocations
        ) = amoHelper.showPoolAccounting(_curveAmoAddrIn);
        uint256[10] memory helper_allocations = amoHelper.showAllocations(_curveAmoAddrIn);
        _initialAmoPoolAccounting = AmoPoolAccounting({
            curveAmoAddress: _curveAmoAddrIn,
            poolAddress: CurveLsdAmo(_curveAmoAddrIn).poolAddress(),
            coinCount: _coinCount,
            coins: coins,
            freeCoinBalances: _freeCoinBalances,
            lpDeposited: _depositedLp,
            lpMaxAllocation: _lpMaxAllocation,
            lpBalance: _poolAndVaultAllocations[0],
            lpInCvxBooster: _poolAndVaultAllocations[1],
            lpInStkCvxFarm: _poolAndVaultAllocations[2],
            lpDepositedInVaults: _poolAndVaultAllocations[3],
            lpTotalAllForms: _poolAndVaultAllocations[4],
            totalOneStepWithdrawableFrxETH: helper_allocations[4], // Total withdrawable frxETH directly from pool
            totalOneStepWithdrawableETH: helper_allocations[5], // Total withdrawable ETH directly from pool
            totalBalancedWithdrawableFrxETH: helper_allocations[6], // Total withdrawable frxETH at CURRENT RATIO
            totalBalancedWithdrawableETH: helper_allocations[7] // Total withdrawable ETH at CURRENT RATIO
        });
    }

    function finalPoolSnapshot(
        AmoPoolAccounting memory _initialAmoPoolAccounting
    )
        public
        view
        returns (AmoPoolAccounting memory _finalAmoPoolAccounting, AmoPoolAccounting memory _netAmoPoolAccounting)
    {
        _finalAmoPoolAccounting = initialPoolSnapshot(payable(_initialAmoPoolAccounting.curveAmoAddress));
        uint256 _coinCount = 2;

        uint256[] memory coinsBalanceDifferences = new uint256[](_coinCount);
        uint256 lpDepositedDifference;
        uint256 lpMaxAllocationDifference;
        uint256[] memory coinsProfitTakenDifferences = new uint256[](_coinCount);

        for (uint256 i = 0; i < _coinCount; i++) {
            coinsBalanceDifferences[i] = stdMath.delta(
                _finalAmoPoolAccounting.freeCoinBalances[i],
                _initialAmoPoolAccounting.freeCoinBalances[i]
            );
        }

        lpDepositedDifference = stdMath.delta(
            _finalAmoPoolAccounting.lpDeposited,
            _initialAmoPoolAccounting.lpDeposited
        );
        lpMaxAllocationDifference = stdMath.delta(
            _finalAmoPoolAccounting.lpMaxAllocation,
            _initialAmoPoolAccounting.lpMaxAllocation
        );

        _netAmoPoolAccounting = AmoPoolAccounting({
            curveAmoAddress: _initialAmoPoolAccounting.curveAmoAddress,
            poolAddress: _initialAmoPoolAccounting.poolAddress,
            coinCount: _coinCount,
            coins: _finalAmoPoolAccounting.coins,
            freeCoinBalances: coinsBalanceDifferences,
            lpDeposited: lpDepositedDifference,
            lpMaxAllocation: lpMaxAllocationDifference,
            lpBalance: stdMath.delta(_finalAmoPoolAccounting.lpBalance, _initialAmoPoolAccounting.lpBalance),
            lpInCvxBooster: stdMath.delta(
                _finalAmoPoolAccounting.lpInCvxBooster,
                _initialAmoPoolAccounting.lpInCvxBooster
            ),
            lpInStkCvxFarm: stdMath.delta(
                _finalAmoPoolAccounting.lpInStkCvxFarm,
                _initialAmoPoolAccounting.lpInStkCvxFarm
            ),
            lpDepositedInVaults: stdMath.delta(
                _finalAmoPoolAccounting.lpDepositedInVaults,
                _initialAmoPoolAccounting.lpDepositedInVaults
            ),
            lpTotalAllForms: stdMath.delta(
                _finalAmoPoolAccounting.lpTotalAllForms,
                _initialAmoPoolAccounting.lpTotalAllForms
            ),
            totalOneStepWithdrawableFrxETH: stdMath.delta(
                _finalAmoPoolAccounting.totalOneStepWithdrawableFrxETH,
                _initialAmoPoolAccounting.totalOneStepWithdrawableFrxETH
            ), // Total withdrawable frxETH directly from pool
            totalOneStepWithdrawableETH: stdMath.delta(
                _finalAmoPoolAccounting.totalOneStepWithdrawableETH,
                _initialAmoPoolAccounting.totalOneStepWithdrawableETH
            ), // Total withdrawable ETH directly from pool
            totalBalancedWithdrawableFrxETH: stdMath.delta(
                _finalAmoPoolAccounting.totalBalancedWithdrawableFrxETH,
                _initialAmoPoolAccounting.totalBalancedWithdrawableFrxETH
            ), // Total withdrawable frxETH at CURRENT RATIO
            totalBalancedWithdrawableETH: stdMath.delta(
                _finalAmoPoolAccounting.totalBalancedWithdrawableETH,
                _initialAmoPoolAccounting.totalBalancedWithdrawableETH
            )
        });
    }

    function initialAmoSnapshot(
        address payable _curveAmoAddrIn
    ) public view returns (AmoAccounting memory _initialAmoAccountingOutput) {
        uint256[10] memory allocations = amoHelper.showAllocations(_curveAmoAddrIn);
        (uint256 frxETH_val_e18, uint256 ETH_val_e18, ) = amoHelper.dollarBalancesOfEths(_curveAmoAddrIn);

        _initialAmoAccountingOutput = AmoAccounting({
            curveAmoAddress: _curveAmoAddrIn,
            frxETHInContract: allocations[0],
            ethInContract: allocations[1],
            totalOneStepWithdrawableFrxETH: allocations[4],
            totalOneStepWithdrawableETH: allocations[5],
            totalBalancedWithdrawableFrxETH: allocations[6],
            totalBalancedWithdrawableETH: allocations[7],
            totalFrxETH: allocations[8],
            totalETH: allocations[9],
            dollarBalances_frxETH_val_e18: frxETH_val_e18,
            dollarBalances_ETH_val_e18: ETH_val_e18
        });
        // mintedBalanceFRAX: mintedBalance
    }

    function finalAMOSnapshot(
        AmoAccounting memory _initialAmoAccountingOutput
    )
        public
        view
        returns (AmoAccounting memory _finalAmoAccountingOutput, AmoAccounting memory _netAmoAccountingOutput)
    {
        address _curveAmoAddrIn = _initialAmoAccountingOutput.curveAmoAddress;
        uint256[10] memory allocations = amoHelper.showAllocations(_curveAmoAddrIn);
        (uint256 frxETH_val_e18, uint256 ETH_val_e18, ) = amoHelper.dollarBalancesOfEths(_curveAmoAddrIn);
        // int256 mintedBalance = curveLsdAmo.mintedBalance();

        _finalAmoAccountingOutput = AmoAccounting({
            curveAmoAddress: _curveAmoAddrIn,
            frxETHInContract: allocations[0],
            ethInContract: allocations[1],
            totalOneStepWithdrawableFrxETH: allocations[4],
            totalOneStepWithdrawableETH: allocations[5],
            totalBalancedWithdrawableFrxETH: allocations[6],
            totalBalancedWithdrawableETH: allocations[7],
            totalFrxETH: allocations[8],
            totalETH: allocations[9],
            dollarBalances_frxETH_val_e18: frxETH_val_e18,
            dollarBalances_ETH_val_e18: ETH_val_e18
        });
        // mintedBalanceFRAX: mintedBalance

        _netAmoAccountingOutput = AmoAccounting({
            curveAmoAddress: _curveAmoAddrIn,
            frxETHInContract: stdMath.delta(
                _finalAmoAccountingOutput.frxETHInContract,
                _initialAmoAccountingOutput.frxETHInContract
            ),
            ethInContract: stdMath.delta(
                _finalAmoAccountingOutput.ethInContract,
                _initialAmoAccountingOutput.ethInContract
            ),
            totalOneStepWithdrawableFrxETH: stdMath.delta(
                _finalAmoAccountingOutput.totalOneStepWithdrawableFrxETH,
                _initialAmoAccountingOutput.totalOneStepWithdrawableFrxETH
            ),
            totalOneStepWithdrawableETH: stdMath.delta(
                _finalAmoAccountingOutput.totalOneStepWithdrawableETH,
                _initialAmoAccountingOutput.totalOneStepWithdrawableETH
            ),
            totalBalancedWithdrawableFrxETH: stdMath.delta(
                _finalAmoAccountingOutput.totalBalancedWithdrawableFrxETH,
                _initialAmoAccountingOutput.totalBalancedWithdrawableFrxETH
            ),
            totalBalancedWithdrawableETH: stdMath.delta(
                _finalAmoAccountingOutput.totalBalancedWithdrawableETH,
                _initialAmoAccountingOutput.totalBalancedWithdrawableETH
            ),
            totalFrxETH: stdMath.delta(_finalAmoAccountingOutput.totalFrxETH, _initialAmoAccountingOutput.totalFrxETH),
            totalETH: stdMath.delta(_finalAmoAccountingOutput.totalETH, _initialAmoAccountingOutput.totalETH),
            dollarBalances_frxETH_val_e18: stdMath.delta(
                _finalAmoAccountingOutput.dollarBalances_frxETH_val_e18,
                _initialAmoAccountingOutput.dollarBalances_frxETH_val_e18
            ),
            dollarBalances_ETH_val_e18: stdMath.delta(
                _finalAmoAccountingOutput.dollarBalances_ETH_val_e18,
                _initialAmoAccountingOutput.dollarBalances_ETH_val_e18
            )
        });
        // mintedBalanceFRAX: _finalAmoAccountingOutput.mintedBalanceFRAX - _initialAmoAccountingOutput.mintedBalanceFRAX
    }

    // Valid for a one-validator pool system only
    function printAndReturnSystemStateInfo(
        string memory titleString,
        bool printLogs
    )
        public
        returns (
            uint256 _interestAccrued,
            uint256 _ethTotalBalanced,
            uint256 _totalNonValidatorEth,
            uint256 _optimisticValidatorEth,
            uint256 _ttlSystemEth
        )
    {
        // Print the title
        if (printLogs) console.log(titleString);

        // ==================== INTEREST ACCRUED ====================

        // Accrue the interest
        lendingPool.addInterest(false);

        // Check to see how much was accrued
        _interestAccrued = lendingPool.interestAccrued();
        if (printLogs) console.log("_interestAccrued: ", _interestAccrued);

        // ==================== UTILIZATION AND RATE ====================

        {
            // Check the utilization
            uint256 _utilization = lendingPool.getUtilization(true, false);
            if (printLogs) console.log("_utilization: ", _utilization);
            if (printLogs) console.log("_utilization (%%): ", uint256(_utilization * 100).decimalString(5, true));

            // Check the stored utilization
            if (printLogs) console.log("utilizationStored: ", lendingPool.utilizationStored());
            if (printLogs) {
                console.log(
                    "utilizationStored (%%): ",
                    uint256(lendingPool.utilizationStored() * 100).decimalString(5, true)
                );
            }

            // Check the rate
            (, uint64 _ratePerSec, uint64 _fullUtilizationRate) = lendingPool.currentRateInfo();
            if (printLogs) console.log("_ratePerSec: ", _ratePerSec);
            if (printLogs) {
                console.log("Approx borrow APR: ", uint256(_ratePerSec * ONE_YEAR_SECS * 100).decimalString(18, true));
            }
            if (printLogs) console.log("_fullUtilizationRate (current rate if at 100%% util): ", _fullUtilizationRate);
            if (printLogs) {
                console.log(
                    "Approx borrow APR if at 100%% util (%%): ",
                    uint256(_fullUtilizationRate * ONE_YEAR_SECS * 100).decimalString(18, true)
                );
            }
        }

        // ==================== TOTAL BORROW ====================

        {
            (uint256 amount, uint256 shares) = lendingPool.totalBorrow();
            if (printLogs) {
                console.log("LP totalBorrow (amount): ", amount);
                console.log("LP totalBorrow (shares): ", shares);
            }
        }

        // ==================== CONSOLIDATED ETHER BALANCE ====================

        {
            EtherRouter.CachedConsEFxBalances memory _cachedBals = etherRouter.getConsolidatedEthFrxEthBalance(
                false,
                true
            );

            _ethTotalBalanced = _cachedBals.ethTotalBalanced;

            if (printLogs) {
                console.log(
                    "ER ethFree: %s (dec: %s)",
                    _cachedBals.ethFree,
                    uint256(_cachedBals.ethFree).decimalString(18, false)
                );
                console.log(
                    "ER ethInLpBalanced: %s (dec: %s)",
                    _cachedBals.ethInLpBalanced,
                    uint256(_cachedBals.ethInLpBalanced).decimalString(18, false)
                );
                console.log(
                    "ER ethTotalBalanced: %s (dec: %s)",
                    _cachedBals.ethTotalBalanced,
                    uint256(_cachedBals.ethTotalBalanced).decimalString(18, false)
                );
                console.log(
                    "ER frxEthFree: %s (dec: %s)",
                    _cachedBals.frxEthFree,
                    uint256(_cachedBals.frxEthFree).decimalString(18, false)
                );
                console.log(
                    "ER frxEthInLpBalanced: %s (dec: %s)",
                    _cachedBals.frxEthInLpBalanced,
                    uint256(_cachedBals.frxEthInLpBalanced).decimalString(18, false)
                );
            }
        }

        // ==================== REDEMPTION QUEUE ACCOUNTING ====================

        {
            (uint120 etherLiabilities, uint120 unclaimedFees, uint120 pendingFees) = redemptionQueue
                .redemptionQueueAccounting();

            (int256 _netEthBalance, uint256 _shortage) = redemptionQueue.ethShortageOrSurplus();
            if (printLogs) {
                console.log(
                    "RQ ETH: %s (dec: %s)",
                    redemptionQueueAddress.balance,
                    uint256(redemptionQueueAddress.balance).decimalString(18, false)
                );
                console.log(
                    "RQ frxETH: %s (dec: %s)",
                    frxETH.balanceOf(redemptionQueueAddress),
                    uint256(frxETH.balanceOf(redemptionQueueAddress)).decimalString(18, false)
                );
                console.log(
                    "RQ etherLiabilities: %s (dec: %s)",
                    etherLiabilities,
                    uint256(etherLiabilities).decimalString(18, false)
                );
                console.log(
                    "RQ unclaimedFees: %s (dec: %s)",
                    unclaimedFees,
                    uint256(unclaimedFees).decimalString(18, false)
                );

                console.log("RQ pendingFees: %s (dec: %s)", pendingFees, uint256(pendingFees).decimalString(18, false));
                console.log(
                    "RQ _netEthBalance: %s (dec: %s)",
                    _netEthBalance.decimalStringI256(0, false),
                    _netEthBalance.decimalStringI256(18, false)
                );
                console.log("RQ _shortage: %s (dec: %s)", _shortage, uint256(_shortage).decimalString(18, false));
            }
        }

        // ==================== VALIDATOR POOL AND OWNER STATS ====================

        {
            (, , , uint64 validatorCount, , uint128 borrowAllowance, uint256 borrowShares) = lendingPool
                .validatorPoolAccounts(validatorPoolAddress);
            uint256 borrowAmount = lendingPool.toBorrowAmount(borrowShares);

            // Assumes no slashes, rewards, etc
            _optimisticValidatorEth = validatorCount * 32 ether;

            // Get solvency data
            (, uint256 _borrowAmount, uint256 _creditAmount) = lendingPool.wouldBeSolvent(
                validatorPoolAddress,
                true,
                0,
                0
            );

            if (printLogs) {
                console.log("VP is solvent?: ", lendingPool.isSolvent(validatorPoolAddress));
                console.log("VP validatorCount: ", validatorCount);
                console.log("VP optimistic ETH in validators: ", _optimisticValidatorEth);
                console.log("VP remaining allowance ETH: ", borrowAllowance);
                console.log(
                    "VP remaining borrow/interest before liquidation: ",
                    int256(_creditAmount) - int256(_borrowAmount)
                );
                console.log("VP borrow ETH (amount): ", borrowAmount);
                console.log("VP owner ETH: ", validatorPoolOwner.balance);
                console.log("VP contract ETH: ", validatorPoolAddress.balance);
            }
        }

        // ==================== TEST USER ====================

        if (printLogs) {
            console.log("TU (test user) frxETH: ", frxETH.balanceOf(testUserAddress));
            console.log("TU (test user) ETH: ", testUserAddress.balance);
        }

        // ==================== MISC TOTALS ====================

        // Sum all the ETH not in validators
        _totalNonValidatorEth =
            _ethTotalBalanced +
            validatorPoolOwner.balance +
            validatorPoolAddress.balance +
            redemptionQueueAddress.balance +
            testUserAddress.balance;

        // Sum all the ETH everywhere in frxETH_V2 (for a one-validator pool setup)
        _ttlSystemEth = _totalNonValidatorEth + _optimisticValidatorEth;

        if (printLogs) {
            console.log("Total non-validator ETH: ", _totalNonValidatorEth);
            console.log("Total system ETH: ", _ttlSystemEth);
        }
    }

    function checkStoredVsLiveUtilization() public {
        assertEq(
            lendingPool.getUtilization(true, false),
            lendingPool.utilizationStored(),
            "Stored utilization does not match live utilization"
        );
    }

    function checkTotalSystemEth(
        string memory titleString,
        uint256 initialFrxethAmt
    ) public returns (uint256 totalNonValidatorEthSum, uint256 ttlSystemEth) {
        (
            uint256 _interestAccrued,
            uint256 _ethTotalBalanced,
            uint256 _totalNonValidatorEthSum,
            uint256 _optimisticValidatorEth,
            uint256 _ttlSystemEth
        ) = printAndReturnSystemStateInfo(titleString, true);
        totalNonValidatorEthSum = _totalNonValidatorEthSum;
        ttlSystemEth = _ttlSystemEth;

        // Check showAllocations
        {
            uint256[10] memory allocations = amoHelper.showAllocations(curveLsdAmoAddress);
            console.log("CurveAMO showAllocations [0]: Free frxETH in AMO: ", allocations[0]);
            console.log("CurveAMO showAllocations [1]: Free ETH in AMO: ", allocations[1]);
            console.log("CurveAMO showAllocations [2]: Total frxETH deposited into Pools: ", allocations[2]);
            console.log("CurveAMO showAllocations [3]: Total ETH + WETH deposited into Pools: ", allocations[3]);
            console.log(
                "CurveAMO showAllocations [4]: Total withdrawable frxETH from LPs as ONE COIN: ",
                allocations[4]
            );
            console.log("CurveAMO showAllocations [5]: Total withdrawable ETH from LPs as ONE COIN: ", allocations[5]);
            console.log(
                "CurveAMO showAllocations [6]: Total withdrawable frxETH from LPs as BALANCED: ",
                allocations[6]
            );
            console.log("CurveAMO showAllocations [7]: Total withdrawable ETH from LPs as BALANCED: ", allocations[7]);
        }
    }
}
