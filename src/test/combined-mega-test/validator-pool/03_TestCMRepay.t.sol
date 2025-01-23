// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./02_TestCMDeposit.t.sol";

contract TestCMRepay is CombinedMegaBaseTest, depositValidatorFunctions {
    using logSnapshot for *;

    /// FEATURE: User can repay debt

    function setUp() public {
        /// BACKGROUND: All base contracts have been deployed and configured
        _defaultSetup();

        /// BACKGROUND: a borrower has 1 validator deposited
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0]
        });

        /// BACKGROUND: Oracle has validated the signing message of the validator
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 1);

        /// BACKGROUND: Oracle has validated that no ether has already been borrowed
        _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);
    }

    function test_CMRepayFlow() public {
        // SCENARIO: successful repay flow
        /// GIVEN the borrower has borrowed 20E and sent it to the validator pool owner
        uint256 borrowAmount = 20 ether;
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(validatorPoolOwner, borrowAmount);

        mineBlocks(100);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// GIVEN validator pool has earned 10E since the borrow
        vm.deal(validatorPoolAddress, validatorPoolAddress.balance + 10 ether);

        /// Take initial snapshots
        // -----------------------------------------
        InitialSystemSnapshot memory _initialSystemSnapshot = initialSystemSnapshot(
            validatorPoolOwner,
            bytes(""),
            lendingPool,
            validatorPool
        );
        AmoAccounting memory _AmoAccountingS0 = initialAmoSnapshot(curveLsdAmoAddress);
        AmoPoolAccounting memory _AmoPoolAccountingS0 = initialPoolSnapshot(curveLsdAmoAddress);

        // WHEN random user funds from staking to repay 10E (should fail)
        vm.prank(testUserAddress);
        try validatorPool.repayWithPoolAndValue{ value: 0 }(10 ether) {
            revert("Should not have succeeded");
        } catch (bytes memory reason) {
            assertEq(ValidatorPool.SenderMustBeOwnerOrLendingPool.selector, bytes4(reason));
        }

        // WHEN owner uses funds from staking to repay 10E
        vm.prank(validatorPoolOwner);
        validatorPool.repayWithPoolAndValue{ value: 0 }(10 ether);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // WHEN Curve AMO operator triggers sweep of the deposited funds from the Ether Router to the Redemption Queue and/or Curve AMO(s)
        // vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        vm.prank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        etherRouter.sweepEther(10 ether, true);
        vm.prank(validatorPoolOwner);

        /// Take deltas after the repay and sweep
        // -----------------------------------------
        DeltaSystemSnapshot memory _firstDeltaSystemSnapshot = deltaSystemSnapshot(_initialSystemSnapshot);
        (AmoAccounting memory _AmoAccountingS1, AmoAccounting memory _netAmoAccounting) = finalAMOSnapshot(
            _AmoAccountingS0
        );
        (
            AmoPoolAccounting memory _AmoPoolAccountingS1,
            AmoPoolAccounting memory _netAmoPoolAccounting
        ) = finalPoolSnapshot(_AmoPoolAccountingS0);

        // THEN the Curve AMO should have an extra 10 ether
        assertApproxEqRel(_netAmoAccounting.totalETH, 10e18, ONE_PCT_DELTA, "AMO Accounting: totalETH [A]");

        /// THEN allowance should remain unchanged
        assertEq(
            _firstDeltaSystemSnapshot.start.validatorPool.lendingPool_validatorPoolAccount.borrowAllowance,
            _firstDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowAllowance,
            "When a validatorPool repays 10 ether, then: the borrow allowance should remain unchanged"
        );
        /// THEN Borrow amount should decrease by an amount equal to 10 ether
        assertApproxEqRel(
            lendingPool.toBorrowAmount(
                _firstDeltaSystemSnapshot.delta.validatorPool.lendingPool_validatorPoolAccount.borrowShares
            ),
            10 ether,
            1e15,
            "When a validatorPool repays 10 ether, then: the borrow shares should have changed to an amount that represents 10 ether"
        );
        assertLt(
            _firstDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowShares,
            _firstDeltaSystemSnapshot.start.validatorPool.lendingPool_validatorPoolAccount.borrowShares,
            "When a validatorPool repays 10 ether, then: the borrow shares should have decreased"
        );
        /// THEN ValidatorPool should have 10E less ether
        assertEq(
            _firstDeltaSystemSnapshot.delta.validatorPool.addressAccounting.etherBalance,
            10 ether,
            "When a validatorPool repays 10 ether, then: the ether balance should have changed by 10 ether"
        );
        assertLt(
            _firstDeltaSystemSnapshot.end.validatorPool.addressAccounting.etherBalance,
            _firstDeltaSystemSnapshot.start.validatorPool.addressAccounting.etherBalance,
            "When a validatorPool repays 10 ether, then: the ether balance should have decreased"
        );
        /// THEN LendingPool should have the same ether balance (because it is moved to the Curve AMO / EtherRouter?)
        assertEq(
            _firstDeltaSystemSnapshot.delta.lendingPool.addressAccounting.etherBalance,
            0,
            "When a validatorPool repays 10 ether, then: the ether balance should have changed by 0 ether"
        );
        assertEq(
            _firstDeltaSystemSnapshot.end.lendingPool.addressAccounting.etherBalance,
            _firstDeltaSystemSnapshot.start.lendingPool.addressAccounting.etherBalance,
            "When a validatorPool repays 10 ether, then: the ether balance of the lending pool should have remained unchanged"
        );
        /// THEN the total debt in the pool should have decreased by 10 ether
        assertApproxEqRel(
            _firstDeltaSystemSnapshot.delta.lendingPool.totalBorrow.amount,
            10 ether,
            1e15,
            "When a validatorPool repays 10 ether, then: the total debt amount on the lending pool should have decreased by 10 ether"
        );
        /// THEN the total debt shares in the pool should have decreased
        assertLt(
            _firstDeltaSystemSnapshot.end.lendingPool.totalBorrow.shares,
            _firstDeltaSystemSnapshot.start.lendingPool.totalBorrow.shares,
            "When a validatorPool repays 10 ether, then: the debt shares should have decreased"
        );

        // WHEN owner uses their balance to repay 10E
        // Anyone can repay on behalf of a validator pool
        vm.prank(validatorPoolOwner);
        lendingPool.repay{ value: 10 ether }(validatorPoolAddress);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // WHEN Curve AMO operator triggers sweep of the deposited funds from the Ether Router to the Redemption Queue and/or Curve AMO(s)
        // vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        vm.prank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        etherRouter.sweepEther(10 ether, true);
        vm.prank(validatorPoolOwner);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// Take deltas after the repay and sweep (again)
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
        DeltaSystemSnapshot memory _secondDeltaSystemSnapshot = deltaSystemSnapshot(_firstDeltaSystemSnapshot.end);

        // THEN the Curve AMO should have an extra 10 ether again
        assertApproxEqRel(_netAmoAccounting1.totalETH, 10e18, ONE_PCT_DELTA, "AMO Accounting: totalETH [B]");

        /// THEN allowance should remain unchanged
        assertEq(
            _secondDeltaSystemSnapshot.start.validatorPool.lendingPool_validatorPoolAccount.borrowAllowance,
            _secondDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowAllowance,
            "When a validatorPool repays 10 ether, then: the borrow allowance should remain unchanged"
        );
        /// THEN validatorPool debt should decrease by 10 ether
        assertApproxEqRel(
            lendingPool.toBorrowAmount(
                _secondDeltaSystemSnapshot.start.validatorPool.lendingPool_validatorPoolAccount.borrowShares
            ) - 10 ether,
            lendingPool.toBorrowAmount(
                _secondDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowShares
            ),
            1e15,
            "When a validatorPool repays 10 ether, then: the debt for that validator pool should have decreased by 10 ether"
        );
        /// THEN validatorPool ether balance should remain unchanged
        assertEq(
            _secondDeltaSystemSnapshot.start.validatorPool.addressAccounting.etherBalance,
            _secondDeltaSystemSnapshot.end.validatorPool.addressAccounting.etherBalance,
            "When a user repays 10 ether on behalf of a validator pool, then: the ether balance of the validator pool should have changed by 0 ether"
        );
        assertEq(
            _secondDeltaSystemSnapshot.delta.validatorPool.addressAccounting.etherBalance,
            0,
            "When a user repays 10 ether on behalf of a validator pool, then: the ether balance of the validator pool should have changed by 0 ether"
        );
        /// THEN lendingPool ether balance should remain unchanged
        assertEq(
            _secondDeltaSystemSnapshot.start.lendingPool.addressAccounting.etherBalance,
            _secondDeltaSystemSnapshot.end.lendingPool.addressAccounting.etherBalance,
            "When a user repays 10 ether on behalf of a validator pool, then: the ether balance of the lending pool should have changed by 0 ether"
        );
        /// THEN lendingPool total debt should decrease by 10 ether
        assertEq(
            _secondDeltaSystemSnapshot.start.lendingPool.totalBorrow.amount - 10 ether,
            _secondDeltaSystemSnapshot.end.lendingPool.totalBorrow.amount,
            "When a user repays 10 ether on behalf of a validator pool, then: the total debt amount on the lending pool should have decreased by 10 ether"
        );
        /// THEN lendingPool utilization rate should decrease
        assertLt(
            _secondDeltaSystemSnapshot.end.lendingPool.utilization,
            _secondDeltaSystemSnapshot.start.lendingPool.utilization,
            "When a user repays 10 ether on behalf of a validator pool, then: the utilization rate of the lending pool should have decreased"
        );
    }

    function test_CMRepayAllFuzz(
        uint256 _vpEarnings,
        uint256 _poolFractionE6,
        uint256 _msgSenderFractionE6,
        bool _repayAll
    ) public {
        // Bound the fuzz inputs and set _msgSenderFractionE6
        _vpEarnings = bound(_poolFractionE6, 0, 1e18);
        _poolFractionE6 = bound(_poolFractionE6, 0, 1e6);
        _msgSenderFractionE6 = 1e6 - _poolFractionE6;
        // TODO: Test overpaying?

        // SCENARIO: successful simple repay flow
        /// GIVEN the borrower has borrowed 20E and sent it to the validator pool owner
        uint256 borrowAmount = 20 ether;
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(validatorPoolOwner, borrowAmount);

        // Make sure the VP is empty
        assertEq(validatorPoolAddress.balance, 0, "VP should be empty right now");

        printAndReturnSystemStateInfo("======== AFTER BORROW ========", true);

        // Wait 1 year. Do not addInterest (simulates no activity)
        for (uint256 i = 0; i < 4; i++) {
            mineBlocksBySecond(90 days);
            // lendingPool.addInterest(false);
        }

        // Do not print system info as it can add interest
        console.log("<<<After 1 year>>>");
        // printAndReturnSystemStateInfo("======== AFTER 1 YEAR ========", true);

        // Do not check utilization as it can add interest
        // Make sure stored utilization matches live utilization
        // checkStoredVsLiveUtilization();

        /// The validator pool has earned interest since the borrow
        vm.deal(validatorPoolAddress, validatorPoolAddress.balance + _vpEarnings);

        // See how much needs to be repaid
        uint256 _amtToRepay = validatorPool.getAmountBorrowed();
        (uint256 _amtToRepayStored, uint256 _sharesBorrowed) = validatorPool.getAmountAndSharesBorrowedStored();
        uint256 _poolRepayAmt = (_amtToRepay * _poolFractionE6) / 1e6;
        uint256 _msgSenderAmt = _amtToRepay - _poolRepayAmt;
        console.log("<<<----- INFO BEFORE----->>>");
        console.log("_poolRepayAmt: ", _poolRepayAmt);
        console.log("_msgSenderAmt: ", _msgSenderAmt);
        console.log("getAmountBorrowed: ", _amtToRepay);
        console.log("_amtToRepayStored: ", _amtToRepayStored);
        console.log("_sharesBorrowed: ", _sharesBorrowed);

        // The stored borrowed amount should be lower than the wouldBeSolvent-obtained one
        assertGt(
            _amtToRepay,
            _amtToRepayStored,
            "The stored borrowed amount should be lower than the wouldBeSolvent-obtained one"
        );

        // Check for potential issues
        bool _willRevert;
        if (_poolRepayAmt > validatorPoolAddress.balance) {
            _willRevert = true;
            console.log("   ---> Expected to revert: Insufficient ETH in VP");
            vm.expectRevert();
        }

        // Vary the route
        if (_repayAll) {
            vm.prank(validatorPoolOwner);
            validatorPool.repayAllWithPoolAndValue{ value: _msgSenderAmt }();
        } else {
            vm.prank(validatorPoolOwner);
            validatorPool.repayWithPoolAndValue{ value: _msgSenderAmt }(_poolRepayAmt);
        }

        // Do checks
        if (!_willRevert) {
            _amtToRepay = validatorPool.getAmountBorrowed();
            (_amtToRepayStored, _sharesBorrowed) = validatorPool.getAmountAndSharesBorrowedStored();
            _poolRepayAmt = (_amtToRepay * _poolFractionE6) / 1e6;
            _msgSenderAmt = _amtToRepay - _poolRepayAmt;
            console.log("<<<----- INFO AFTER----->>>");
            console.log("getAmountBorrowed: ", _amtToRepay);
            console.log("_amtToRepayStored: ", _amtToRepayStored);
            console.log("_sharesBorrowed: ", _sharesBorrowed);
            assertEq(
                _amtToRepay,
                _amtToRepayStored,
                "The stored borrowed amount should equal the wouldBeSolvent-obtained one"
            );
            assertEq(_sharesBorrowed, 0, "Borrow shares should be 0");
        }

        // revert();
    }
}
