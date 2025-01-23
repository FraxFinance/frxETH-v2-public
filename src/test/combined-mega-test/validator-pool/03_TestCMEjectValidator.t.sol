// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./02_TestCMDeposit.t.sol";

contract TestCMEjectValidator is CombinedMegaBaseTest, depositValidatorFunctions {
    using LendingPoolStructHelper for LendingPool;
    using RedemptionQueueStructHelper for FraxEtherRedemptionQueueV2;

    /// FEATURE: Users can eject validators and collect ether

    function setUp() public {
        /// BACKGROUND: All base contracts have been deployed and configured
        _defaultSetup();

        // Give the validator pool owner 96 ETH
        vm.deal(validatorPoolOwner, 96 ether);

        /// BACKGROUND: a validator pool has been properly deployed
        /// BACKGROUND: a validator has been properly deposited with 32 ether and no borrowed ether
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0]
        });

        // Change to the operator so you can trigger the sweep
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);

        // First set the Ether Router balance to 20 ether.
        // Sweep 10 ETH to the Redemption Queue and/or Curve AMO(s), leave 10 ETH in the EtherRouter, drop 5 ETH into the Curve AMO
        // This is to simulate mixed ETH in various places and force LP unwinding at the Curve AMO
        vm.deal(etherRouterAddress, 20 ether);
        etherRouter.sweepEther(10 ether, true); // Put in LP
        vm.deal(curveLsdAmoAddress, 5 ether);
        vm.stopPrank();
    }

    function test_EjectValidatorFlow() public {
        /// Take initial snapshots
        // -----------------------------------------
        ValidatorDepositInfoSnapshot memory _initialValidatorDepositInfo = validatorDepositInfoSnapshot(
            validatorPublicKeys[0],
            lendingPool
        );
        ValidatorPoolAccountingSnapshot
            memory _initialValidatorPoolAccountingSnapshot = validatorPoolAccountingSnapshot(validatorPool);
        AmoAccounting memory _AmoAccountingS0 = initialAmoSnapshot(curveLsdAmoAddress);
        AmoPoolAccounting memory _AmoPoolAccountingS0 = initialPoolSnapshot(curveLsdAmoAddress);
        InitialSystemSnapshot memory _initialSystemSnapshot = initialSystemSnapshot(
            validatorPoolOwner,
            bytes(""),
            lendingPool,
            validatorPool
        );
        // -----------------------------------------

        /// GIVEN the validator has deposited 2 additional, 3 total validators
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[1],
            _validatorSignature: validatorSignatures[1]
        });
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[2],
            _validatorSignature: validatorSignatures[2]
        });

        /// GIVEN the beacon oracle has verified the deposits
        _beaconOracle_setValidatorApproval(validatorPublicKeys[1], validatorPoolAddress, uint32(block.timestamp));
        _beaconOracle_setValidatorApproval(validatorPublicKeys[2], validatorPoolAddress, uint32(block.timestamp));

        /// GIVEN the beacon oracle has updated the count and allowance
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 3);
        _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);

        /// GIVEN the borrower has borrowed 20E and sent it to the validator pool owner
        uint256 borrowAmount = 20 ether;
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(validatorPoolOwner, borrowAmount);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        printAndReturnSystemStateInfo("======== AFTER BORROW ========", true);

        /// Take deltas after the deposits and borrowing
        // -----------------------------------------
        (AmoAccounting memory _AmoAccountingS1, AmoAccounting memory _netAmoAccounting) = finalAMOSnapshot(
            _AmoAccountingS0
        );
        (
            AmoPoolAccounting memory _AmoPoolAccountingS1,
            AmoPoolAccounting memory _netAmoPoolAccounting
        ) = finalPoolSnapshot(_AmoPoolAccountingS0);
        DeltaValidatorDepositInfoSnapshot memory _firstDeltaValidatorDepositInfo = deltaValidatorDepositInfoSnapshot(
            _initialValidatorDepositInfo
        );
        DeltaValidatorPoolAccountingSnapshot
            memory _firstDeltaValidatorPoolAccountingSnapshot = deltaValidatorPoolAccountingSnapshot(
                _initialValidatorPoolAccountingSnapshot
            );
        DeltaSystemSnapshot memory _firstDeltaSystemSnapshot = deltaSystemSnapshot(_initialSystemSnapshot);
        // -----------------------------------------

        // THEN the Curve AMO should have ~5 ether remaining
        assertApproxEqRel(_AmoAccountingS1.totalETH, 5e18, ONE_PCT_DELTA, "AMO Accounting: totalETH [A]");

        mineBlocks(10_000);

        /// GIVEN validator pool has earned 10E since the borrow
        vm.deal(validatorPoolAddress, validatorPoolAddress.balance + 10 ether);

        /// GIVEN the validator pool has ejected the validator
        vm.deal(validatorPoolAddress, validatorPoolAddress.balance + 32 ether);

        /// GIVEN the validator pool has paid of all debt
        lendingPool.addInterest(false);
        uint256 _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
        vm.prank(validatorPoolOwner);
        validatorPool.repayShares(_borrowShares);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // WHEN the validatorPool calls withdraw on the remaining balance
        hoax(validatorPoolOwner);
        validatorPool.withdraw(validatorPoolOwner, validatorPoolAddress.balance);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// Take deltas after the repay and withdrawal
        // -----------------------------------------
        (AmoAccounting memory _AmoAccountingS2, AmoAccounting memory _netAmoAccounting1) = finalAMOSnapshot(
            _AmoAccountingS1
        );
        _netAmoAccounting = _netAmoAccounting1;
        (
            AmoPoolAccounting memory _AmoPoolAccountingS2,
            AmoPoolAccounting memory _netAmoPoolAccounting1
        ) = finalPoolSnapshot(_AmoPoolAccountingS1);
        _netAmoPoolAccounting = _netAmoPoolAccounting1;
        DeltaValidatorDepositInfoSnapshot memory _secondDeltaValidatorDepositInfo = deltaValidatorDepositInfoSnapshot(
            _firstDeltaValidatorDepositInfo.start
        );
        DeltaValidatorPoolAccountingSnapshot
            memory _secondDeltaValidatorPoolAccountingSnapshot = deltaValidatorPoolAccountingSnapshot(
                _firstDeltaValidatorPoolAccountingSnapshot.start
            );
        DeltaSystemSnapshot memory _secondDeltaSystemSnapshot = deltaSystemSnapshot(_firstDeltaSystemSnapshot.end);
        // -----------------------------------------

        //THEN check LP, cvxLP, and stkcvxLP balances
        {
            // frxETH/ETH
            assertEq(frxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: frxETHETH_LP balance");
            assertEq(cvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: cvxfrxETHETH_LP balance");
            assertEq(stkcvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: stkcvxfrxETHETH_LP balance");

            // frxETH/WETH
            assertEq(frxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: frxETHWETH_LP balance");
            assertEq(cvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: cvxfrxETHWETH_LP balance");
            assertEq(stkcvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: stkcvxfrxETHWETH_LP balance");

            // ankrETH/ETH
            assertEq(ankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: ankrETHfrxETH_LP balance");
            assertEq(cvxankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: cvxankrETHfrxETH_LP balance");
            assertEq(stkcvxankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: stkcvxankrETHfrxETH_LP balance");

            // stETH/ETH
            assertEq(stETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: stETHfrxETH_LP balance");
            assertEq(cvxstETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: cvxstETHfrxETH_LP balance");
            assertEq(stkcvxstETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ARW]: stkcvxstETHfrxETH_LP balance");
        }

        // THEN the EtherRouter should have some extra ETH (above 20 ETH) earned from interest + the withdrawal fee
        assertApproxEqAbs(etherRouterAddress.balance, 20.15e18, 0.1e18, "[ARW]: etherRouterAddress ETH balance");

        // THEN the Curve AMO should have 0 ether remaining
        assertEq(_netAmoAccounting1.totalETH, 0, "AMO Accounting: totalETH [B]");
        assertEq(_netAmoAccounting1.totalOneStepWithdrawableETH, 0, "AMO Accounting: totalOneStepWithdrawableETH [B]");
    }
}
