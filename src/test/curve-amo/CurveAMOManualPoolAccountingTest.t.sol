// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./CurveAmoBaseTest.t.sol";

contract CurveAMOManualAccountingTest is CurveAmoBaseTest {
    // For determining expected ratios
    uint256 public frxETHWETH_LPPerETH;
    uint256 public frxETHWETH_LPPerfrxETH;

    // Temporary. Prevents stack too deep errors
    uint256[2] public tmpAmounts;
    uint256 tmpNetSumBothFullOneStepWithdrawables;
    uint256 tmpNetTotalWithdrawableBothAsBalanced;
    uint256 tmpNetTotalWithdrawableETH;

    function manualAccountingTestSetup() public {
        defaultSetup();
        vm.stopPrank();

        // Give 10000 WETH to the AMO (from a WETH whale)
        startHoax(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        WETH.transfer(curveLsdAmoAddress, 10_000e18);

        // Switch back to the timelock
        vm.startPrank(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);

        // Setup the frxETH/WETH farm
        setupFrxETHWETHInAmo(0);

        vm.stopPrank();

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

        // Switch back to the timelock
        vm.startPrank(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
    }

    function testManualPoolAccounting() public {
        manualAccountingTestSetup();

        // DEPOSIT TO THE POOL
        // ============================================
        AmoAccounting memory _AmoAccountingS0 = initialAmoSnapshot(curveLsdAmoAddress);
        AmoPoolAccounting memory _AmoPoolAccountingS0 = initialPoolSnapshot(curveLsdAmoAddress);
        amoHelper.showPoolFreeCoinBalances(curveLsdAmoAddress); // For stack traces

        // Do the deposit
        // Input here is ETH amount, not LP amount
        (uint256 _lpOutActual, uint256 _frxETHUsed) = curveLsdAmo.depositToCurveLP(200e18, false);
        console.log("- frxETHWETH: deposit (frxETH and ETH)");
        (AmoAccounting memory _AmoAccountingS1, AmoAccounting memory _netAmoAccounting) = finalAMOSnapshot(
            _AmoAccountingS0
        );
        (
            AmoPoolAccounting memory _AmoPoolAccountingS1,
            AmoPoolAccounting memory _netAmoPoolAccounting
        ) = finalPoolSnapshot(_AmoPoolAccountingS0);

        // Assert AMO Accounting
        assertEq(_netAmoAccounting.frxETHInContract, _frxETHUsed, "AMO Accounting: frxETHInContract");
        assertEq(_netAmoAccounting.ethInContract, 200e18, "AMO Accounting: ethInContract");
        assertEq(_netAmoPoolAccounting.lpDeposited, _lpOutActual, "AMO Accounting: lpDeposited");

        // Sum if you pulled out all ETH and all frxETH in 2 different transactions
        tmpNetSumBothFullOneStepWithdrawables =
            _netAmoAccounting.totalOneStepWithdrawableFrxETH +
            _netAmoAccounting.totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            2 * _lpOutActual, // Since this particular LP is basically 1:1
            HALF_PCT_DELTA,
            "AMO Accounting: TotalSumBothFullOneStepWithdrawables"
        );

        // Sum if you pulled out balanced ETH and frxETH in one transaction
        tmpNetTotalWithdrawableBothAsBalanced =
            _netAmoAccounting.totalBalancedWithdrawableFrxETH +
            _netAmoAccounting.totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            _lpOutActual,
            HALF_PCT_DELTA,
            "AMO Accounting: TotalWithdrawableBothAsBalanced [A]"
        );

        // assertEq(_netAmoAccounting.mintedBalanceFRAX, 0, "AMO Accounting: mintedBalanceFRAX");

        // Assert AMO Pool Accounting
        amoHelper.showPoolFreeCoinBalances(curveLsdAmoAddress); // For stack traces
        console.log("lpTotalAllForms [_AmoPoolAccountingS0]: %s", _AmoPoolAccountingS0.lpTotalAllForms);
        console.log("lpTotalAllForms [_AmoPoolAccountingS1]: %s", _AmoPoolAccountingS1.lpTotalAllForms);
        console.log("lpTotalAllForms [_netAmoPoolAccounting]: %s", _netAmoPoolAccounting.lpTotalAllForms);
        assertEq(
            _netAmoPoolAccounting.lpTotalAllForms,
            _netAmoPoolAccounting.lpDeposited,
            "AMO Pool Accounting: LP balance accounting"
        );
        assertGt(
            _AmoPoolAccountingS1.lpMaxAllocation,
            _netAmoPoolAccounting.lpDeposited,
            "AMO Pool Accounting: LP max allocation check"
        );
        assertApproxEqRel(
            _netAmoPoolAccounting.lpBalance,
            _lpOutActual,
            HALF_PCT_DELTA,
            "AMO Pool Accounting: lpBalance"
        );
        assertEq(_netAmoPoolAccounting.lpDepositedInVaults, 0, "AMO Pool Accounting: lpDepositedInVaults");

        tmpNetSumBothFullOneStepWithdrawables =
            _netAmoPoolAccounting.totalOneStepWithdrawableFrxETH +
            _netAmoPoolAccounting.totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            2 * _lpOutActual, // Since this particular LP is basically 1:1
            HALF_PCT_DELTA,
            "AMO Pool Accounting: sumBothFullOneStepWithdrawables"
        );

        tmpNetTotalWithdrawableBothAsBalanced =
            _netAmoPoolAccounting.totalBalancedWithdrawableFrxETH +
            _netAmoPoolAccounting.totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableBothAsBalanced,
            _lpOutActual,
            HALF_PCT_DELTA,
            "AMO Pool Accounting: totalWithdrawableBothAsBalanced"
        );

        // SET A MANUAL LP TRANSACTION (DEPOSIT)
        // ============================================

        // Do the deposit
        curveLsdAmo.setPoolManualLPTrans(50e18, true);
        console.log("- frxETHWETH: manual deposit registry");
        (AmoAccounting memory _AmoAccountingS2, AmoAccounting memory _netAmoAccounting1) = finalAMOSnapshot(
            _AmoAccountingS1
        );
        _netAmoAccounting = _netAmoAccounting1;
        (
            AmoPoolAccounting memory _AmoPoolAccountingS2,
            AmoPoolAccounting memory _netAmoPoolAccounting1
        ) = finalPoolSnapshot(_AmoPoolAccountingS1);
        _netAmoPoolAccounting = _netAmoPoolAccounting1;

        // Assert AMO Accounting
        assertEq(_netAmoAccounting.frxETHInContract, 0, "AMO Accounting: frxETHInContract [MANUAL DEPOSIT]");
        assertEq(_netAmoAccounting.ethInContract, 0, "AMO Accounting: ethInContract [MANUAL DEPOSIT]");
        assertEq(_netAmoPoolAccounting.lpDeposited, 50e18, "AMO Accounting: lpDeposited [MANUAL DEPOSIT]");

        // Should be 0 as no actual tokens were pooled
        tmpNetSumBothFullOneStepWithdrawables =
            _netAmoAccounting.totalOneStepWithdrawableFrxETH +
            _netAmoAccounting.totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            0,
            ONE_PCT_DELTA,
            "AMO Accounting: TotalSumBothFullOneStepWithdrawables [MANUAL DEPOSIT]"
        );

        // Should be 0 as no actual tokens were pooled
        tmpNetTotalWithdrawableETH =
            _netAmoAccounting.totalBalancedWithdrawableFrxETH +
            _netAmoAccounting.totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableETH,
            0,
            ONE_PCT_DELTA,
            "AMO Accounting: TotalWithdrawableETH [A] [MANUAL DEPOSIT]"
        );

        // Assert AMO Pool Accounting
        assertGt(
            _AmoPoolAccountingS1.lpMaxAllocation,
            _netAmoPoolAccounting.lpDeposited,
            "AMO Pool Accounting: LP max allocation check [MANUAL DEPOSIT]"
        );
        assertApproxEqRel(_netAmoPoolAccounting.lpBalance, 0, 25e14, "AMO Pool Accounting: lpBalance [MANUAL DEPOSIT]");
        assertEq(
            _netAmoPoolAccounting.lpDepositedInVaults,
            0,
            "AMO Pool Accounting: lpDepositedInVaults [MANUAL DEPOSIT]"
        );

        tmpNetSumBothFullOneStepWithdrawables =
            _netAmoPoolAccounting.totalOneStepWithdrawableFrxETH +
            _netAmoPoolAccounting.totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            0,
            25e14,
            "AMO Pool Accounting: totalOneStepWithdrawableETH [MANUAL DEPOSIT]"
        );

        tmpNetTotalWithdrawableETH =
            _netAmoPoolAccounting.totalBalancedWithdrawableFrxETH +
            _netAmoPoolAccounting.totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableETH,
            0,
            25e14,
            "AMO Pool Accounting: totalWithdrawableETH [MANUAL DEPOSIT]"
        );

        // SET A MANUAL LP TRANSACTION (WITHDRAWAL)
        // ============================================
        tmpAmounts[0] = 25e18;
        tmpAmounts[1] = 25e18;

        // Do the deposit
        curveLsdAmo.setPoolManualLPTrans(50e18, false);
        console.log("- frxETHWETH: manual withdrawal registry");
        (AmoAccounting memory _AmoAccountingFinal3, AmoAccounting memory _netAmoAccountingDelta2) = finalAMOSnapshot(
            _AmoAccountingS2
        );
        _netAmoAccounting = _netAmoAccountingDelta2;
        (
            AmoPoolAccounting memory _AmoPoolAccountingFinal3,
            AmoPoolAccounting memory _netAmoPoolAccountingDelta2
        ) = finalPoolSnapshot(_AmoPoolAccountingS2);
        _netAmoPoolAccounting = _netAmoPoolAccountingDelta2;

        // Assert AMO Accounting
        assertEq(_netAmoAccounting.frxETHInContract, 0, "AMO Accounting: frxETHInContract [MANUAL WITHDRAWAL]");
        assertEq(_netAmoAccounting.ethInContract, 0, "AMO Accounting: ethInContract [MANUAL WITHDRAWAL]");
        assertEq(_netAmoPoolAccounting.lpDeposited, 50e18, "AMO Accounting: lpDeposited [MANUAL WITHDRAWAL]");

        // Should be 0 as no actual tokens were pooled
        tmpNetSumBothFullOneStepWithdrawables =
            _netAmoAccounting.totalOneStepWithdrawableFrxETH +
            _netAmoAccounting.totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            0,
            ONE_PCT_DELTA,
            "AMO Accounting: TotalSumBothFullOneStepWithdrawables [MANUAL WITHDRAWAL]"
        );

        // Should be 0 as no actual tokens were pooled
        tmpNetTotalWithdrawableETH =
            _netAmoAccounting.totalBalancedWithdrawableFrxETH +
            _netAmoAccounting.totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableETH,
            0,
            ONE_PCT_DELTA,
            "AMO Accounting: TotalWithdrawableETH [A] [MANUAL WITHDRAWAL]"
        );

        // Assert AMO Pool Accounting
        assertGt(
            _AmoPoolAccountingS1.lpMaxAllocation,
            _netAmoPoolAccounting.lpDeposited,
            "AMO Pool Accounting: LP max allocation check [MANUAL WITHDRAWAL]"
        );
        assertApproxEqRel(
            _netAmoPoolAccounting.lpBalance,
            0,
            25e14,
            "AMO Pool Accounting: lpBalance [MANUAL WITHDRAWAL]"
        );

        assertEq(
            _netAmoPoolAccounting.lpDepositedInVaults,
            0,
            "AMO Pool Accounting: lpDepositedInVaults [MANUAL WITHDRAWAL]"
        );

        tmpNetSumBothFullOneStepWithdrawables =
            _netAmoPoolAccounting.totalOneStepWithdrawableFrxETH +
            _netAmoPoolAccounting.totalOneStepWithdrawableETH;
        assertApproxEqRel(
            tmpNetSumBothFullOneStepWithdrawables,
            0,
            25e14,
            "AMO Pool Accounting: totalOneStepWithdrawableETH [MANUAL WITHDRAWAL]"
        );

        tmpNetTotalWithdrawableETH =
            _netAmoPoolAccounting.totalBalancedWithdrawableFrxETH +
            _netAmoPoolAccounting.totalBalancedWithdrawableETH;
        assertApproxEqRel(
            tmpNetTotalWithdrawableETH,
            0,
            25e14,
            "AMO Pool Accounting: totalWithdrawableETH [MANUAL WITHDRAWAL]"
        );
    }
}
