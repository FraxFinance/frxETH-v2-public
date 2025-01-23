// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "../../script/DeployAll.s.sol";
import "../SharedBaseTestState.t.sol";

contract CurveAmoBaseTest is SharedBaseTestState {
    using stdStorage for StdStorage;

    // Used in tests
    DeployAll public deployContract;

    // Misc constants
    uint256 INITIAL_CURVE_LP_ETH_BALANCED_DEPOSIT = 400e18;
    uint256 INITIAL_CURVE_LP_RECEIVED_FROM_BAL_DEPOSIT;
    uint256 INITIAL_FRXETH_USED_IN_BAL_DEPOSIT;
    uint256 INITIAL_CVXLP_VAULTED = 100e18;
    uint256 INITIAL_STKCVXLP_VAULTED = 650e18;

    // Used for ffi and generating test creds for ETH2 staking
    // For some reason, the Json ordering is screwed up so you have to order it this way
    // Probably alphabetical
    struct ComboCredsJsonBytes {
        bytes32 deposit_data_root;
        bytes pubkey;
        bytes signature;
        bytes withdrawal_credentials;
    }

    // Need to parse this as a string, then convert to the proper bytes later
    // For some reason, the Json ordering is screwed up so you have to order it this way
    // Probably alphabetical
    struct ComboCredsJsonStrings {
        string deposit_data_root;
        string pubkey;
        string signature;
        string withdrawal_credentials;
    }

    function defaultSetup() public {
        // Select the fork block
        // vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_000_000); // Should be 19000000
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 20_000_000); // Should be 20000000

        // Set the validator operator
        VALIDATOR_OPERATOR = 0x28Ff0220384260089E669fbc46E8528e92F8D190;

        // Set frxETH
        frxETH = IFrxEth(FRXETH_ERC20);

        // Deploy core contracts
        console.log("<<<Deploy core contracts>>>");
        deployContract = DeployAll(new DeployAll());
        deployContract.run();

        // Instantiate the new contracts
        fraxEtherMinter = deployContract.fraxEtherMinter();
        beaconOracle = deployContract.beaconOracle();
        amoHelper = deployContract.amoHelper();
        curveLsdAmo = deployContract.curveLsdAmo();
        etherRouter = deployContract.etherRouter();
        redemptionQueue = deployContract.redemptionQueue();
        variableInterestRate = deployContract.variableInterestRate();
        lendingPool = deployContract.lendingPool();

        // Set convenience addresses
        beaconOracleAddress = address(beaconOracle);
        curveLsdAmoAddress = payable(curveLsdAmo);
        etherRouterAddress = payable(etherRouter);
        redemptionQueueAddress = payable(redemptionQueue);
        variableInterestRateAddress = address(variableInterestRate);
        lendingPoolAddress = payable(lendingPool);
        fraxEtherMinterAddress = payable(fraxEtherMinter);

        // Track this address
        address this_address = address(this);

        // Setup frxETH Minter
        // ============================================
        // Set some .env variables
        // Must be done at compile time due to .env loading)
        // prettier-ignore
        pubKeys = [bytes(hex"997ffd9198463bb5a3f43212ffc96a19e3e9d629798e75cde4ea21043d682616cfc03af7d025d508f761328bd4b76b75"), bytes(hex"a529622c7845262390888c7e907a53367877d683a28e94a96323c833701a061cd34aaa6ed82389f0690b3c063a67678b"), bytes(hex"92fd82c005bccc00a1ee8aed9d66d3d1d165c3ee397f06cb5989110817ba35c983cdf2f8d965b5ed3792cb40cf6346a6"), bytes(hex"aecdd7f48a7299e964e56470ef5a596afdb0a4d6d12aa6f308c0740042dc794da862fd517cf44f9d86a023b2ffa9ae41"), bytes(hex"a4f1932c46cba49b994cec513fd360952b30937852d6a967be4cf10e08cc81976fd156f6a92f4ddb626cd19c4da90bcf")];
        // prettier-ignore
        sigs = [
            bytes(hex"8fef0dd8fa892c0b85180b51a3be62849f6b05976ae3f98967656bf1c37cb3ca91e19df8f1d0b9486a1247152b5de0d304eeb355bc01e8e06ef34cd5c54925224fa4a0cf7d42a751ade42080c5bcbd8cc5fd4b5fe7ade9f50098f1d816987868"),
            bytes(hex"b80cfb30ca6a7f3df09cfb8ce841140b39f0ef384b315a7294e294f7bfcb5407a3557b8e6668ce46a3278955157148461248d735efc00a3693ae6d662c3e7aa87585df48d1cbe043de304ac45e0f01193d0346e6914df3c173c3ae5fa89b03c6"),
            bytes(hex"82860f7006e8dc9dd84287b56b013da0e3d598047f85b72d862b3d2fc5fa208395cef0fc881e54c2fc250f2c1f3c537510090515b313244c0a4e3098312c4479163ad69ee4cd3d230e8cbd34de97c51c31dca60b40aa138c18c2e9918a2faf79"),
            bytes(hex"a63990b9d2a4781773f11d8b4750a1668213e292ed4a8f01b86d0a4ae011a5915e97bcd6a3ed0bb3fc589e07459b32d80c295171f73fe75e9b1299685ec6d79f84f0b8cff703a541958e27f1ca7ee126716cd0157b1d07896f4167ff1ebdbec2"),
            bytes(hex"8e67371cb156fd94b35fd0882c0f4960669cef4ee06a4a05ae5fe15df915d363315d76426316ec7cdf31e766be52adda0aaaa825834f7739637665335d344b0a9b162fecd4cfe96f1d6a1df2596af84c247120f70ba08bd3b826a0ff32b6c9f0")
        ];
        // prettier-ignore
        ddRoots = [bytes32(hex"20e81d31c009c9b779346b05aee653635195bcadd8e7d632bde9fab2bba77dcd"), bytes32(hex"6f88fb0dd4066bbfe051c28571755527ab4b409e50affdd8b7fdaecfe5975f65"), bytes32(hex"6c62729d4f168a8ff11224ef375d942dc0528eb68b750cc6efe790ca62c30d5b"), bytes32(hex"1c7101589ca14a74c3e2a7da9092ccb18dc1064e1abbee8d73b811f8d4cad57d"), bytes32(hex"4645ce50940a306f2a120a8f2a80fd86bd9567760c3a742cf50aee9acfaa6c8a")];
        withdrawalCreds = [
            bytes(hex"010000000000000000000000b1748c79709f4ba2dd82834b8c82d4a505003f27"),
            bytes(hex"010000000000000000000000b1748c79709f4ba2dd82834b8c82d4a505003f27"),
            bytes(hex"010000000000000000000000b1748c79709f4ba2dd82834b8c82d4a505003f27"),
            bytes(hex"010000000000000000000000b1748c79709f4ba2dd82834b8c82d4a505003f27"),
            bytes(hex"010000000000000000000000b1748c79709f4ba2dd82834b8c82d4a505003f27")
        ];

        // Finish configurations after deployment (CurveAMO Operator)
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);

        vm.stopPrank();

        // Finish configurations after deployment (frxETH Comptroller)
        vm.startPrank(FRXETH_COMPTROLLER);

        // Add the new frxETHMinter as a minter for frxETH
        frxETH.addMinter(address(fraxEtherMinter));

        vm.stopPrank();

        // Finish configurations after deployment (Timelock)
        console.log("<<<Finish configurations after deployment (Timelock)>>>");
        vm.startPrank(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);

        // Set the lending pool for the beacon oracle
        beaconOracle.setLendingPool(lendingPoolAddress);

        // Set the lending pool for Ether Router
        etherRouter.setLendingPool(lendingPoolAddress);

        // Set the redemption queue address on the ether router
        etherRouter.setRedemptionQueue(redemptionQueueAddress);

        // Set the redemption fee to 0.05% because of Curve 0.03% + extra 0.02% margin of safety
        // If set, may be defeating the purpose of the 1:1 redemption queue.
        // lendingPool.setRedemptionFee(5000);

        // Set the withdrawal fee to 0.03% because of Curve (0.03%)
        lendingPool.setVPoolWithdrawalFee(3000);

        // Add the Curve AMO to the Ether Router and set it as the default deposit and withdrawal AMO
        etherRouter.addAmo(payable(curveLsdAmo));
        etherRouter.setPreferredDepositAndWithdrawalAMOs(payable(curveLsdAmo), payable(curveLsdAmo));

        vm.stopPrank();

        // Set up the unprivileged test users
        testUserPrivateKey = 0xA11CE;
        testUserPrivateKey2 = 0xB0B;
        testUserAddress = payable(vm.addr(testUserPrivateKey));
        testUserAddress2 = payable(vm.addr(testUserPrivateKey2));

        // Label the testUserAddresses
        vm.label(testUserAddress, "testUserAddress");
        vm.label(testUserAddress2, "testUserAddress2");

        // Give FXS to places that need it
        // ============================================
        // Impersonate FXS whale
        startHoax(FXS_WHALE);

        // Give 1000000 FXS to the frxETHWETH farm
        fxsERC20.transfer(address(stkcvxfrxETHWETH_Farm), 1_000_000e18);

        // Give 1000000 FXS to the rewards distributor
        fxsERC20.transfer(0x278dC748edA1d8eFEf1aDFB518542612b49Fcd34, 1_000_000e18);

        vm.stopPrank();

        // Give CRV and CVX to the farm
        // ============================================
        // Impersonate Binance 8
        startHoax(0xF977814e90dA44bFA03b6295A0616a897441aceC);

        // Give 250000 CRV to the frxETHWETH farm
        crvERC20.transfer(address(stkcvxfrxETHWETH_Farm), 250_000e18);

        // Give 250000 CVX to the frxETHWETH farm
        cvxERC20.transfer(address(stkcvxfrxETHWETH_Farm), 250_000e18);

        vm.stopPrank();

        // Setup other frxETH, ankrETH, and stETH stuff
        // ============================================
        console.log("<<<Setup other frxETH, ankrETH, and stETH stuff>>>");
        // Impersonate frxETH owner
        startHoax(FRXETH_OWNER);

        // Mint 10000 frxETH to the AMO
        frxETH.minter_mint(curveLsdAmoAddress, 10_000e18);

        // Mint 10 frxETH to testUserAddress2
        frxETH.minter_mint(testUserAddress2, 10e18);

        vm.stopPrank();

        // // Impersonate ankrETH whale
        // startHoax(ANKRETH_WHALE);

        // // Give 1000 ankrETH to AMO
        // ankrETHERC20.transfer(curveLsdAmoAddress, 1000e18);

        // vm.stopPrank();

        // // Impersonate stETH whale
        // startHoax(STETH_WHALE);

        // // Give 1000 stETH to AMO
        // stETHERC20.transfer(curveLsdAmoAddress, 1000e18);

        // vm.stopPrank();

        // Transfer 1000 ETH into the AMO
        vm.deal(curveLsdAmoAddress, 1000 ether);

        // Impersonate FRAX_TIMELOCK owner by default
        startHoax(FRAX_TIMELOCK);

        // Labels
        vm.label(address(ankrETHERC20), "ankrETHERC20");
        vm.label(address(stETHERC20), "stETHERC20");
    }

    function ffiGenerateETH2Creds(address withdrawal_address, uint256 num_creds) public {
        string[] memory inputs = new string[](8);
        inputs[0] = "tsx";
        inputs[1] = "./node-scripts/ffiGenerateETH2CredsHelper.ts";
        inputs[2] = "--withdrawal-address";
        inputs[3] = vm.toString(withdrawal_address);
        inputs[4] = "--num-validators";
        inputs[5] = vm.toString(num_creds);
        inputs[6] = "--offset";
        inputs[7] = "0";

        bytes memory res = vm.ffi(inputs);

        // Don't need to return anything rn
        // string memory output = abi.decode(res, (string));
        // console.log('ffiGenerateETH2Creds output: %s', output);
    }

    function to_little_endian_64(uint64 value) public pure returns (bytes memory ret) {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }

    // function addFrxETHETHAsPool(uint256 seed_amt_amo) public {
    //     // frxETH/ETH Pool
    //     bytes memory _configDataFrxETHETH = abi.encode(
    //         CurveLsdAmo.LpAbiType.LSDETH,
    //         CurveLsdAmo.FrxSfrxType.FRXETH,
    //         1, // frxEthIndex
    //         CurveLsdAmo.EthType.RAWETH,
    //         0, // ethIndex
    //         address(frxETHETH_LP) // lpTokenAddress
    //     );
    //     // console.logBytes(_configDataFrxETHETH);
    //     vm.stopPrank();
    //     startHoax(FRAX_TIMELOCK);
    //     curveLsdAmo.addOrSetPool(_configDataFrxETHETH, address(frxETHETH_Pool));

    //     // Re-set the now-initialized pool with the same values
    //     curveLsdAmo.addOrSetPool(_configDataFrxETHETH, address(frxETHETH_Pool));

    //     curveLsdAmo.setPoolVault(address(frxETHETH_Pool), cvxfrxETHETH_BaseRewardPool_address); // cvxLP
    //     uint256[] memory _poolMaxAllocations = new uint256[](2);
    //     _poolMaxAllocations[0] = 10_000e18; // ETH
    //     _poolMaxAllocations[1] = 10_000e18; // frxETH
    //     curveLsdAmo.setMaxLP(address(frxETHETH_Pool), _poolMaxAllocations);
    // }

    // function addFrxETHETHAsPoolWithFundedVault(uint256 seed_amt_amo) public returns (address _fxsPersonalVaultAddress) {
    //     addFrxETHETHAsPool(seed_amt_amo);

    //     // Set it as the default FXS vault
    //     curveLsdAmo.setDefaultFxsVaultPool(address(frxETHETH_Pool), 1000); // cvxstkLP

    //     // Deposit some ETH into the frxETHETH pool
    //     uint256[2] memory _amounts;
    //     _amounts[0] = 400e18;
    //     _amounts[1] = 400e18;
    //     curveLsdAmo.depositToCurveLP(address(frxETHETH_Pool), _amounts, 790e18);

    //     // Create the stkcvxLP vault (use the Convex pool id on the Convex Frax page, not the Convex Curve page)
    //     _fxsPersonalVaultAddress = curveLsdAmo.createFxsVault(address(frxETHETH_Pool), 36);

    //     // Lock part of the LP in cvxLP, not stkcvxLP
    //     curveLsdAmo.depositToCvxLPVault(address(frxETHETH_Pool), 100e18);

    //     // Vault most of the LP into stkcvxLP
    //     curveLsdAmo.depositCurveLPToVaultedStkCvxLP(address(frxETHETH_Pool), 650e18, 0);
    // }

    // function addAnkrETHFrxETHAsPool(uint256 seed_amt_amo) public {
    //     // ankrETH/frxETH Pool

    //     // SEED THE POOL FIRST, as it is pretty thin, but keep it imbalanced to stress test
    //     // ===================================
    //     // Stop the old prank
    //     vm.stopPrank();

    //     // Seed the Curve AMO with ankrETH
    //     startHoax(ANKRETH_WHALE);
    //     ankrETHERC20.transfer(curveLsdAmoAddress, seed_amt_amo);
    //     vm.stopPrank();

    //     // // Set up, approve, and deposit
    //     // uint256[2] memory __amounts;
    //     // __amounts[0] = 50e18;
    //     // __amounts[1] = 50e18;
    //     // frxETH.approve(address(ankrETHfrxETH_Pool), __amounts[0]);
    //     // ankrETHERC20.approve(address(ankrETHfrxETH_Pool), __amounts[1]);
    //     // uint256 lp_amount = ankrETHfrxETH_Pool.add_liquidity(__amounts, 0);
    //     // console.log("ankrETHfrxETH LP Seed Amount", lp_amount);

    //     // Re-Impersonate CURVEAMO_OPERATOR_ADDRESS
    //     startHoax(CURVEAMO_OPERATOR_ADDRESS);

    //     // SET THE POOL
    //     // ===================================
    //     bytes memory _configDataAnkrETHFrxETH = abi.encode(
    //         CurveLsdAmo.LpAbiType.TWOCRYPTO,
    //         CurveLsdAmo.FrxSfrxType.FRXETH,
    //         1, // frxEthIndex
    //         CurveLsdAmo.EthType.NONE,
    //         0, // ethIndex
    //         address(ankrETHfrxETH_LP) // lpTokenAddress
    //     );
    //     // console.logBytes(_configDataAnkrETHFrxETH);
    //     vm.stopPrank();
    //     startHoax(FRAX_TIMELOCK);
    //     curveLsdAmo.addOrSetPool(_configDataAnkrETHFrxETH, address(ankrETHfrxETH_Pool));

    //     curveLsdAmo.setPoolVault(address(ankrETHfrxETH_Pool), cvxankrETHfrxETH_BaseRewardPool_address);
    //     uint256[] memory _poolMaxAllocations = new uint256[](2);
    //     _poolMaxAllocations[0] = 10e18; // ankrETH
    //     _poolMaxAllocations[1] = 10e18; // frxETH
    //     curveLsdAmo.setMaxLP(address(ankrETHfrxETH_Pool), _poolMaxAllocations);
    // }

    // function addStETHFrxETHAsPool(uint256 seed_amt_amo) public {
    //     //  stETH/frxETH Pool

    //     // SEED THE POOL FIRST, as it is pretty thin, but keep it imbalanced to stress test
    //     // ===================================
    //     // Stop the old prank
    //     vm.stopPrank();

    //     // Give seed stETH to the AMO
    //     startHoax(STETH_WHALE);
    //     stETHERC20.transfer(curveLsdAmoAddress, seed_amt_amo);
    //     vm.stopPrank();

    //     // // Set up, approve, and deposit
    //     // uint256[2] memory __amounts;
    //     // __amounts[0] = 50e18;
    //     // __amounts[1] = 50e18;
    //     // frxETH.approve(address(stETHfrxETH_Pool), __amounts[0]);
    //     // stETHERC20.approve(address(stETHfrxETH_Pool), __amounts[1]);
    //     // uint256 lp_amount = stETHfrxETH_Pool.add_liquidity(__amounts, 0);
    //     // console.log("stETHfrxETH LP Seed Amount", lp_amount);

    //     // Re-Impersonate CURVEAMO_OPERATOR_ADDRESS
    //     startHoax(CURVEAMO_OPERATOR_ADDRESS);

    //     // SET THE POOL
    //     // ===================================
    //     bytes memory _configDataStETHFrxETH = abi.encode(
    //         CurveLsdAmo.LpAbiType.TWOLSDSTABLE,
    //         CurveLsdAmo.FrxSfrxType.FRXETH,
    //         1, // frxEthIndex
    //         CurveLsdAmo.EthType.NONE,
    //         0, // ethIndex
    //         address(stETHfrxETH_Pool) // lpTokenAddress
    //     );
    //     // console.logBytes(_configDataStETHFrxETH);
    //     vm.stopPrank();
    //     startHoax(FRAX_TIMELOCK);
    //     curveLsdAmo.addOrSetPool(_configDataStETHFrxETH, address(stETHfrxETH_Pool));

    //     curveLsdAmo.setPoolVault(address(stETHfrxETH_Pool), cvxstETHfrxETH_BaseRewardPool_address);
    //     uint256[] memory _poolMaxAllocations = new uint256[](2);
    //     _poolMaxAllocations[0] = 10e18; // stETH
    //     _poolMaxAllocations[1] = 10e18; // frxETH
    //     curveLsdAmo.setMaxLP(address(stETHfrxETH_Pool), _poolMaxAllocations);
    // }

    function setupFrxETHWETHInAmo(uint256 seed_amt_amo) public {
        // // frxETH/WETH Pool
        // bytes memory _configDataFrxETHWETH = abi.encode(
        //     CurveLsdAmo.LpAbiType.LSDWETH,
        //     CurveLsdAmo.FrxSfrxType.FRXETH,
        //     1, // frxEthIndex
        //     CurveLsdAmo.EthType.WETH,
        //     0, // ethIndex
        //     address(frxETHWETH_LP) // lpTokenAddress
        // );
        // // console.logBytes(_configDataFrxETHWETH);
        // vm.stopPrank();
        // startHoax(FRAX_TIMELOCK);

        // // Re-set the now-initialized pool with the same values
        // curveLsdAmo.addOrSetPool(_configDataFrxETHWETH, address(frxETHWETH_Pool));

        // curveLsdAmo.setPoolVault(address(frxETHWETH_Pool), cvxfrxETHWETH_BaseRewardPool_address); // cvxLP

        vm.stopPrank();
        startHoax(FRAX_TIMELOCK);
        curveLsdAmo.setMaxLP(20_000e18);
    }

    function fundFrxETHWETHVault(uint256 seed_amt_amo) public {
        // Assumes the vault already exists

        // Switch to the timelock
        vm.stopPrank();
        vm.startPrank(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);

        // Deposit some WETH into the frxETHWETH pool
        (INITIAL_CURVE_LP_RECEIVED_FROM_BAL_DEPOSIT, INITIAL_FRXETH_USED_IN_BAL_DEPOSIT) = curveLsdAmo.depositToCurveLP(
            INITIAL_CURVE_LP_ETH_BALANCED_DEPOSIT,
            false
        );

        // Lock part of the LP in cvxLP, not stkcvxLP
        curveLsdAmo.depositToCvxLPVault(INITIAL_CVXLP_VAULTED);

        // Vault most of the LP into stkcvxLP
        curveLsdAmo.depositCurveLPToVaultedStkCvxLP(INITIAL_STKCVXLP_VAULTED, 0);

        // Clear the prank
        vm.stopPrank();
    }

    // int256 mintedBalanceFRAX;
}
