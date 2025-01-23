// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./CurveAmoBaseTest.t.sol";

contract VaultInteractionTest is CurveAmoBaseTest {
    function vaultInteractionTestSetup() public {
        defaultSetup();

        vm.stopPrank();

        // Give 10000 WETH to the AMO (from a WETH whale)
        startHoax(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        WETH.transfer(curveLsdAmoAddress, 10_000e18);

        // Switch back to the timelock
        vm.startPrank(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);

        // Setup the frxETH/WETH farm
        setupFrxETHWETHInAmo(0);
    }

    // cvxLP
    function testConvexVault() public {
        vaultInteractionTestSetup();

        // Action 1 - Deposit funds to the pool (vanilla LP)
        curveLsdAmo.depositToCurveLP(100e18, false);
        console.log("- frxETHWETH: deposit (frxETH and WETH)");

        // Snapshot AFTER depositing the LP, as a baseline
        AmoAccounting memory _AmoAccountingS0 = initialAmoSnapshot(curveLsdAmoAddress);
        AmoPoolAccounting memory _AmoPoolAccountingS0 = initialPoolSnapshot(curveLsdAmoAddress);

        // Action 2 - Deposit to Convex Vault (cvxLP)
        curveLsdAmo.depositToCvxLPVault(195e18);
        console.log("- frxETHWETH: deposit LP into Convex Vault");
        (AmoAccounting memory _AmoAccountingS1, AmoAccounting memory _netAmoAccounting) = finalAMOSnapshot(
            _AmoAccountingS0
        );
        (
            AmoPoolAccounting memory _AmoPoolAccountingS1,
            AmoPoolAccounting memory _netAmoPoolAccounting
        ) = finalPoolSnapshot(_AmoPoolAccountingS0);
        assertApproxEqRel(_netAmoPoolAccounting.lpBalance, 195e18, ONE_PCT_DELTA, "AMO Pool Accounting: lpBalance");

        assertApproxEqRel(
            _netAmoPoolAccounting.lpDepositedInVaults,
            195e18,
            ONE_PCT_DELTA,
            "AMO Pool Accounting: lpDepositedInVaults"
        );

        // Action 3 - Wait and claim rewards
        // Wait for 1 hr
        skip(3600);
        console.log("- Wait for 1 hr, then claim");
        uint256 crvBefore = crvERC20.balanceOf(curveLsdAmoAddress);
        uint256 cvxBefore = cvxERC20.balanceOf(curveLsdAmoAddress);
        curveLsdAmo.claimRewards(true, false);
        assertGt(crvERC20.balanceOf(curveLsdAmoAddress), crvBefore, "CRV claimRewards [A]");
        assertGt(cvxERC20.balanceOf(curveLsdAmoAddress), cvxBefore, "CVX claimRewards [A]");
        console.log("- frxETHWETH: Claim rewards");

        // Wait 1 hr
        skip(3600);

        // Call the claim but actually claim nothing (code coverage branch)
        curveLsdAmo.claimRewards(false, false);

        // Wait 1 hr
        skip(3600);

        // Call the claim for both tokens
        curveLsdAmo.claimRewards(true, true);

        // Action 4 - Wait and withdraw + claim
        // Wait for 21 days
        skip(21 * 24 * 3600);
        console.log("- Wait for 21 more days, then withdraw with inline claim");

        crvBefore = crvERC20.balanceOf(curveLsdAmoAddress);
        cvxBefore = cvxERC20.balanceOf(curveLsdAmoAddress);
        curveLsdAmo.withdrawAndUnwrapVaultedCvxLP(195e18, true);
        console.log("- frxETHWETH: Withdraw LP from Convex Vault");
        (, AmoAccounting memory _netAmoAccounting1) = finalAMOSnapshot(_AmoAccountingS1);
        _netAmoAccounting = _netAmoAccounting1;
        (, AmoPoolAccounting memory _netAmoPoolAccounting1) = finalPoolSnapshot(_AmoPoolAccountingS1);
        _netAmoPoolAccounting = _netAmoPoolAccounting1;
        assertApproxEqRel(_netAmoPoolAccounting.lpBalance, 195e18, ONE_PCT_DELTA, "AMO Pool Accounting: lpBalance");
        assertApproxEqRel(
            _netAmoPoolAccounting.lpDepositedInVaults,
            195e18,
            ONE_PCT_DELTA,
            "AMO Pool Accounting: lpDepositedInVaults"
        );

        // NOTE: Small chance this can fail if you are forking near on a reward boundary period, because rewards are set on
        // a weekly basis and you are fast-forwarding past that
        assertGt(crvERC20.balanceOf(curveLsdAmoAddress), crvBefore, "CRV claimRewards [B]");
        assertGt(cvxERC20.balanceOf(curveLsdAmoAddress), cvxBefore, "CVX claimRewards [B]");
    }

    // stkcvxLP
    function testFXSPersonalVault() public {
        vaultInteractionTestSetup();

        // Action 1 - Deposit funds to the pool (vanilla LP)
        curveLsdAmo.depositToCurveLP(105e18, false);
        console.log("- frxETHWETH: deposit (frxETH and WETH)");

        AmoPoolAccounting memory _AmoPoolAccountingS0 = initialPoolSnapshot(curveLsdAmoAddress);

        // Action 3 - Deposit to FXS Personal Vault (Frax stkcvxfrxETHWETH farm)
        bytes32 _kek_id_1 = curveLsdAmo.depositCurveLPToVaultedStkCvxLP(100e18, bytes32(0));
        // fails in veFXSMultiplier
        console.log("- frxETHWETH: deposit LP into FXS Personal Vault and lock it for 7 days");
        bytes32 _kek_id_2 = curveLsdAmo.depositCurveLPToVaultedStkCvxLP(100e18, bytes32(0));
        console.log("- frxETHWETH: deposit LP into FXS Personal Vault and lock it for 7 days (again)");

        (
            AmoPoolAccounting memory _AmoPoolAccountingS1,
            AmoPoolAccounting memory _netAmoPoolAccounting
        ) = finalPoolSnapshot(_AmoPoolAccountingS0);
        assertApproxEqRel(_netAmoPoolAccounting.lpBalance, 200e18, ONE_PCT_DELTA, "AMO Pool Accounting: lpBalance");
        assertEq(_netAmoPoolAccounting.lpDepositedInVaults, 200e18, "AMO Pool Accounting: lpDepositedInVaults");

        // Wait for 1 hour
        skip(3600);
        console.log("- Wait for 1 hour");
        // Action 4 - Claim rewards
        uint256 fxsBefore = fxsERC20.balanceOf(curveLsdAmoAddress);
        uint256 crvBefore = crvERC20.balanceOf(curveLsdAmoAddress);
        uint256 cvxBefore = cvxERC20.balanceOf(curveLsdAmoAddress);
        curveLsdAmo.claimRewards(false, true);
        assertGt(fxsERC20.balanceOf(curveLsdAmoAddress), fxsBefore, "FXS claimRewards [A]");
        assertGt(crvERC20.balanceOf(curveLsdAmoAddress), crvBefore, "CRV claimRewards [A]");
        assertGt(cvxERC20.balanceOf(curveLsdAmoAddress), cvxBefore, "CVX claimRewards [A]");
        console.log("- frxETHWETH: Claim rewards");

        // Wait for 8 days
        skip(8 * 24 * 3600);
        console.log("- frxETHWETH: Wait 8 days for the first stake to expire (_kek_id_1)");

        // Action 5 - Withdraw from FXS Personal Vault. Do not claim
        curveLsdAmo.withdrawAndUnwrapFromFxsVault(_kek_id_1, false);
        console.log("- frxETHWETH: Withdraw LP from FXS Personal Vault after 8 days");
        (
            AmoPoolAccounting memory _AmoPoolAccountingS2,
            AmoPoolAccounting memory _netAmoPoolAccounting1
        ) = finalPoolSnapshot(_AmoPoolAccountingS1);
        _netAmoPoolAccounting = _netAmoPoolAccounting1;
        assertApproxEqAbs(_netAmoPoolAccounting.lpBalance, 100e18, 1e18, "AMO Pool Accounting: lpBalance");
        assertEq(_netAmoPoolAccounting.lpDepositedInVaults, 100e18, "AMO Pool Accounting: lpDepositedInVaults");

        // Action 6 - Lock more into one kek
        curveLsdAmo.depositCurveLPToVaultedStkCvxLP(100e18, _kek_id_2);
        console.log("- frxETHWETH: Lock more LP into the locked");

        (
            AmoPoolAccounting memory _AmoPoolAccountingS3,
            AmoPoolAccounting memory _netAmoPoolAccounting2
        ) = finalPoolSnapshot(_AmoPoolAccountingS2);
        _netAmoPoolAccounting = _netAmoPoolAccounting2;
        assertApproxEqAbs(_netAmoPoolAccounting.lpBalance, 100e18, 1e18, "AMO Pool Accounting: lpBalance");
        assertEq(_netAmoPoolAccounting.lpDepositedInVaults, 100e18, "AMO Pool Accounting: lpDepositedInVaults");

        // Wait for 180 days
        skip(180 * 24 * 3600);
        console.log("- Wait for 180 days");

        // Action 7 - Withdraw from FXS Personal Vault. Claim too
        fxsBefore = fxsERC20.balanceOf(curveLsdAmoAddress);
        crvBefore = crvERC20.balanceOf(curveLsdAmoAddress);
        cvxBefore = cvxERC20.balanceOf(curveLsdAmoAddress);
        curveLsdAmo.withdrawAndUnwrapFromFxsVault(_kek_id_2, true);
        console.log("- frxETHWETH: Withdraw LP from FXS Personal Vault after 180 days");
        (, AmoPoolAccounting memory _netAmoPoolAccounting3) = finalPoolSnapshot(_AmoPoolAccountingS3);
        _netAmoPoolAccounting = _netAmoPoolAccounting3;
        assertApproxEqAbs(_netAmoPoolAccounting.lpBalance, 200e18, 1e18, "AMO Pool Accounting: lpBalance");
        assertEq(_netAmoPoolAccounting.lpDepositedInVaults, 200e18, "AMO Pool Accounting: lpDepositedInVaults");
        assertGt(fxsERC20.balanceOf(curveLsdAmoAddress), fxsBefore, "FXS claimRewards [B]");
        assertGt(crvERC20.balanceOf(curveLsdAmoAddress), crvBefore, "CRV claimRewards [B]");
        assertGt(cvxERC20.balanceOf(curveLsdAmoAddress), cvxBefore, "CVX claimRewards [B]");
    }
}
