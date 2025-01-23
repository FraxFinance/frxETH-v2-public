// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./CurveAmoBaseTest.t.sol";

interface CurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function get_virtual_price() external view returns (uint256);
    function balances(uint256 i) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract CurveAMOFunctionsTest is CurveAmoBaseTest {
    // For determining expected ratios
    uint256 public frxETHWETH_LPPerETH;
    uint256 public frxETHWETH_LPPerfrxETH;

    // Temporary. Prevents stack too deep errors
    uint256[2] public tmpAmounts;
    uint256 public ETH_PRICE_E18;
    uint256 public FRXETH_PRICE_E18;
    uint256 lpValueInEthCurr;
    uint256 lpValueInEthPrev;
    uint256 lpValueInEthDelta;
    uint256 tmpNetSumBothFullOneStepWithdrawables;
    uint256 tmpNetTotalWithdrawableBothAsBalanced;

    function amoFunctionsTestSetup() public {
        defaultSetup();
        vm.stopPrank();

        // Give 10000 WETH to the AMO (from a WETH whale)
        startHoax(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        WETH.transfer(curveLsdAmoAddress, 10_000e18);

        // Switch back to the timelock
        vm.startPrank(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);

        // Setup the frxETH/WETH farm
        setupFrxETHWETHInAmo(0);

        // Set the helper ratios
        {
            (, , , uint256[2] memory _lpPerCoinsBalancedE18, ) = amoHelper.calcMiscBalancedInfo(
                curveLsdAmoAddress,
                0,
                0
            );
            frxETHWETH_LPPerETH = _lpPerCoinsBalancedE18[0];
            frxETHWETH_LPPerfrxETH = _lpPerCoinsBalancedE18[1];
        }

        // Set ETH and frxETH prices
        ETH_PRICE_E18 = amoHelper.getFrxEthPriceE18();
        FRXETH_PRICE_E18 = amoHelper.getEthPriceE18();

        // vm.stopPrank();
    }

    function testPoolInfo() public {
        amoFunctionsTestSetup();

        // Fetch the pool info
        CurveLsdAmo.PoolInfo memory _poolInfo = curveLsdAmo.getFullPoolInfo();

        // Do checks
        assertEq(_poolInfo.hasCvxVault, true, "poolSet: frxETHWETH Initialization problem [hasCvxVault]");
        assertEq(_poolInfo.hasStkCvxFxsVault, true, "poolSet: frxETHWETH Initialization problem [hasStkCvxFxsVault]");
        assertEq(_poolInfo.frxEthIndex, 1, "poolSet: frxETHWETH Initialization problem [frxEthIndex]");
        assertEq(_poolInfo.ethIndex, 0, "poolSet: frxETHWETH Initialization problem [ethIndex]");
        assertEq(
            _poolInfo.rewardsContractAddress,
            address(cvxfrxETHWETH_BaseRewardPool_address),
            "poolSet: frxETHWETH Initialization problem [rewardsContractAddress]"
        );
        assertEq(
            curveLsdAmo.poolAddress(),
            address(frxETHWETH_Pool),
            "poolSet: frxETHWETH Initialization problem [poolAddress]"
        );
        assertEq(
            _poolInfo.lpTokenAddress,
            address(frxETHWETH_Pool),
            "poolSet: frxETHWETH Initialization problem [lpTokenAddress]"
        );
        assertEq(_poolInfo.lpDepositPid, 219, "poolSet: frxETHWETH Initialization problem [lpDepositPid]");
        // assertEq(uint256(_poolInfo.lpAbiType), uint256(CurveLsdAmo.LpAbiType.LSDWETH), "poolSet: frxETHWETH Initialization problem [lpAbiType]");
        // assertEq(uint256(_poolInfo.frxEthType), uint256(CurveLsdAmo.FrxSfrxType.FRXETH), "poolSet: frxETHWETH Initialization problem [frxEthType]");
        // assertEq(uint256(_poolInfo.ethType), uint256(CurveLsdAmo.EthType.WETH), "poolSet: frxETHWETH Initialization problem [ethType]");
    }

    function testLPValues() public {
        amoFunctionsTestSetup();

        // ============================================================================
        // ================================= DEPOSITS =================================
        // ============================================================================

        // frxETHWETH_Pool [Deposit - Balanced]
        // ===================================
        console.log("- frxETHWETH: [Deposit - Balanced] (frxETH and WETH)");
        (, uint256 _nonEthUsed0) = curveLsdAmo.depositToCurveLP(100e18, false);
        (, , uint256[5] memory _poolAndVaultAllocations) = amoHelper.showPoolAccounting(curveLsdAmoAddress);
        (uint256 lp_price_eth_e18, ) = amoHelper.getEstLpPriceEthOrUsdE18(curveLsdAmoAddress);
        lpValueInEthCurr = (_poolAndVaultAllocations[0] * lp_price_eth_e18) / (1e18); // Get the current value
        lpValueInEthDelta = lpValueInEthCurr - lpValueInEthPrev; // Get the delta
        lpValueInEthPrev = lpValueInEthCurr; // Set the previous to the current now

        // Should be about equal assuming 1:1 frxETH:WETH (virtual_price is near 1)
        assertApproxEqRel(
            lpValueInEthDelta,
            100e18 + _nonEthUsed0,
            HALF_PCT_DELTA,
            "LP Eth Value [Deposit - Balanced]: frxETHWETH LP"
        );

        // frxETHWETH_Pool [Deposit - OneCoin]
        // ===================================
        console.log("- frxETHWETH: [Deposit - OneCoin] (frxETH and WETH)");
        (, uint256 _nonEthUsed1) = curveLsdAmo.depositToCurveLP(100e18, true);

        // Refetch the allocations
        (, , _poolAndVaultAllocations) = amoHelper.showPoolAccounting(curveLsdAmoAddress);
        lpValueInEthCurr = (_poolAndVaultAllocations[0] * lp_price_eth_e18) / (1e18); // Get the current value
        lpValueInEthDelta = lpValueInEthCurr - lpValueInEthPrev; // Get the delta
        lpValueInEthPrev = lpValueInEthCurr; // Set the previous to the current now

        // Should be about equal assuming 1:1 frxETH:WETH (virtual_price is near 1)
        assertApproxEqRel(lpValueInEthDelta, 100e18, HALF_PCT_DELTA, "LP Eth Value [Deposit - OneCoin]: frxETHWETH LP");

        // ============================================================================
        // =============================== WITHDRAWALS ================================
        // ============================================================================
        // Will revert to slippage minimums anyways
        tmpAmounts[0] = 0;
        tmpAmounts[1] = 0;

        // frxETHWETH_Pool [Withdrawal - Balanced]
        // ===================================
        console.log("- frxETHWETH: [Withdrawal - Balanced] (frxETH and WETH)");
        uint256[2] memory _coinsReceived = curveLsdAmo.withdrawBalanced(100e18, tmpAmounts);

        // Refetch the allocations
        (, , _poolAndVaultAllocations) = amoHelper.showPoolAccounting(curveLsdAmoAddress);
        lpValueInEthCurr = (_poolAndVaultAllocations[0] * lp_price_eth_e18) / (1e18); // Get the current value
        lpValueInEthDelta = lpValueInEthPrev - lpValueInEthCurr; // Get the delta
        lpValueInEthPrev = lpValueInEthCurr; // Set the previous to the current now

        // Should be about 1:1
        assertApproxEqRel(
            lpValueInEthDelta,
            _coinsReceived[0] + _coinsReceived[1],
            HALF_PCT_DELTA,
            "LP Eth Value [Withdrawal - Balanced]: frxETHWETH LP"
        );

        // frxETHWETH_Pool [Withdrawal - OneCoin]
        // ===================================
        console.log("- frxETHWETH: [Withdrawal - OneCoin] (frxETH and WETH)");
        _coinsReceived = curveLsdAmo.withdrawOneCoin(50e18, 0, 0);
        uint256[2] memory _coinsReceivedTmp = curveLsdAmo.withdrawOneCoin(50e18, 1, 0);
        _coinsReceived[1] = _coinsReceivedTmp[1];

        // Refetch the allocations
        (, , _poolAndVaultAllocations) = amoHelper.showPoolAccounting(curveLsdAmoAddress);
        lpValueInEthCurr = (_poolAndVaultAllocations[0] * lp_price_eth_e18) / (1e18); // Get the current value
        lpValueInEthDelta = lpValueInEthPrev - lpValueInEthCurr; // Get the delta
        lpValueInEthPrev = lpValueInEthCurr; // Set the previous to the current now

        // Should be about 1:1
        assertApproxEqRel(
            lpValueInEthDelta,
            _coinsReceived[0] + _coinsReceived[1],
            HALF_PCT_DELTA,
            "LP Eth Value [Withdrawal - OneCoin]: frxETHWETH LP"
        );
    }

    function testRequestEtherByTimelockOrOperator() public {
        amoFunctionsTestSetup();

        // Switch back to the operator
        vm.stopPrank();
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);

        // Set the ETH balance to 1100
        vm.deal(curveLsdAmoAddress, 1100 ether);

        // Deposit into Curve LP
        console.log("- testRequestEther: [depositToCurveLP]");
        (uint256 _lpOut, uint256 _nonEthUsed0) = curveLsdAmo.depositToCurveLP(1000 ether, false);

        // Deposit a quarter of the Curve LP into cvxLP
        console.log("- testRequestEther: [depositToCvxLPVault]");
        curveLsdAmo.depositToCvxLPVault(_lpOut / 4);

        // Deposit a quarter of the Curve LP into stkcvxLP
        console.log("- testRequestEther: [depositCurveLPToVaultedStkCvxLP]");
        curveLsdAmo.depositCurveLPToVaultedStkCvxLP(_lpOut / 4, 0);

        // Temporarily stop the prank
        vm.stopPrank();

        // Random person test 1 (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            0.01 ether,
            false,
            0
        );

        // Random person test 2 (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            0.01 ether,
            true,
            0
        );

        // Random person test 3 (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            150 ether,
            false,
            0
        );

        // Random person test 4 (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            150 ether,
            true,
            0
        );

        // Switch back to the CurveAMO Operator
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);

        // Request a small amount of ETH (balanced, fails due to invalid recipient)
        vm.expectRevert(abi.encodeWithSignature("InvalidRecipient()"));
        curveLsdAmo.requestEtherByTimelockOrOperator(payable(testUserAddress), 0.01 ether, false, 0);

        // Request a small amount of ETH (balanced)
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            0.01 ether,
            false,
            0
        );

        // Request a small amount of ETH (oneCoin)
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            0.01 ether,
            true,
            0
        );

        // Request a larger amount of ETH (balanced)
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            150 ether,
            false,
            0
        );

        // Request a larger amount of ETH (oneCoin)
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            150 ether,
            true,
            0
        );

        // Swap a huge amount of frxETH into the pool to imbalance it
        // ==============================
        // Set up callable curve pool
        CurvePool curvePool = CurvePool(curveLsdAmo.poolAddress());

        // Switch to the frxETH Comptroller, mint some frxETH, then do the big swap
        vm.stopPrank();
        vm.startPrank(FRXETH_COMPTROLLER);
        frxETH.minter_mint(FRXETH_COMPTROLLER, 2500e18);
        frxETH.approve(address(curveLsdAmo.poolAddress()), 2500e18);
        curvePool.exchange(1, 0, 2500e18, 0);

        // Switch back to the CurveAMO Operator
        vm.stopPrank();
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);

        // Calculate how much ETH is already free so you can go past that and start unwinding the CurveAMO
        uint256 _freeEth = curveLsdAmoAddress.balance + etherRouterAddress.balance + WETH.balanceOf(curveLsdAmoAddress);
        console.log("_freeEth: ", _freeEth);

        // Request a large amount of ETH (oneCoin) on a manipulated pool without a _minOneCoinOut
        // Should revert due to the pool imbalance check
        vm.expectRevert(abi.encodeWithSignature("PoolTooImbalanced()"));
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            _freeEth + 150 ether,
            true,
            0
        );

        // Request a large amount of ETH (oneCoin) on a manipulated pool, but supply a _minOneCoinOut
        // Should fail on remove_liquidity_one_coin due to slippage
        vm.expectRevert(bytes("Not enough coins removed"));
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            _freeEth + 150 ether,
            true,
            151 ether // ETH out
        );

        // Request a large amount of ETH (balanced) on a manipulated pool
        // Should succeed because a balanced withdrawal on a temporarily manipulated pool should be value-additive
        // since when the pool re-balances to the (real) market rate, you would have gotten cheaper tokens and the attacker
        // suffered the loss
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            _freeEth + 500 ether,
            false,
            0
        );
    }

    function testWithdrawAll_Route0() public {
        amoFunctionsTestSetup();

        // Switch back to the operator
        vm.stopPrank();
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);

        // Set the ETH balance to 100
        vm.deal(curveLsdAmoAddress, 100 ether);

        // Take initial snapshots
        _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

        // Deposit into Curve LP
        console.log("- testRequestEther: [depositToCurveLP - balanced]");
        (uint256 _lpOut, uint256 _nonEthUsed0) = curveLsdAmo.depositToCurveLP(100e18, false);

        // Will revert to slippage minimums anyways
        tmpAmounts[0] = 0;
        tmpAmounts[1] = 0;

        // withdrawAll (balanced)
        uint256[2] memory _amountsReceived = curveLsdAmo.withdrawAll(tmpAmounts, false);

        // Take delta snapshots
        (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
        (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);

        // Delta of frxETH/ETH/WETH should have stayed the same
        tmpNetTotalWithdrawableBothAsBalanced =
            _amoAccountingNets[0].totalBalancedWithdrawableFrxETH +
            _amoAccountingNets[0].totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            0,
            HALF_PCT_DELTA,
            "testWithdrawAll_Route0 [balanced]: tmpNetTotalWithdrawableBothAsBalanced"
        );

        // ETH and WETH deposited should equal ETH and WETH received from the withdrawal
        assertApproxEqRel(
            _amountsReceived[0] + _amountsReceived[1],
            100e18 + _nonEthUsed0,
            HALF_PCT_DELTA,
            "testWithdrawAll_Route0 [balanced]: coin balances"
        );
    }

    function testWithdrawAll_Route1() public {
        amoFunctionsTestSetup();

        // Switch back to the operator
        vm.stopPrank();
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);

        // Set the ETH balance to 100
        vm.deal(curveLsdAmoAddress, 100 ether);

        // Take initial snapshots
        _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

        // Deposit into Curve LP
        console.log("- testRequestEther: [depositToCurveLP - balanced]");
        (uint256 _lpOut, uint256 _nonEthUsed0) = curveLsdAmo.depositToCurveLP(100e18, false);

        // Set up to revert (one coin needs exactly one of the tmpAmounts value to be nonzero)
        tmpAmounts[0] = 0;
        tmpAmounts[1] = 0;

        // withdrawAll (will revert)
        vm.expectRevert(abi.encodeWithSignature("MinAmountsIncorrect()"));
        curveLsdAmo.withdrawAll(tmpAmounts, true);

        // Set up to revert (version 2) (one coin needs exactly one of the tmpAmounts value to be nonzero)
        tmpAmounts[0] = 1;
        tmpAmounts[1] = 1;

        // withdrawAll (will revert - version 2)
        vm.expectRevert(abi.encodeWithSignature("MinAmountsIncorrect()"));
        curveLsdAmo.withdrawAll(tmpAmounts, true);

        // Will revert to slippage minimums anyways
        tmpAmounts[0] = 1;
        tmpAmounts[1] = 0;

        // withdrawAll (oneCoin)
        uint256[2] memory _amountsReceived = curveLsdAmo.withdrawAll(tmpAmounts, true);

        // Take delta snapshots
        (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
        (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);

        // Delta of frxETH/ETH/WETH should have stayed the same
        tmpNetSumBothFullOneStepWithdrawables =
            _amoAccountingNets[0].totalOneStepWithdrawableFrxETH +
            _amoAccountingNets[0].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            0,
            HALF_PCT_DELTA,
            "testWithdrawAll_Route1 [oneCoin: WETH]: tmpNetSumBothFullOneStepWithdrawables"
        );

        // WETH and frxETH deposited should equal WETH and frxETH received from the withdrawal
        assertApproxEqRel(
            _amountsReceived[0],
            100e18 + _nonEthUsed0,
            HALF_PCT_DELTA,
            "testWithdrawAll_Route1 [oneCoin: WETH]: coin balances"
        );
    }

    function testWithdrawAll_Route2() public {
        amoFunctionsTestSetup();

        // Switch back to the operator
        vm.stopPrank();
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);

        // Set the ETH balance to 100
        vm.deal(curveLsdAmoAddress, 100 ether);

        // Take initial snapshots
        _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

        // Deposit into Curve LP
        console.log("- testRequestEther: [depositToCurveLP - balanced]");
        (uint256 _lpOut, uint256 _nonEthUsed0) = curveLsdAmo.depositToCurveLP(100e18, false);

        // Will revert to slippage minimums anyways
        tmpAmounts[0] = 0;
        tmpAmounts[1] = 1;

        // withdrawAll (oneCoin)
        uint256[2] memory _amountsReceived = curveLsdAmo.withdrawAll(tmpAmounts, true);

        // Take delta snapshots
        (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
        (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);

        // Delta of frxETH/ETH/WETH should have stayed the same
        tmpNetSumBothFullOneStepWithdrawables =
            _amoAccountingNets[0].totalOneStepWithdrawableFrxETH +
            _amoAccountingNets[0].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            0,
            HALF_PCT_DELTA,
            "testWithdrawAll_Route1 [oneCoin: frxETH]: tmpNetSumBothFullOneStepWithdrawables"
        );

        // WETH and frxETH deposited should equal WETH and frxETH received from the withdrawal
        assertApproxEqRel(
            _amountsReceived[1],
            100e18 + _nonEthUsed0,
            HALF_PCT_DELTA,
            "testWithdrawAll_Route1 [oneCoin: frxETH]: coin balances"
        );
    }

    function test_OverBudget() public {
        amoFunctionsTestSetup();
        vm.stopPrank();

        // startHoax(FRAX_TIMELOCK);
        // curveLsdAmo.setMaxLP(20_000e18);

        console.log("<<<Dump ETH into EtherRouter>>>");
        vm.deal(address(etherRouter), 100 ether);

        // Impersonate the timelock
        vm.startPrank(FRAX_TIMELOCK);

        console.log("<<<sweepEther (1)>>>");
        etherRouter.sweepEther(0, true);

        console.log("<<<Set a low budget>>>");
        curveLsdAmo.setMaxLP(150e18);

        console.log("<<<Dump more ETH into EtherRouter>>>");
        vm.deal(address(etherRouter), 250 ether);

        console.log("<<<Try to sweep the ETH into LP (should fail due to the budget)>>>");
        vm.expectRevert(abi.encodeWithSignature("OverLpBudget()"));
        etherRouter.sweepEther(0, true);

        console.log("<<<Raise the budget>>>");
        curveLsdAmo.setMaxLP(10_000e18);

        console.log("<<<Try to sweep the ETH into LP (should succeed now)>>>");
        etherRouter.sweepEther(0, true);
    }

    function testLpCvxLPStkCvxLPE2EActions() public {
        amoFunctionsTestSetup();
        vm.stopPrank();

        // Take initial snapshots
        console.log("<<<Take initial snapshots>>>");
        _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

        // Deposit some WETH into the frxETHWETH pool
        // =============================

        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.depositToCurveLP(200e18, false);

        // With the timelock (correct)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        (uint256 _lpOut, ) = curveLsdAmo.depositToCurveLP(200e18, false);

        // Lock half of the LP into cvxLP, not stkcvxLP
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.depositToCvxLPVault(_lpOut / 2);

        // With the timelock (correct)
        console.log("<<<depositToCvxLPVault>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.depositToCvxLPVault(_lpOut / 2);

        // Vault most of remaining half of the LP into stkcvxLP
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        bytes32 vault_kek_id = curveLsdAmo.depositCurveLPToVaultedStkCvxLP((_lpOut * 9) / (10 * 2), 0);

        // With the timelock (correct)
        console.log("<<<depositCurveLPToVaultedStkCvxLP (1st time)>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vault_kek_id = curveLsdAmo.depositCurveLPToVaultedStkCvxLP((_lpOut * 9) / (10 * 2), 0);

        // Vault the remaining LP into stkcvxLP, reusing the existing stake
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.depositCurveLPToVaultedStkCvxLP(_lpOut / (10 * 2), vault_kek_id);

        // With the timelock (correct)
        console.log("<<<depositCurveLPToVaultedStkCvxLP (2nd time)>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.depositCurveLPToVaultedStkCvxLP(_lpOut / (10 * 2), vault_kek_id);

        // Wait until after the stake unlocks
        // =============================
        mineBlocksBySecond(8 days);

        // Unwrap & unvault half of the cvxLP. Some still remains in the vault
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.withdrawAndUnwrapVaultedCvxLP(_lpOut / 4, true);

        // With the timelock (correct)
        console.log("<<<withdrawAndUnwrapVaultedCvxLP>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.withdrawAndUnwrapVaultedCvxLP(_lpOut / 4, true);

        // Withdraw the entire amount of stkcvxLP from the FXS vault to get normal LP
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.withdrawAndUnwrapFromFxsVault(vault_kek_id, true);

        // With the timelock (correct)
        console.log("<<<withdrawAndUnwrapFromFxsVault>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.withdrawAndUnwrapFromFxsVault(vault_kek_id, true);

        // ===============================================================
        // =========== Do another deposit and withdrawal cycle ===========
        // ===============================================================

        /// Take deltas after deposits & withdrawals
        // -----------------------------------------
        (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
        (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);
        _deltaValidatorDepositInfos[0] = deltaValidatorDepositInfoSnapshot(_validatorDepositInfoSnapshotInitial);
        _deltaValidatorPoolAccountings[0] = deltaValidatorPoolAccountingSnapshot(
            _validatorPoolAccountingSnapshotInitial
        );

        // Make sure the balances are ok so far
        assertApproxEqAbs(
            _amoPoolAccountingFinals[1].lpBalance,
            (_lpOut * 3) / 4,
            1 wei,
            "Midpoint 1 check [LP balance]"
        );
        assertApproxEqAbs(
            _amoPoolAccountingFinals[1].lpInCvxBooster,
            _lpOut / 4,
            1 wei,
            "Midpoint 1 check [cvxLP balance]"
        );
        assertApproxEqAbs(_amoPoolAccountingFinals[1].lpInStkCvxFarm, 0, 1 wei, "Midpoint 1 check [stkcvxLP balance]");

        // Lock part of the LP in cvxLP, not stkcvxLP
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.depositToCvxLPVault(_lpOut / 4);

        // With the timelock (correct)
        console.log("<<<depositToCvxLPVault (2nd time)>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.depositToCvxLPVault(_lpOut / 4);

        // Vault some of the LP into stkcvxLP
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        vault_kek_id = curveLsdAmo.depositCurveLPToVaultedStkCvxLP(_lpOut / 8, 0);

        // With the timelock (correct)
        console.log("<<<depositCurveLPToVaultedStkCvxLP (3rd time)>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vault_kek_id = curveLsdAmo.depositCurveLPToVaultedStkCvxLP(_lpOut / 8, 0);

        // Vault a some LP into stkcvxLP, reusing the existing stake
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.depositCurveLPToVaultedStkCvxLP(_lpOut / 8, vault_kek_id);

        // With the timelock (correct)
        console.log("<<<depositCurveLPToVaultedStkCvxLP (3rd time)>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.depositCurveLPToVaultedStkCvxLP(_lpOut / 8, vault_kek_id);

        // Wait until after the stake unlocks again
        // =============================
        mineBlocksBySecond(8 days);

        /// Take deltas after deposits
        // -----------------------------------------
        (_amoAccountingFinals[2], _amoAccountingNets[1]) = finalAMOSnapshot(_amoAccountingFinals[1]);
        (_amoPoolAccountingFinals[2], _amoPoolAccountingNets[1]) = finalPoolSnapshot(_amoPoolAccountingFinals[1]);
        _deltaValidatorDepositInfos[1] = deltaValidatorDepositInfoSnapshot(_deltaValidatorDepositInfos[0].start);
        _deltaValidatorPoolAccountings[1] = deltaValidatorPoolAccountingSnapshot(
            _deltaValidatorPoolAccountings[0].start
        );

        // Make sure the balances are ok so far
        assertApproxEqAbs(_amoPoolAccountingFinals[2].lpBalance, _lpOut / 4, 2 wei, "Midpoint 2 check [LP balance]");
        assertApproxEqAbs(
            _amoPoolAccountingFinals[2].lpInCvxBooster,
            _lpOut / 2,
            2 wei,
            "Midpoint 2 check [cvxLP balance]"
        );
        assertApproxEqAbs(
            _amoPoolAccountingFinals[2].lpInStkCvxFarm,
            _lpOut / 4,
            2 wei,
            "Midpoint 2 check [stkcvxLP balance]"
        );

        // Withdraw the entire amount of cvxLP to get normal LP
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.withdrawAndUnwrapVaultedCvxLP(_lpOut / 2, true);

        // With the timelock (correct)
        console.log("<<<withdrawAndUnwrapVaultedCvxLP (2nd time)>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.withdrawAndUnwrapVaultedCvxLP(_lpOut / 2, true);

        // Withdraw the entire amount of stkcvxLP from the FXS vault to get normal LP
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.withdrawAndUnwrapFromFxsVault(vault_kek_id, true);

        // With the timelock (correct)
        console.log("<<<withdrawAndUnwrapFromFxsVault (2nd time)>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.withdrawAndUnwrapFromFxsVault(vault_kek_id, true);

        // Wait 8 days
        // =============================
        mineBlocksBySecond(8 days);

        // Claim rewards
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.claimRewards(true, true);

        // Test coverage routes
        vm.startPrank(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.claimRewards(false, false);
        curveLsdAmo.claimRewards(false, true);
        curveLsdAmo.claimRewards(true, false);
        mineBlocksBySecond(1 days);
        curveLsdAmo.claimRewards(true, true);
        vm.stopPrank();

        // Withdraw rewards
        // =============================
        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.withdrawRewards(100, 200, 0, 300, FRAX_TIMELOCK);

        // With the timelock (works, but pointless)
        console.log("<<<withdrawRewards (1st time)>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.withdrawRewards(0, 0, 0, 0, FRAX_TIMELOCK);

        // With the timelock (correct)
        console.log("<<<withdrawRewards (2nd time)>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.withdrawRewards(100, 200, 0, 300, FRAX_TIMELOCK);

        // With an incorrect rewards recipient (should fail)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("InvalidRecipient()"));
        curveLsdAmo.withdrawRewards(100, 200, 0, 300, testUserAddress);

        // Take deltas at the end
        // -----------------------------------------
        (_amoAccountingFinals[3], _amoAccountingNets[2]) = finalAMOSnapshot(_amoAccountingFinals[2]);
        (_amoPoolAccountingFinals[3], _amoPoolAccountingNets[2]) = finalPoolSnapshot(_amoPoolAccountingFinals[2]);
        _deltaValidatorDepositInfos[2] = deltaValidatorDepositInfoSnapshot(_deltaValidatorDepositInfos[1].start);
        _deltaValidatorPoolAccountings[2] = deltaValidatorPoolAccountingSnapshot(
            _deltaValidatorPoolAccountings[1].start
        );

        // Do checks
        assertApproxEqAbs(_amoPoolAccountingFinals[3].lpBalance, _lpOut, 3 wei, "End check [LP balance]");
        assertApproxEqAbs(_amoPoolAccountingFinals[3].lpInCvxBooster, 0, 3 wei, "End check [cvxLP balance]");
        assertApproxEqAbs(_amoPoolAccountingFinals[3].lpInStkCvxFarm, 0, 3 wei, "End check [stkcvxLP balance]");
    }

    function testSetOperatorAddress() public {
        amoFunctionsTestSetup();
        vm.stopPrank();

        // Try setting the Operator as a random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS,
                testUserAddress
            )
        );
        curveLsdAmo.setOperatorAddress(testUserAddress);

        // Set the Operator correctly
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setOperatorAddress(testUserAddress);
    }

    function testWhitelistedExecute() public {
        amoFunctionsTestSetup();
        vm.stopPrank();

        // FRAX_WHALE sends some FRAX to the the Curve AMO accidentally
        hoax(ConstantsSBTS.Mainnet.FRAX_WHALE);
        fraxERC20.transfer(curveLsdAmoAddress, 2000e18);

        // Generate the calldata for sending the misplaced FRAX back to the FRAX_WHALE
        bytes memory _calldata = abi.encodeWithSelector(
            bytes4(0xa9059cbb),
            address(ConstantsSBTS.Mainnet.FRAX_WHALE),
            1000e18
        );

        // Try setting an execute target as random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS,
                testUserAddress
            )
        );
        curveLsdAmo.setExecuteTarget(address(fraxERC20), true);

        // Set an execute target correctly
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setExecuteTarget(address(fraxERC20), true);

        // Try to execute without enabling the selector first (should fail)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedSelector()"));
        curveLsdAmo.whitelistedExecute(address(fraxERC20), 0, _calldata);

        // Try setting an execute selector as random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS,
                testUserAddress
            )
        );
        curveLsdAmo.setExecuteSelector(address(fraxERC20), bytes4(0xa9059cbb), true);

        // Try setting an execute selector on a non-approved target (should fail)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedTarget()"));
        curveLsdAmo.setExecuteSelector(address(usdcERC20), bytes4(0xa9059cbb), true);

        // Try setting an execute selector correctly
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setExecuteSelector(address(fraxERC20), bytes4(0xa9059cbb), true);

        // Try to send half of the misplaced FRAX back (with whitelistedExecute) as a random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS,
                testUserAddress
            )
        );
        curveLsdAmo.whitelistedExecute(address(fraxERC20), 0, _calldata);

        // Send the FRAX back correctly
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.whitelistedExecute(address(fraxERC20), 0, _calldata);

        // Disable the execute target
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setExecuteTarget(address(fraxERC20), false);

        // Try to execute after the target is disabled (should fail)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedTarget()"));
        curveLsdAmo.whitelistedExecute(address(fraxERC20), 0, _calldata);

        // Re-enable an execute target
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setExecuteTarget(address(fraxERC20), true);

        // Disable a specific selector but leave the target enabled
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setExecuteSelector(address(fraxERC20), bytes4(0xa9059cbb), false);

        // Try to execute after the selector is disabled (should fail)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedSelector()"));
        curveLsdAmo.whitelistedExecute(address(fraxERC20), 0, _calldata);
    }

    function testPoolSwap() public {
        amoFunctionsTestSetup();
        vm.stopPrank();

        // frxETHWETH Pool Swap tests
        // [0]: WETH, [1]: frxETH
        // ====================================

        // Swap frxETH for WETH
        // --------------------------------
        // Take a snapshot
        console.log("- frxETHWETH: SWAP (frxETH => WETH)");
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

        // Prep the inputs
        uint256 _inIndex = 1;
        uint256 _outIndex = 0;
        uint256 _inAmount = 1e18;
        uint256 _minOutFromUser = 0.998e18;

        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        console.log("   ---> Expected to revert: NotTimelockOrOperator");
        curveLsdAmo.poolSwap(_inIndex, _outIndex, _inAmount, _minOutFromUser);

        // Try with too high of a _minOutFromUser (should revert)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert();
        console.log("   ---> Expected to revert: bad _minOutFromUser");
        curveLsdAmo.poolSwap(_inIndex, _outIndex, _inAmount, _minOutFromUser);

        // Relax the swap slippage
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setSlippages(600, 1000, 100, 10_000, 150_000, 850_000);

        // Do the swap with a correct _minOutFromUser
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        _minOutFromUser = 0.994e18;
        curveLsdAmo.poolSwap(_inIndex, _outIndex, _inAmount, _minOutFromUser);
        (, _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);

        // Check balances
        assertEq(
            _amoPoolAccountingNets[0].freeCoinBalances[_inIndex],
            _inAmount,
            "testPoolSwap 1: balance of input check"
        );
        assertApproxEqAbs(
            _amoPoolAccountingNets[0].freeCoinBalances[_outIndex],
            _inAmount,
            0.0075e18,
            "testPoolSwap 1: balance of output check"
        );

        // Swap ETH for frxETH
        // --------------------------------
        // Take snapshot
        console.log("- frxETHWETH: SWAP (WETH => frxETH)");
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

        // Prep inputs
        _inIndex = 0;
        _outIndex = 1;
        _inAmount = 1e18;
        _minOutFromUser = 1.01e18;

        // Tighten the swap slippage
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setSlippages(600, 1000, 100, 600, 150_000, 850_000);

        // Try with too low of a _minOutFromUser (should revert)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert();
        console.log("   ---> Expected to revert: bad _minOutFromUser");
        curveLsdAmo.poolSwap(_inIndex, _outIndex, _inAmount, _minOutFromUser);

        // Relax the swap slippage
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setSlippages(600, 1000, 100, 10_000, 150_000, 850_000);

        // Try again with a correct _minOutFromUser
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        _minOutFromUser = 1.002011e18;
        curveLsdAmo.poolSwap(_inIndex, _outIndex, _inAmount, _minOutFromUser);

        // Check balances
        (, _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);
        assertEq(
            _amoPoolAccountingNets[0].freeCoinBalances[_inIndex],
            _inAmount,
            "testPoolSwap 2: balance of input check"
        );
        assertApproxEqAbs(
            _amoPoolAccountingNets[0].freeCoinBalances[_outIndex],
            _inAmount,
            0.0075e18,
            "testPoolSwap 2: balance of output check"
        );
    }

    function testBurnFrxEth() public {
        amoFunctionsTestSetup();
        vm.stopPrank();

        // Take initial snapshots
        _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        curveLsdAmo.burnFrxEth(100e18);

        // Burn some frxETH
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.burnFrxEth(100e18);

        // Take delta snapshots
        (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
        (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);

        // Assert AMO Accounting Deltas
        assertApproxEqRel(
            _amoAccountingNets[0].frxETHInContract,
            100e18,
            HALF_PCT_DELTA,
            "AMO Accounting [testBurnFrxEth]: frxETHInContract"
        );
    }

    function testEthWethWrappingUnwrapping() public {
        amoFunctionsTestSetup();
        vm.stopPrank();

        // Take initial snapshots
        _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOperatorOrEtherRouter()"));
        curveLsdAmo.wrapEthToWeth(100e18);

        // Exchange some ETH for WETH
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.wrapEthToWeth(100e18);

        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOperatorOrEtherRouter()"));
        curveLsdAmo.unwrapWethToEth(100e18);

        // Exchange the WETH back for ETH
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.unwrapWethToEth(100e18);

        // Take delta snapshots
        (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
        (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);

        // Assert AMO Accounting Deltas
        assertApproxEqRel(
            _amoAccountingNets[0].ethInContract,
            0,
            HALF_PCT_DELTA,
            "AMO Accounting [testEthWethWrappingUnwrapping]: ethInContract"
        );
    }

    // function testEthStEthConversions() public {
    //     amoFunctionsTestSetup();
    //     vm.stopPrank();

    //     // Take initial balance and snapshots
    //     uint256 _ethBalInitial = curveLsdAmoAddress.balance;
    //     _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
    //     _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

    //     // With random person (fail)
    //     hoax(testUserAddress);
    //     vm.expectRevert(abi.encodeWithSignature("NotTimelockOperatorOrEtherRouter()"));
    //     curveLsdAmo.convertEthToStEth(100e18);

    //     // Exchange some ETH for stETH. Should be 1:1
    //     uint256 _stEthBefore = stETHERC20.balanceOf(curveLsdAmoAddress);
    //     hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
    //     curveLsdAmo.convertEthToStEth(100e18);
    //     uint256 _stEthOut = stETHERC20.balanceOf(curveLsdAmoAddress) - _stEthBefore;

    //     // Take delta snapshots after ETH -> stETH
    //     (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
    //     (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);

    //     // Assert AMO Accounting Deltas
    //     assertApproxEqRel(
    //         _amoAccountingNets[0].ethInContract,
    //         100e18,
    //         HALF_PCT_DELTA,
    //         "AMO Accounting [testEthStEthConversion - ETH to stETH]: ethInContract"
    //     );

    //     // With random person (fail)
    //     hoax(testUserAddress);
    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "AddressIsNotTimelock(address,address)",
    //             ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS,
    //             testUserAddress
    //         )
    //     );
    //     curveLsdAmo.setSlippages(3000, 10_000, 100, 10, 150000, 850000);

    //     // Tighten the swap slippage (0.03% -> 0.0001%)
    //     hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
    //     curveLsdAmo.setSlippages(3000, 10_000, 100, 1, 150000, 850000);

    //     // Test slippage for 1 <> 1 conversions
    //     // ==================================

    //     // Should fail due to slippage (stETH -> ETH)
    //     hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
    //     vm.expectRevert(); // Tests EthLsdConversionSlippage
    //     curveLsdAmo.convertStEthToEth(_stEthOut, true);

    //     // // Should fail due to slippage (ETH -> stETH)
    //     // hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
    //     // vm.expectRevert(); // Tests EthLsdConversionSlippage
    //     // curveLsdAmo.convertEthToStEth(100e18);

    //     // Try again (should no-op and not execute the swap)
    //     hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
    //     curveLsdAmo.convertStEthToEth(_stEthOut, false);

    //     // Exchange the stETH back to ETH. NOT 1:1.
    //     // ==================================

    //     // Loosen the swap slippage (0.0001% -> 1%)
    //     hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
    //     curveLsdAmo.setSlippages(3000, 10_000, 100, 10_000, 150000, 850000);

    //     // With random person (fail)
    //     hoax(testUserAddress);
    //     vm.expectRevert(abi.encodeWithSignature("NotTimelockOperatorOrEtherRouter()"));
    //     curveLsdAmo.convertStEthToEth(_stEthOut, true);

    //     // Try again now (should execute)
    //     hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
    //     curveLsdAmo.convertStEthToEth(_stEthOut, true);

    //     // Take delta snapshots and ETH balance after stETH -> ETH
    //     uint256 _ethBalFinal = curveLsdAmoAddress.balance;
    //     (_amoAccountingFinals[2], _amoAccountingNets[1]) = finalAMOSnapshot(_amoAccountingFinals[1]);
    //     (_amoPoolAccountingFinals[2], _amoPoolAccountingNets[1]) = finalPoolSnapshot(_amoPoolAccountingFinals[1]);

    //     // Assert AMO Accounting Deltas
    //     assertApproxEqRel(
    //         _amoAccountingNets[1].ethInContract,
    //         _stEthOut,
    //         HALF_PCT_DELTA,
    //         "AMO Accounting [testEthStEthConversion - stETH to ETH]: ethInContract"
    //     );

    //     // Assert balances (double check)
    //     assertApproxEqRel(
    //         _ethBalInitial,
    //         _ethBalFinal,
    //         HALF_PCT_DELTA,
    //         "ETH balance [testEthStEthConversion - stETH to ETH]"
    //     );
    // }

    // function testExchangeFrxEthSfrxEth() public {
    //     amoFunctionsTestSetup();
    //     vm.stopPrank();

    //     // Take initial snapshots
    //     _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
    //     _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

    //     // With random person (fail)
    //     hoax(testUserAddress);
    //     vm.expectRevert(abi.encodeWithSignature("NotTimelockOperatorOrEtherRouter()"));
    //     curveLsdAmo.exchangeFrxEthSfrxEth(100e18, true);

    //     // Exchange some frxETH for sfrxETH
    //     hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
    //     uint256 _sfrxEthOut = curveLsdAmo.exchangeFrxEthSfrxEth(100e18, true);

    //     // With random person (fail)
    //     hoax(testUserAddress);
    //     vm.expectRevert(abi.encodeWithSignature("NotTimelockOperatorOrEtherRouter()"));
    //     curveLsdAmo.exchangeFrxEthSfrxEth(_sfrxEthOut, false);

    //     // Exchange the resultant sfrxETH for frxETH
    //     hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
    //     curveLsdAmo.exchangeFrxEthSfrxEth(_sfrxEthOut, false);

    //     // Take delta snapshots
    //     (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
    //     (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);

    //     // Assert AMO Accounting Deltas
    //     assertApproxEqAbs(
    //         _amoAccountingNets[0].frxETHInContract,
    //         0,
    //         0.001e18,
    //         "AMO Accounting [testExchangeFrxEthSfrxEth]: frxETHInContract"
    //     );
    // }

    function testScroungeEthFromEquivalents() public {
        amoFunctionsTestSetup();
        vm.stopPrank();

        // Drain the AMO of ETH
        vm.deal(curveLsdAmoAddress, 0);

        // Take some balances before
        uint256 _ethBalBefore = curveLsdAmoAddress.balance;
        uint256 _wethBalBefore = WETH.balanceOf(curveLsdAmoAddress);

        // With random person (fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOperatorOrEtherRouter()"));
        curveLsdAmo.scroungeEthFromEquivalents(100e18);

        // Scrounge for ETH by converting WETH to ETH
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        uint256 _ethOut = curveLsdAmo.scroungeEthFromEquivalents(100e18);

        // Take some balances after
        uint256 _ethBalAfter = curveLsdAmoAddress.balance;
        uint256 _wethBalAfter = WETH.balanceOf(curveLsdAmoAddress);

        // Assert balance delta for ETH
        assertApproxEqRel(
            _ethBalAfter - _ethBalBefore,
            100e18,
            HALF_PCT_DELTA,
            "ETH balance [scroungeEthFromEquivalents]"
        );

        // Assert balance delta for WETH
        assertApproxEqRel(
            _wethBalBefore - _wethBalAfter,
            100e18,
            HALF_PCT_DELTA,
            "WETH balance [scroungeEthFromEquivalents]"
        );
    }

    function testZach_RemainingMisCalc() public {
        amoFunctionsTestSetup();
        uint256 ethBal = address(curveLsdAmo).balance;
        uint256 wethBal = WETH.balanceOf(address(curveLsdAmo));
        curveLsdAmo.requestEtherByTimelockOrOperator(
            payable(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS),
            ethBal + wethBal + 1e18,
            true,
            0
        );
    }
}
