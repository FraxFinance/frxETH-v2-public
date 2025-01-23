// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./CurveAmoBaseTest.t.sol";

contract CurveAMODetailedAccountingTest is CurveAmoBaseTest {
    // For determining expected ratios
    uint256 public frxETHWETH_LPPerETH;
    uint256 public frxETHWETH_LPPerfrxETH;

    // Temporary. Prevents stack too deep errors
    uint256[2] public tmpAmounts;
    uint256[2] public tmpCoinsReceived;
    uint256 public ETH_PRICE_E18;
    uint256 public FRXETH_PRICE_E18;
    uint256 tmpNetSumBothFullOneStepWithdrawables;
    uint256 tmpNetTotalWithdrawableBothAsBalanced;
    uint256 tmpLpDeposited;
    uint256[5] tmpPoolAndVaultAllocations;
    uint256[] tmpProfits;
    uint256[10] tmpAllocations;

    function detailedAccountingTestSetup() public {
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

    function testFrxETHWETHLiquidityLPOnly() public {
        detailedAccountingTestSetup();

        // Take initial snapshots
        _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

        // Action 1 - Deposit funds to pool
        // -------------------------------------------------------------------------
        // -------------------------------------------------------------------------
        (uint256 _lpOut, uint256 _nonEthUsed) = curveLsdAmo.depositToCurveLP(100e18, false);
        console.log("- frxETHWETH: deposit (frxETH and WETH)");

        // Take snapshots again
        (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
        (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);

        // Print the LP balance delta
        console.log("lpBalance delta:", _amoPoolAccountingNets[0].lpBalance);

        // Assert AMO Accounting for deltas
        assertEq(_amoAccountingNets[0].frxETHInContract, _nonEthUsed, "AMO Accounting 1: frxETHInContract");
        assertEq(_amoAccountingNets[0].ethInContract, 100e18, "AMO Accounting 1: ethInContract");
        assertEq(_amoPoolAccountingNets[0].lpDeposited, _lpOut, "AMO Accounting 1: lpDeposited");

        // The sum of both oneStepWithdrawals should be ≈2x LP balance since virtual_price is ≈ 1
        // Check oneStep withdrawables [amo accounting]
        tmpNetSumBothFullOneStepWithdrawables =
            _amoAccountingNets[0].totalOneStepWithdrawableFrxETH +
            _amoAccountingNets[0].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            2 * _lpOut,
            HALF_PCT_DELTA,
            "AMO Accounting 1: tmpNetSumBothFullOneStepWithdrawables"
        );

        // The sum of both tokens in a balanced withdrawal should ≈ LP balance since virtual_price is ≈ 1
        // Check balanced withdrawables [amo accounting]
        tmpNetTotalWithdrawableBothAsBalanced =
            _amoAccountingNets[0].totalBalancedWithdrawableFrxETH +
            _amoAccountingNets[0].totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            _lpOut,
            HALF_PCT_DELTA,
            "AMO Accounting 1: tmpNetTotalWithdrawableBothAsBalanced"
        );

        // Assert AMO Pool Accounting
        // LP balances & deposits
        assertEq(
            _amoPoolAccountingNets[0].lpTotalAllForms,
            _amoPoolAccountingNets[0].lpDeposited,
            "AMO Pool Accounting 1: LP balance accounting"
        );
        assertGt(
            _amoPoolAccountingFinals[1].lpMaxAllocation,
            _amoPoolAccountingNets[0].lpDeposited,
            "AMO Pool Accounting 1: LP max allocation check"
        );

        // Lp balances and deposits
        assertEq(_amoPoolAccountingNets[0].lpBalance, _lpOut, "AMO Pool Accounting 1: lpBalance");
        assertEq(_amoPoolAccountingNets[0].lpDepositedInVaults, 0, "AMO Pool Accounting 1: lpDepositedInVaults");

        // Check oneStep withdrawable [pool accounting]
        tmpNetSumBothFullOneStepWithdrawables =
            _amoPoolAccountingNets[0].totalOneStepWithdrawableFrxETH +
            _amoPoolAccountingNets[0].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            _lpOut * 2,
            HALF_PCT_DELTA,
            "AMO Pool Accounting 1: tmpNetSumBothFullOneStepWithdrawables"
        );

        // Check balanced withdrawables [pool accounting]
        tmpNetTotalWithdrawableBothAsBalanced =
            _amoPoolAccountingNets[0].totalBalancedWithdrawableFrxETH +
            _amoPoolAccountingNets[0].totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            _lpOut,
            ONE_PCT_DELTA,
            "AMO Pool Accounting 1: tmpNetTotalWithdrawableBothAsBalanced"
        );

        // Action 2 - withdraw one coin (WETH and frxETH respectively) from pool (once per coin)
        // -------------------------------------------------------------------------
        // -------------------------------------------------------------------------
        curveLsdAmo.withdrawOneCoin(25e18, 0, 0);
        console.log("- frxETHWETH: withdraw one coin (frxETH) from pool");
        curveLsdAmo.withdrawOneCoin(25e18, 1, 0);
        console.log("- frxETHWETH: withdraw one coin (WETH) from pool");

        /// Take snapshot after withdrawals
        // -----------------------------------------
        (_amoAccountingFinals[2], _amoAccountingNets[1]) = finalAMOSnapshot(_amoAccountingFinals[1]);
        (_amoPoolAccountingFinals[2], _amoPoolAccountingNets[1]) = finalPoolSnapshot(_amoPoolAccountingFinals[1]);

        // Assert AMO Accounting Deltas
        assertApproxEqRel(
            _amoAccountingNets[1].frxETHInContract,
            25e18,
            HALF_PCT_DELTA,
            "AMO Accounting 2: frxETHInContract"
        );
        assertApproxEqRel(
            _amoAccountingNets[1].ethInContract,
            25e18,
            HALF_PCT_DELTA,
            "AMO Accounting 2: ethInContract"
        );
        assertApproxEqRel(_amoPoolAccountingNets[1].lpDeposited, 50e18, ONE_PCT_DELTA, "AMO Accounting 2: lpDeposited");

        // Check oneStep withdrawable
        // Check oneStep withdrawables [amo accounting]
        tmpNetSumBothFullOneStepWithdrawables =
            _amoAccountingNets[1].totalOneStepWithdrawableFrxETH +
            _amoAccountingNets[1].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            100e18,
            ONE_PCT_DELTA,
            "AMO Accounting 2: tmpNetSumBothFullOneStepWithdrawables"
        );

        // Check balanced withdrawables
        // Check balanced withdrawables [amo accounting]
        tmpNetTotalWithdrawableBothAsBalanced =
            _amoAccountingNets[1].totalBalancedWithdrawableFrxETH +
            _amoAccountingNets[1].totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            50e18,
            HALF_PCT_DELTA,
            "AMO Accounting 2: tmpNetTotalWithdrawableBothAsBalanced"
        );

        // Assert AMO Pool Accounting
        assertEq(
            _amoPoolAccountingNets[1].lpTotalAllForms,
            _amoPoolAccountingNets[1].lpDeposited,
            "AMO Pool Accounting 2: LP balance accounting"
        );
        assertGt(
            _amoPoolAccountingFinals[2].lpMaxAllocation,
            _amoPoolAccountingNets[1].lpDeposited,
            "AMO Pool Accounting 2: LP max allocation check"
        );

        assertApproxEqRel(
            _amoPoolAccountingNets[1].lpBalance,
            50e18,
            HALF_PCT_DELTA,
            "AMO Pool Accounting 2: lpBalance"
        );
        assertEq(_amoPoolAccountingNets[1].lpDepositedInVaults, 0, "AMO Pool Accounting 2: lpDepositedInVaults");

        // Check oneStep withdrawable [pool accounting]
        tmpNetSumBothFullOneStepWithdrawables =
            _amoPoolAccountingNets[1].totalOneStepWithdrawableFrxETH +
            _amoPoolAccountingNets[1].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            100e18,
            HALF_PCT_DELTA,
            "AMO Pool Accounting 2: tmpNetSumBothFullOneStepWithdrawables"
        );

        // Check balanced withdrawables [pool accounting]
        tmpNetTotalWithdrawableBothAsBalanced =
            _amoPoolAccountingNets[1].totalBalancedWithdrawableFrxETH +
            _amoPoolAccountingNets[1].totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            50e18,
            HALF_PCT_DELTA,
            "AMO Pool Accounting 2: tmpNetTotalWithdrawableBothAsBalanced"
        );

        // Action 3 - withdraw from pool with balanced ratio
        // -------------------------------------------------------------------------
        // -------------------------------------------------------------------------
        // Will revert to slippage minimums anyways
        tmpAmounts[0] = 0;
        tmpAmounts[1] = 0;

        // Do the withdrawal
        curveLsdAmo.withdrawBalanced(50e18, tmpAmounts);
        console.log("- frxETHWETH: withdraw from pool with balanced ratio");

        // Take snapshots
        (_amoAccountingFinals[3], _amoAccountingNets[2]) = finalAMOSnapshot(_amoAccountingFinals[2]);
        (_amoPoolAccountingFinals[3], _amoPoolAccountingNets[2]) = finalPoolSnapshot(_amoPoolAccountingFinals[2]);

        // Assert AMO Accounting Deltas
        assertApproxEqRel(
            _amoAccountingNets[2].frxETHInContract + _amoAccountingNets[2].ethInContract,
            50e18,
            HALF_PCT_DELTA,
            "AMO Accounting 3: frxETHInContract + ethInContract"
        );
        assertApproxEqRel(
            _amoPoolAccountingNets[2].lpDeposited,
            50e18,
            HALF_PCT_DELTA,
            "AMO Accounting 3: lpDeposited"
        );

        // Check oneStep withdrawable [amo accounting]
        tmpNetSumBothFullOneStepWithdrawables =
            _amoAccountingNets[2].totalOneStepWithdrawableFrxETH +
            _amoAccountingNets[2].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            100e18,
            HALF_PCT_DELTA,
            "AMO Accounting 3: tmpNetSumBothFullOneStepWithdrawables"
        );

        // Check balanced withdrawable [amo accounting]
        tmpNetTotalWithdrawableBothAsBalanced =
            _amoAccountingNets[2].totalBalancedWithdrawableFrxETH +
            _amoAccountingNets[2].totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            50e18,
            HALF_PCT_DELTA,
            "AMO Accounting 3: tmpNetTotalWithdrawableBothAsBalanced"
        );

        // Assert AMO Pool Accounting
        assertEq(
            _amoPoolAccountingNets[2].lpTotalAllForms,
            _amoPoolAccountingNets[2].lpDeposited,
            "AMO Pool Accounting 3: LP balance accounting"
        );
        assertGt(
            _amoPoolAccountingFinals[3].lpMaxAllocation,
            _amoPoolAccountingNets[2].lpDeposited,
            "AMO Pool Accounting 3: LP max allocation check"
        );

        assertApproxEqRel(
            _amoPoolAccountingNets[2].lpBalance,
            50e18,
            ONE_PCT_DELTA,
            "AMO Pool Accounting 3: lpBalance"
        );
        assertEq(_amoPoolAccountingNets[2].lpDepositedInVaults, 0, "AMO Pool Accounting 3: lpDepositedInVaults");

        // Check oneStep withdrawable [pool accounting]
        tmpNetSumBothFullOneStepWithdrawables =
            _amoPoolAccountingNets[2].totalOneStepWithdrawableFrxETH +
            _amoPoolAccountingNets[2].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            100e18,
            HALF_PCT_DELTA,
            "AMO Pool Accounting 3: tmpNetSumBothFullOneStepWithdrawables"
        );

        // Check balanced withdrawable [pool accounting]
        tmpNetTotalWithdrawableBothAsBalanced =
            _amoPoolAccountingNets[2].totalBalancedWithdrawableFrxETH +
            _amoPoolAccountingNets[2].totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            50e18,
            HALF_PCT_DELTA,
            "AMO Pool Accounting 3: tmpNetTotalWithdrawableBothAsBalanced"
        );

        // Action 4 - withdraw all coins from pool
        // -------------------------------------------------------------------------
        // Will revert to slippage minimums anyways
        tmpAmounts[0] = 0;
        tmpAmounts[1] = 0;

        // Withdraw all remaining coins as balanced
        uint256[2] memory _amountsReceived = curveLsdAmo.withdrawAll(tmpAmounts, false);
        console.log("- frxETHWETH: withdraw all coins from pool");

        // Take snapshots
        (_amoAccountingFinals[4], _amoAccountingNets[3]) = finalAMOSnapshot(_amoAccountingFinals[3]);
        (_amoPoolAccountingFinals[4], _amoPoolAccountingNets[3]) = finalPoolSnapshot(_amoPoolAccountingFinals[3]);

        // Assert AMO Accounting Deltas
        assertApproxEqRel(
            _amoAccountingNets[3].frxETHInContract + _amoAccountingNets[3].ethInContract,
            _amountsReceived[0] + _amountsReceived[1],
            HALF_PCT_DELTA,
            "AMO Accounting 4: frxETHInContract + ethInContract"
        );

        // Check oneStep withdrawable [amo accounting]
        tmpNetSumBothFullOneStepWithdrawables =
            _amoAccountingNets[3].totalOneStepWithdrawableFrxETH +
            _amoAccountingNets[3].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            (_amountsReceived[0] + _amountsReceived[1]) * 2,
            HALF_PCT_DELTA,
            "AMO Accounting 4: TotalOneStepWithdrawableETH"
        );

        // Check balanced withdrawable [amo accounting]
        tmpNetTotalWithdrawableBothAsBalanced =
            _amoAccountingNets[3].totalBalancedWithdrawableFrxETH +
            _amoAccountingNets[3].totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            _amountsReceived[0] + _amountsReceived[1],
            HALF_PCT_DELTA,
            "AMO Accounting 4: tmpNetTotalWithdrawableBothAsBalanced"
        );

        // Assert AMO Pool Accounting

        // Sum of value of free coins initially should match current sum of value of free coins
        // console.log("_amoPoolAccountingFinals sum [initial]: %s", _amoPoolAccountingFinals[0].freeCoinBalances[0] + _amoPoolAccountingFinals[0].freeCoinBalances[1]);
        // console.log("_amoPoolAccountingFinals sum [end]: %s", _amoPoolAccountingFinals[4].freeCoinBalances[0] + _amoPoolAccountingFinals[4].freeCoinBalances[1]);
        assertApproxEqRel(
            _amoPoolAccountingFinals[0].freeCoinBalances[0] + _amoPoolAccountingFinals[0].freeCoinBalances[1],
            _amoPoolAccountingFinals[4].freeCoinBalances[0] + _amoPoolAccountingFinals[4].freeCoinBalances[1],
            HALF_PCT_DELTA,
            "AMO Pool Accounting 4: freeCoinBalances accounting"
        );

        // Other checks
        assertGt(
            _amoPoolAccountingFinals[4].lpMaxAllocation,
            _amoPoolAccountingNets[3].lpDeposited,
            "AMO Pool Accounting 4: LP max allocation check"
        );

        assertApproxEqRel(
            _amoPoolAccountingNets[3].lpBalance,
            _amountsReceived[0] + _amountsReceived[1],
            HALF_PCT_DELTA,
            "AMO Pool Accounting 4: lpBalance"
        );
        assertEq(_amoPoolAccountingNets[3].lpDepositedInVaults, 0, "AMO Pool Accounting 4: lpDepositedInVaults");

        // Check oneStep withdrawable [pool accounting]
        tmpNetSumBothFullOneStepWithdrawables =
            _amoPoolAccountingNets[3].totalOneStepWithdrawableFrxETH +
            _amoPoolAccountingNets[3].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            (_amountsReceived[0] + _amountsReceived[1]) * 2,
            HALF_PCT_DELTA,
            "AMO Pool Accounting 4: totalOneStepWithdrawableETH"
        );

        // Check balanced withdrawable [pool accounting]
        tmpNetTotalWithdrawableBothAsBalanced =
            _amoPoolAccountingNets[3].totalBalancedWithdrawableFrxETH +
            _amoPoolAccountingNets[3].totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            (_amountsReceived[0] + _amountsReceived[1]),
            HALF_PCT_DELTA,
            "AMO Pool Accounting 4: totalBalancedWithdrawableETH"
        );
    }

    function testWithdrawalAccountingRoute1() public {
        detailedAccountingTestSetup();

        // Deposit funds to LP (oneCoin)
        // -------------------------------------------------------------------------
        console.log("- AllCurveLpCvxLpAndStkcvxLp: depositToCurveLP (WETH only)");
        (uint256 _lpOut, uint256 _nonEthUsed) = curveLsdAmo.depositToCurveLP(200e18, true);

        // Check deposited amounts
        // 1 LP is approx worth 1 ETH
        (, tmpLpDeposited, ) = amoHelper.showPoolAccounting(curveLsdAmoAddress);
        console.log("lpDeposited (1): ", tmpLpDeposited);
        assertEq(_nonEthUsed, 0, "testWithdrawalAccounting [A]: _nonEthUsed should be 0 for oneCoin deposit");
        assertApproxEqRel(
            tmpLpDeposited,
            200e18,
            HALF_PCT_DELTA,
            "testWithdrawalAccounting [A]: lpDeposited incorrect"
        );

        // Withdraw almost all LP balanced
        // -------------------------------------------------------------------------
        uint256[2] memory _minOuts;
        _minOuts[0] = 0;
        _minOuts[1] = 0;
        uint256 _lpToWithdraw = (_lpOut * (1e18 - 1e12)) / 1e18;
        tmpCoinsReceived = curveLsdAmo.withdrawBalanced(_lpToWithdraw, _minOuts);

        // Check deposited amounts
        (, tmpLpDeposited, ) = amoHelper.showPoolAccounting(curveLsdAmoAddress);
        console.log("lpDeposited (2): ", tmpLpDeposited);
        assertEq(_lpOut - _lpToWithdraw, tmpLpDeposited, "testWithdrawalAccounting [B1]: tmpLpDeposited incorrect");

        // Withdraw remaining LP crumbs
        // -------------------------------------------------------------------------
        tmpCoinsReceived = curveLsdAmo.withdrawBalanced(frxETHWETH_LP.balanceOf(curveLsdAmoAddress), _minOuts);
        // Check deposited amounts
        (, tmpLpDeposited, ) = amoHelper.showPoolAccounting(curveLsdAmoAddress);
        console.log("lpDeposited (3): ", tmpLpDeposited);

        // Should be 0 for both because you have zero lp now
        assertEq(0, tmpLpDeposited, "testWithdrawalAccounting [C]: tmpLpDeposited incorrect");
    }

    function testAllCurveLpCvxLpAndStkcvxLp() public {
        detailedAccountingTestSetup();

        // Take initial snapshots
        _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);

        // Action 1 - Deposit funds to LP (oneCoin)
        // -------------------------------------------------------------------------
        console.log("- AllCurveLpCvxLpAndStkcvxLp: depositToCurveLP (WETH only)");
        curveLsdAmo.depositToCurveLP(200e18, true);

        // Action 2 - Deposit 50 vanilla LP to cvxLP
        // -------------------------------------------------------------------------
        console.log("- AllCurveLpCvxLpAndStkcvxLp: depositToCvxLPVault");
        curveLsdAmo.depositToCvxLPVault(50e18);

        // Action 3 - Deposit 25 vanilla LP to stkcvxLP with various kek_ids
        // -------------------------------------------------------------------------
        console.log("- AllCurveLpCvxLpAndStkcvxLp: depositCurveLPToVaultedStkCvxLP (various kek_ids)");

        // Deposit into three different kek_ids, in two parts for the 0th kek_id
        bytes32[3] memory vault_kek_ids;
        vault_kek_ids[0] = curveLsdAmo.depositCurveLPToVaultedStkCvxLP(10e18, 0); // New kek_id
        curveLsdAmo.depositCurveLPToVaultedStkCvxLP(5e18, vault_kek_ids[0]); // Adds to the existing kek_id
        vault_kek_ids[1] = curveLsdAmo.depositCurveLPToVaultedStkCvxLP(7.5e18, 0); // New kek_id
        vault_kek_ids[2] = curveLsdAmo.depositCurveLPToVaultedStkCvxLP(2.5e18, 0); // New kek_id

        // Print some info
        {
            console.log("----------------");
            (, , tmpPoolAndVaultAllocations) = amoHelper.showPoolAccounting(curveLsdAmoAddress);

            tmpAllocations = amoHelper.showAllocations(curveLsdAmoAddress);
            console.log("Deposit Allocations [2]: Total frxETH deposited into Pools: ", tmpAllocations[2]);
            console.log("Deposit Allocations [3]: Total ETH + WETH deposited into Pools: ", tmpAllocations[3]);
            console.log("Deposit Allocations [4]: Total withdrawable frxETH from LPs as ONE COIN: ", tmpAllocations[4]);
            console.log("Deposit Allocations [5]: Total withdrawable ETH from LPs as ONE COIN: ", tmpAllocations[5]);
            console.log("Deposit Allocations [6]: Total withdrawable frxETH from LPs as BALANCED: ", tmpAllocations[6]);
            console.log("Deposit Allocations [7]: Total withdrawable ETH from LPs as BALANCED: ", tmpAllocations[7]);
        }

        // Check accounting for all above actions
        // -------------------------------------------------------------------------
        // Should have 125 LP (direct held), 50 cvxLP (vaulted), and 25 stkcvxLP (vaulted)

        // Print and check LP and vault balances
        {
            console.log("frxETHWETH_LP.balanceOf: ", frxETHWETH_LP.balanceOf(curveLsdAmoAddress));
            console.log("cvxfrxETHWETH_LP.balanceOf: ", cvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress));
            console.log("stkcvxfrxETHWETH_LP.balanceOf: ", stkcvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress));

            // Check LP balance
            assertApproxEqRel(
                tmpPoolAndVaultAllocations[0],
                125e18,
                HALF_PCT_DELTA,
                "tmpPoolAndVaultAllocations [A]: LP balance"
            );

            // Check cvxLP free balance (should be zero)
            assertApproxEqRel(
                cvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress),
                0,
                HALF_PCT_DELTA,
                "tmpPoolAndVaultAllocations [A]: cvxLP free balance"
            );

            // Check cvxLP vaulted balance
            assertApproxEqRel(
                tmpPoolAndVaultAllocations[1],
                50e18,
                HALF_PCT_DELTA,
                "tmpPoolAndVaultAllocations [A]: cvxLP vaulted balance"
            );

            // Check stkcvxLP free balance
            assertApproxEqRel(
                stkcvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress),
                0,
                HALF_PCT_DELTA,
                "tmpPoolAndVaultAllocations [A]: stkcvxLP free balance"
            );

            // Check stkcvxLP vaulted balance
            assertApproxEqRel(
                tmpPoolAndVaultAllocations[2],
                25e18,
                HALF_PCT_DELTA,
                "tmpPoolAndVaultAllocations [A]: stkcvxLP vaulted balance"
            );
        }

        /// Take deltas after deposits
        // -----------------------------------------
        (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
        (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);

        // console.log("lpBalance delta:", _netAmoPoolAccounting0.lpBalance);

        // Assert AMO Accounting for deltas
        assertEq(_amoAccountingNets[0].frxETHInContract, 0, "AMO Accounting [0]: frxETHInContract");
        assertEq(_amoAccountingNets[0].ethInContract, 200e18, "AMO Accounting [0]: ethInContract");
        assertApproxEqRel(
            _amoPoolAccountingNets[0].lpDeposited,
            200e18,
            HALF_PCT_DELTA,
            "AMO Accounting [0]: lpDeposited"
        );

        // Check the sum of oneStep withdrawables [amo accounting]
        tmpNetSumBothFullOneStepWithdrawables =
            _amoAccountingNets[0].totalOneStepWithdrawableFrxETH +
            _amoAccountingNets[0].totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            400e18, // 2x here because each one step gives 200e18 because you have ~200e18 LP and you are adding both
            HALF_PCT_DELTA,
            "AMO Accounting [0]: tmpNetSumBothFullOneStepWithdrawables"
        );

        // Check the sum of balanced withdrawables [amo accounting]
        tmpNetTotalWithdrawableBothAsBalanced =
            _amoAccountingNets[0].totalBalancedWithdrawableFrxETH +
            _amoAccountingNets[0].totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            200e18,
            HALF_PCT_DELTA,
            "AMO Accounting [0]: tmpNetTotalWithdrawableBothAsBalanced"
        );

        // Assert AMO Pool Accounting
        // LP balances & deposits
        assertEq(
            _amoPoolAccountingNets[0].lpTotalAllForms,
            _amoPoolAccountingNets[0].lpDeposited,
            "AMO Pool Accounting [0]: LP balance accounting"
        );
        assertGt(
            _amoPoolAccountingFinals[1].lpMaxAllocation,
            _amoPoolAccountingNets[0].lpDeposited,
            "AMO Pool Accounting [0]: LP max allocation check"
        );

        // Check lp and vaulted lp balances
        assertApproxEqRel(
            _amoPoolAccountingNets[0].lpBalance,
            125e18,
            HALF_PCT_DELTA,
            "AMO Pool Accounting [0]: lpBalance"
        );
        assertEq(_amoPoolAccountingNets[0].lpInCvxBooster, 50e18, "AMO Pool Accounting [0]: lpInCvxBooster");
        assertEq(_amoPoolAccountingNets[0].lpInStkCvxFarm, 25e18, "AMO Pool Accounting [0]: lpInStkCvxFarm");
        assertEq(_amoPoolAccountingNets[0].lpDepositedInVaults, 75e18, "AMO Pool Accounting [0]: lpDepositedInVaults");

        // Check the sum of oneStep withdrawables [pool accounting]
        assertApproxEqRel(
            _amoPoolAccountingNets[0].totalOneStepWithdrawableFrxETH +
                _amoPoolAccountingNets[0].totalOneStepWithdrawableETH,
            400e18,
            ONE_PCT_DELTA,
            "AMO Pool Accounting [0]: totalOneStepWithdrawableETH"
        );

        // Check the sum of balanced withdrawables [pool accounting]
        assertApproxEqRel(
            _amoPoolAccountingNets[0].totalBalancedWithdrawableFrxETH +
                _amoPoolAccountingNets[0].totalBalancedWithdrawableETH,
            200e18,
            ONE_PCT_DELTA,
            "AMO Pool Accounting [0]: totalBalancedWithdrawableETH"
        );

        // Action 4 - Do various coin and LP withdrawals and check balances afterwards.
        // Should have a mix of all coins and LP types afterwards
        // -------------------------------------------------------------------------

        // Wait until after the stake unlocks
        mineBlocksBySecond(8 days);

        // Withdraw 2 LP worth (balanced)
        console.log("- AllCurveLpCvxLpAndStkcvxLp: withdrawBalanced");
        {
            uint256[2] memory _minOuts;
            _minOuts[0] = 0;
            _minOuts[1] = 0;
            tmpCoinsReceived = curveLsdAmo.withdrawBalanced(2e18, _minOuts); // [-2 LP]
        }

        // Withdraw 1 ETH and 1 frxETH each, with oneCoin
        console.log("- AllCurveLpCvxLpAndStkcvxLp: withdrawOneCoins");
        curveLsdAmo.withdrawOneCoin(1e18, 0, 0); // ETH [-1 LP]
        curveLsdAmo.withdrawOneCoin(1e18, 1, 0); // frxETH [-1 LP]
        tmpCoinsReceived[0] += 1e18;
        tmpCoinsReceived[1] += 1e18;

        // Withdraw some cvxLP
        curveLsdAmo.withdrawAndUnwrapVaultedCvxLP(1.5e18, true); // [1.5 LP unwrapped, 0 net change]

        // Withdraw LP from one of the kek_ids
        console.log("- AllCurveLpCvxLpAndStkcvxLp: withdrawAndUnwrapFromFxsVault");
        curveLsdAmo.withdrawAndUnwrapFromFxsVault(vault_kek_ids[1], true); // [7.5 LP unwrapped, 0 net change]

        // Check accounting for all above actions
        // -------------------------------------------------------------------------

        // Print some info
        {
            console.log("----------------");
            console.log("tmpCoinsReceived[0] (WETH): ", tmpCoinsReceived[0]);
            console.log("tmpCoinsReceived[1] (frxETH): ", tmpCoinsReceived[1]);

            console.log("----------------");
            console.log("frxETHWETH_LP.balanceOf: ", frxETHWETH_LP.balanceOf(curveLsdAmoAddress));
            console.log("cvxfrxETHWETH_LP.balanceOf: ", cvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress));
            console.log("stkcvxfrxETHWETH_LP.balanceOf: ", stkcvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress));

            console.log("----------------");
            (, , tmpPoolAndVaultAllocations) = amoHelper.showPoolAccounting(curveLsdAmoAddress);

            tmpAllocations = amoHelper.showAllocations(curveLsdAmoAddress);
            console.log("First Withdrawal Allocations [2]: Total frxETH deposited into Pools: ", tmpAllocations[2]);
            console.log("First Withdrawal Allocations [3]: Total ETH + WETH deposited into Pools: ", tmpAllocations[3]);
            console.log(
                "First Withdrawal Allocations [4]: Total withdrawable frxETH from LPs as ONE COIN: ",
                tmpAllocations[4]
            );
            console.log(
                "First Withdrawal Allocations [5]: Total withdrawable ETH from LPs as ONE COIN: ",
                tmpAllocations[5]
            );
            console.log(
                "First Withdrawal Allocations [6]: Total withdrawable frxETH from LPs as BALANCED: ",
                tmpAllocations[6]
            );
            console.log(
                "First Withdrawal Allocations [7]: Total withdrawable ETH from LPs as BALANCED: ",
                tmpAllocations[7]
            );
        }

        // Check accounting for all above actions
        // -------------------------------------------------------------------------
        // Should have 130 LP (direct held), 48.5 cvxLP (vaulted), and 17.5 stkcvxLP (vaulted)

        // Print and check LP and vault balances
        {
            // Check LP balance
            assertApproxEqRel(
                tmpPoolAndVaultAllocations[0],
                125e18 + 5e18,
                HALF_PCT_DELTA,
                "tmpPoolAndVaultAllocations [B]: LP balance"
            );

            // Check cvxLP free balance (should be zero)
            assertApproxEqRel(
                cvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress),
                0,
                HALF_PCT_DELTA,
                "tmpPoolAndVaultAllocations [B]: cvxLP free balance"
            );

            // Check cvxLP vaulted balance
            assertApproxEqRel(
                tmpPoolAndVaultAllocations[1],
                48.5e18,
                HALF_PCT_DELTA,
                "tmpPoolAndVaultAllocations [B]: cvxLP vaulted balance"
            );

            // Check stkcvxLP free balance
            assertApproxEqRel(
                stkcvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress),
                0,
                HALF_PCT_DELTA,
                "tmpPoolAndVaultAllocations [B]: stkcvxLP free balance"
            );

            // Check stkcvxLP vaulted balance
            assertApproxEqRel(
                tmpPoolAndVaultAllocations[2],
                17.5e18,
                HALF_PCT_DELTA,
                "tmpPoolAndVaultAllocations [B]: stkcvxLP vaulted balance"
            );
        }

        // Take deltas after mini withdrawals
        // -----------------------------------------
        (_amoAccountingFinals[2], _amoAccountingNets[1]) = finalAMOSnapshot(_amoAccountingFinals[1]);
        (_amoPoolAccountingFinals[2], _amoPoolAccountingNets[1]) = finalPoolSnapshot(_amoPoolAccountingFinals[1]);

        // Assert AMO Accounting Deltas
        assertApproxEqRel(
            _amoAccountingNets[1].ethInContract,
            tmpCoinsReceived[0],
            HALF_PCT_DELTA,
            "AMO Accounting [1]: ethInContract"
        );
        assertApproxEqRel(
            _amoAccountingNets[1].frxETHInContract,
            tmpCoinsReceived[1],
            HALF_PCT_DELTA,
            "AMO Accounting [1]: frxETHInContract"
        );
        assertApproxEqRel(
            _amoPoolAccountingNets[1].lpDeposited,
            4e18,
            HALF_PCT_DELTA,
            "AMO Accounting [1]: lpDeposited"
        );

        // // Double here because two one-steps are being added
        // tmpNetSumBothFullOneStepWithdrawables =
        //     _amoAccountingNets[1].totalOneStepWithdrawableFrxETH +
        //     _amoAccountingNets[1].totalOneStepWithdrawableETH;
        // assertApproxEqRel(
        //     tmpNetSumBothFullOneStepWithdrawables,
        //     8e18,
        //     HALF_PCT_DELTA,
        //     "AMO Accounting [1]: tmpNetSumBothFullOneStepWithdrawables"
        // );

        // tmpNetTotalWithdrawableBothAsBalanced =
        //     _amoAccountingNets[1].totalBalancedWithdrawableFrxETH +
        //     _amoAccountingNets[1].totalBalancedWithdrawableETH;
        // assertApproxEqRel(
        //     tmpNetTotalWithdrawableBothAsBalanced,
        //     4e18,
        //     HALF_PCT_DELTA,
        //     "AMO Accounting [1]: tmpNetTotalWithdrawableBothAsBalanced"
        // );

        // // Shouldn't have moved much. Difference due to pool imbalance & slippage
        // assertApproxEqRel(
        //     _netAmoAccounting1.totalFrxETH,
        //     _netAmoAccounting1.totalETH,
        //     ONE_PCT_DELTA,
        //     "AMO Accounting [1]: totalFrxETH and totalETH [B]"
        // );

        // // Assert AMO Pool Accounting
        // for (uint256 i = 0; i < _netAmoPoolAccounting1.coinCount; i++) {
        //     assertEq(
        //         _netAmoPoolAccounting1.freeCoinBalances[i],
        //         _netAmoPoolAccounting1.coinsDeposited[i],
        //         "AMO Pool Accounting [1]: token balance accounting"
        //     );
        //     assertGt(
        //         _AmoPoolAccountingPostPartialWithdrawals.coinsMaxAllocation[i],
        //         _netAmoPoolAccounting1.coinsDeposited[i],
        //         "AMO Pool Accounting [1]: pool max allocation check"
        //     );
        // }

        // assertApproxEqRel(
        //     _netAmoPoolAccounting1.lpBalance,
        //     3.5e18,
        //     ONE_PCT_DELTA,
        //     "AMO Pool Accounting [1]: lpBalance"
        // );
        // assertEq(_netAmoPoolAccounting1.lpDepositedInVaults, 7.5e18, "AMO Pool Accounting [1]: lpDepositedInVaults");

        // // Double here because two one-steps are being added
        // // 4 LP was converted to coins, 7.5 LP was moved from stkcvxLP to LP. Even though the net LP balanceOf change was -3.5 LP
        // // 4 LP was unwound, so use 4 x 2 = 8 here
        // _netTotalOneStepWithdrawableComboETH =
        //     _netAmoPoolAccounting1.totalOneStepWithdrawableFrxETH +
        //     _netAmoPoolAccounting1.totalOneStepWithdrawableETH;
        // assertApproxEqRel(
        //     _netTotalOneStepWithdrawableComboETH,
        //     8e18,
        //     ONE_PCT_DELTA,
        //     "AMO Pool Accounting [1]: totalOneStepWithdrawableETH"
        // );

        // _netTotalBalancedWithdrawableComboETH =
        //     _netAmoPoolAccounting1.totalBalancedWithdrawableFrxETH +
        //     _netAmoPoolAccounting1.totalBalancedWithdrawableETH;
        // assertApproxEqRel(
        //     _netTotalBalancedWithdrawableComboETH,
        //     4e18,
        //     ONE_PCT_DELTA,
        //     "AMO Pool Accounting [1]: totalBalancedWithdrawableETH"
        // );

        // // Action 4 - Exit everything into ETH and frxETH
        // // -------------------------------------------------------------------------

        // // Unstake all the stkcvxLP
        // console.log("- AllCurveLpCvxLpAndStkcvxLp: withdrawAndUnwrapFromFxsVault [2]");
        // {
        //     curveLsdAmo.withdrawAndUnwrapFromFxsVault(address(frxETHWETH_Pool), vault_kek_ids[0], true);
        //     curveLsdAmo.withdrawAndUnwrapFromFxsVault(address(frxETHWETH_Pool), vault_kek_ids[2], true);
        // }

        // // Unwrap the cvxLP
        // console.log("- AllCurveLpCvxLpAndStkcvxLp: withdrawAndUnwrapVaultedCvxLP [2]");
        // {
        //     (uint256 cvxLPInVault, , ) = amoHelper.lpInVaults(address(frxETHWETH_Pool));
        //     curveLsdAmo.withdrawAndUnwrapVaultedCvxLP(address(frxETHWETH_Pool), cvxLPInVault, true);
        // }

        // // Withdraw vanilla LP
        // console.log("- AllCurveLpCvxLpAndStkcvxLp: withdrawAll [2]");
        // {
        //     uint256[2] memory _minOuts;
        //     _minOuts[0] = 35e18;
        //     _minOuts[1] = 35e18;
        //     curveLsdAmo.withdrawAll(address(frxETHWETH_Pool), _minOuts);
        // }

        // // Check to make sure the accounting is correct
        // {
        //     console.log("----------------");
        //     console.log("frxETHWETH_LP.balanceOf: ", frxETHWETH_LP.balanceOf(curveLsdAmoAddress));
        //     console.log("cvxfrxETHWETH_LP.balanceOf: ", cvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress));
        //     console.log("stkcvxfrxETHWETH_LP.balanceOf: ", stkcvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress));

        //     uint256[10] memory allocations = amoHelper.showAllocations(curveLsdAmoAddress);
        //     console.log("Final Allocations [2]: Total frxETH deposited into Pools: ", allocations[2]);
        //     console.log("Final Allocations [3]: Total ETH + WETH deposited into Pools: ", allocations[3]);
        //     console.log("Final Allocations [4]: Total withdrawable frxETH from LPs as ONE COIN: ", allocations[4]);
        //     console.log("Final Allocations [5]: Total withdrawable ETH from LPs as ONE COIN: ", allocations[5]);
        //     console.log("Final Allocations [6]: Total withdrawable frxETH from LPs as BALANCED: ", allocations[6]);
        //     console.log("Final Allocations [7]: Total withdrawable ETH from LPs as BALANCED: ", allocations[7]);
        //     assertEq(allocations[2], 0, "Final Allocations [2]: Total frxETH deposited into Pools");
        //     assertEq(allocations[3], 0, "Final Allocations [3]: Total ETH + WETH deposited into Pools");
        //     assertEq(allocations[4], 0, "Final Allocations [4]: Total withdrawable frxETH from LPs as ONE COIN");
        //     assertEq(allocations[5], 0, "Final Allocations [5]: Total withdrawable ETH from LPs as ONE COIN");
        //     assertEq(allocations[6], 0, "Final Allocations [6]: Total withdrawable frxETH from LPs as BALANCED");
        //     assertEq(allocations[7], 0, "Final Allocations [7]: Total withdrawable ETH from LPs as BALANCED");
        // }
    }
}
