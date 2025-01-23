// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "src/test/SharedBaseTestState.t.sol";

contract TestLiveSetup is SharedBaseTestState {
    using DecimalStringHelper for uint256;
    using DecimalStringHelper for int256;

    address public investorCustodian = 0x5180db0237291A6449DdA9ed33aD90a38787621c;

    function setUp() public {
        // Select the fork block
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_474_955);

        // Instantiate the new contracts
        amoHelper = CurveLsdAmoHelper(ConstantsSBTS.MainnetFEV2Live.CURVE_LSD_AMO_HELPER);
        beaconOracle = BeaconOracle(ConstantsSBTS.MainnetFEV2Live.BEACON_ORACLE);
        curveLsdAmo = CurveLsdAmo(payable(ConstantsSBTS.MainnetFEV2Live.CURVE_LSD_AMO));
        etherRouter = EtherRouter(payable(ConstantsSBTS.MainnetFEV2Live.ETHER_ROUTER));
        fraxEtherMinter = FraxEtherMinter(payable(ConstantsSBTS.MainnetFEV2Live.FRAX_ETHER_MINTER));
        lendingPool = LendingPool(payable(ConstantsSBTS.MainnetFEV2Live.LENDING_POOL));
        redemptionQueue = FraxEtherRedemptionQueueV2(payable(ConstantsSBTS.MainnetFEV2Live.REDEMPTION_QUEUE));
        variableInterestRate = VariableInterestRate(ConstantsSBTS.MainnetFEV2Live.VARIABLE_INTEREST_RATE);
        validatorPool = ValidatorPool(payable(ConstantsSBTS.MainnetFEV2Live.VALIDATOR_POOL_IC));

        // Set convenience addresses
        amoHelperAddress = address(amoHelper);
        beaconOracleAddress = address(beaconOracle);
        curveLsdAmoAddress = payable(curveLsdAmo);
        etherRouterAddress = payable(etherRouter);
        fraxEtherMinterAddress = payable(fraxEtherMinter);
        lendingPoolAddress = payable(lendingPool);
        redemptionQueueAddress = payable(redemptionQueue);
        variableInterestRateAddress = address(variableInterestRate);
        validatorPoolAddress = payable(validatorPool);
        validatorPoolOwner = payable(investorCustodian);

        // Label
        vm.label(amoHelperAddress, "CurveLsdAmoHelper");
        vm.label(beaconOracleAddress, "BeaconOracle");
        vm.label(curveLsdAmoAddress, "CurveLsdAmo");
        vm.label(etherRouterAddress, "EtherRouter");
        vm.label(fraxEtherMinterAddress, "FraxEtherMinter");
        vm.label(lendingPoolAddress, "LendingPool");
        vm.label(redemptionQueueAddress, "RedemptionQueue");
        vm.label(variableInterestRateAddress, "VariableInterestRate");
        vm.label(validatorPoolAddress, "ValidatorPool");

        // Set up the unprivileged test users
        testUserPrivateKey = 0xA11CE;
        testUserPrivateKey2 = 0xB0B;
        testUserAddress = payable(vm.addr(testUserPrivateKey));
        testUserAddress2 = payable(vm.addr(testUserPrivateKey2));

        // Label the testUserAddresses
        vm.label(testUserAddress, "testUserAddress");
        vm.label(testUserAddress2, "testUserAddress2");

        // Turn on frxETH minting
        hoax(frxETH.owner());
        frxETH.addMinter(fraxEtherMinterAddress);
    }

    function test_LiveE2ENoBorrow() public {
        // Give the IC some ETH
        vm.deal(investorCustodian, 100 ether);

        // IC mints some frxETH
        hoax(investorCustodian);
        fraxEtherMinter.mintFrxEth{ value: 10 ether }();

        // Print
        printAndReturnSystemStateInfo("========= INITIAL =========", true);

        // Drop some frxETH into the Curve AMO
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        frxETH.transfer(curveLsdAmoAddress, 50e18);

        // Increase the LP budget
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        curveLsdAmo.setMaxLP(100e18);

        // Sweep some ETH into the Curve AMO
        hoax(etherRouter.operatorAddress());
        etherRouter.sweepEther(5 ether, true);

        // Note CRV balance before
        uint256 _crvBefore = crvERC20.balanceOf(curveLsdAmoAddress);

        // Print
        printAndReturnSystemStateInfo("========= AFTER SWEEP =========", true);

        // Wait 8 days
        // =============================
        mineBlocksBySecond(8 days);

        // Claim rewards
        // =============================
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        curveLsdAmo.claimRewards(true, true);

        // Note balance change
        uint256 _collectedCRV = crvERC20.balanceOf(curveLsdAmoAddress) - _crvBefore;
        console.log("Collected CRV: %s (dec: %s)", _collectedCRV, _collectedCRV.decimalString(18, false));

        // IC requests to redeem some frxETH
        hoax(investorCustodian);
        frxETH.approve(redemptionQueueAddress, 3 ether);
        hoax(investorCustodian);
        uint256 _nftId = redemptionQueue.enterRedemptionQueue(investorCustodian, 3 ether);

        // Wait 15 days
        // =============================
        mineBlocksBySecond(15 days);

        // IC redeems their NFT
        hoax(investorCustodian);
        redemptionQueue.fullRedeemNft(_nftId, payable(investorCustodian));


        console.logBytes(abi.encodePacked(bytes4(keccak256(bytes("addMinter(address)"))), hex"0000000000000000000000007bc6bad540453360f744666d625fec0ee1320ca3"));
    }

    function test_CurveAMORecoverFrxETH() public {
        // Drop some frxETH into the Curve AMO
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        frxETH.transfer(curveLsdAmoAddress, 50e18);

        // Prepate to recover some unused frxETH
        // =============================

        // Generate the calldata for sending the misplaced FRAX back to the FRAX_WHALE
        bytes memory _calldata = abi.encodeWithSelector(
            bytes4(0xa9059cbb),
            address(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS),
            20e18
        );

        // Try setting an execute target as random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS,
                testUserAddress
            )
        );
        curveLsdAmo.setExecuteTarget(address(frxETH), true);

        // Set an execute target correctly
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        curveLsdAmo.setExecuteTarget(address(frxETH), true);

        // Try to execute without enabling the selector first (should fail)
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedSelector()"));
        curveLsdAmo.whitelistedExecute(address(frxETH), 0, _calldata);

        // Try setting an execute selector as random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS,
                testUserAddress
            )
        );
        curveLsdAmo.setExecuteSelector(address(frxETH), bytes4(0xa9059cbb), true);

        // Try setting an execute selector on a non-approved target (should fail)
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedTarget()"));
        curveLsdAmo.setExecuteSelector(address(usdcERC20), bytes4(0xa9059cbb), true);

        // Try setting an execute selector correctly
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        curveLsdAmo.setExecuteSelector(address(frxETH), bytes4(0xa9059cbb), true);

        // Try to send the extra frxETH back (with whitelistedExecute) as a random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS,
                testUserAddress
            )
        );
        curveLsdAmo.whitelistedExecute(address(frxETH), 0, _calldata);

        // Send the frxETH back correctly
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        curveLsdAmo.whitelistedExecute(address(frxETH), 0, _calldata);

        // Disable the execute target
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        curveLsdAmo.setExecuteTarget(address(frxETH), false);

        // Try to execute after the target is disabled (should fail)
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedTarget()"));
        curveLsdAmo.whitelistedExecute(address(frxETH), 0, _calldata);

        // Re-enable an execute target
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        curveLsdAmo.setExecuteTarget(address(frxETH), true);

        // Disable a specific selector but leave the target enabled
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        curveLsdAmo.setExecuteSelector(address(frxETH), bytes4(0xa9059cbb), false);

        // Try to execute after the selector is disabled (should fail)
        hoax(ConstantsSBTS.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedSelector()"));
        curveLsdAmo.whitelistedExecute(address(frxETH), 0, _calldata);
    }
}
