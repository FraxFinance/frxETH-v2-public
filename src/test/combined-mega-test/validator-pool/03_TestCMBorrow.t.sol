// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./02_TestCMDeposit.t.sol";

struct AddressAccounting {
    uint256 etherBalance;
    uint256 frxEthBalance;
}

contract TestCMBorrow is CombinedMegaBaseTest, depositValidatorFunctions {
    /// FEATURE: User Borrows ether using validator as collateral

    using LendingPoolStructHelper for LendingPool;
    using RedemptionQueueStructHelper for FraxEtherRedemptionQueueV2;

    address payable borrowRecipient;

    function setUp() public {
        borrowRecipient = labelAndDeal(address(4482), "borrowRecipient");
        /// BACKGROUND: All base contracts have been deployed and configured

        _defaultSetup();
        /// BACKGROUND: a validator pool has been properly deployed

        // Change to the operator so you can trigger the sweep
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);

        // First set the Ether Router balance to 20 ether.
        // Sweep 10 ETH to the Redemption Queue and/or Curve AMO(s), leave 10 ETH in the EtherRouter, drop 5 ETH into the Curve AMO
        // This is to simulate mixed ETH in various places and force LP unwinding at the Curve AMO
        vm.deal(etherRouterAddress, 20 ether);
        etherRouter.sweepEther(10 ether, true); // Put in LP
        vm.deal(curveLsdAmoAddress, 5 ether);
        vm.stopPrank();

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();
    }

    function test_BorrowHighUtilization() public {
        /// GIVEN a borrower has 1 validator deposited
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0]
        });
        /// GIVEN Oracle has validated the signing message of the validator
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 1);

        /// GIVEN Oracle has validated that no ether has already been borrowed, and set the borrow allowance to 23.5 ether
        uint256 _borrowAllowance = _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);

        // WHEN the borrower borrows 23.5 ether
        InitialSystemSnapshot memory _initialSystemSnapshot = initialSystemSnapshot(
            borrowRecipient,
            bytes(""),
            lendingPool,
            validatorPool
        );
        uint256 _borrowAmount = 235e17; // 23.5 ether
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(borrowRecipient, _borrowAmount);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// THEN the borrow shares should be equal to an amount that represents 23.5 ether
        DeltaSystemSnapshot memory _firstDeltaSystemSnapshot = deltaSystemSnapshot(_initialSystemSnapshot);
        assertEq(
            lendingPool.toBorrowAmount(
                _firstDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowShares
            ),
            _borrowAmount,
            "When a borrower borrows 23.5 ether, then: the borrow shares should be equal to an amount that represents 23.5 ether"
        );

        /// THEN: the ether balance should have changed by 23.5 ether
        assertEq(
            _borrowAmount,
            _firstDeltaSystemSnapshot.delta.user.etherBalance,
            "When a validatorPool borrows 23.5 ether to send to a recipient, then: the ether balance should have changed by 23.5 ether"
        );
        /// THEN: the borrow allowance should be 0
        assertEq(
            _firstDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowAllowance,
            0,
            "Given a starting allowance of 23.5, \
            When a validatorPool borrows 23.5 ether to send to a recipient, \
            Then: the borrow allowance should be 0"
        );
        /// THEN: the total borrow amount should increase by 23.5 ether
        assertEq(
            _firstDeltaSystemSnapshot.delta.lendingPool.totalBorrow.amount,
            _borrowAmount,
            "When a validatorPool borrows 23.5 ether to send to a recipient, then: the total borrow amount should increase by 23.5 ether"
        );

        /// THEN: There should be ~1.5 ether left in the Curve AMO
        {
            uint256[10] memory allocations = amoHelper.showAllocations(curveLsdAmoAddress);
            assertApproxEqRel(
                allocations[9],
                1.5e18,
                0.02e18,
                "AMO Accounting Final: Total ETH + WETH deposited into Pools [test_BorrowFlow]"
            );
        }

        // Test negative allowance corner case
        {
            // Lower the credit per validator first
            _beaconOracle_setVPoolCreditPerValidatorI48_E12(validatorPoolAddress, 0.1e12);

            // Set validator pool borrow allowances (single validator method, negative allowance so will fail)
            uint32 _lastWithdrawalTimestamp = lendingPool.getLastWithdrawalTimestamp(address(validatorPool));
            vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
            vm.expectRevert(abi.encodeWithSignature("AllowanceWouldBeNegative()"));
            beaconOracle.setVPoolValidatorCountAndBorrowAllowance(
                payable(validatorPoolAddress),
                1,
                0 ether,
                _lastWithdrawalTimestamp
            );
        }

        {
            // (
            //     uint256 _interestAccrued,
            //     uint256 _ethTotalBalanced,
            //     uint256 _totalNonValidatorEthSum,
            //     uint256 _optimisticValidatorEth,
            //     uint256 _ttlSystemEth
            // ) =
            printAndReturnSystemStateInfo("======== AT END ========", true);

            console.log("====================== UTILITY RATE ======================");
            console.log("UTILITY RATE (live, cache updated): ", lendingPool.getUtilization(true, true));
            console.log("UTILITY RATE (live, cache not updated): ", lendingPool.getUtilization(true, false));
            console.log("UTILITY RATE (cached, cache updated?): ", lendingPool.getUtilization(false, true));
            console.log("UTILITY RATE (cached, cache not updated): ", lendingPool.getUtilization(false, false));
        }
    }

    function test_BorrowMidUtilization() public {
        // Give a bunch of ETH to the EtherRouter to put utility somewhere mid-range
        // vm.deal(etherRouterAddress, (frxETH.totalSupply() + 1000 ether) / 2);

        /// GIVEN a borrower has 1 validator deposited
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0]
        });
        /// GIVEN Oracle has validated the signing message of the validator
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 1);

        /// GIVEN Oracle has validated that no ether has already been borrowed, and set the borrow allowance to 23.5 ether
        uint256 _borrowAllowance = _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);

        // WHEN the borrower borrows 0.05 ether
        InitialSystemSnapshot memory _initialSystemSnapshot = initialSystemSnapshot(
            borrowRecipient,
            bytes(""),
            lendingPool,
            validatorPool
        );
        uint256 _borrowAmount = 12.5e18; // 16 ether
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(borrowRecipient, _borrowAmount);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// THEN the borrow shares should be equal to an amount that represents 16 ether
        DeltaSystemSnapshot memory _firstDeltaSystemSnapshot = deltaSystemSnapshot(_initialSystemSnapshot);
        assertEq(
            lendingPool.toBorrowAmount(
                _firstDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowShares
            ),
            _borrowAmount,
            "When a borrower borrows 12.5e18 ether, then: the borrow shares should be equal to an amount that represents 12.5e18 ether"
        );

        /// THEN: the ether balance should have changed by 12.5e18 ether
        assertEq(
            _borrowAmount,
            _firstDeltaSystemSnapshot.delta.user.etherBalance,
            "When a validatorPool borrows 12.5e18 ether to send to a recipient, then: the ether balance should have changed by 12.5e18 ether"
        );
        /// THEN: the borrow allowance should be 0
        assertEq(
            _firstDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowAllowance,
            (23.5 ether) - 12.5e18,
            "Given a starting allowance of 23.5, \
            When a validatorPool borrows 12.5e18 ether to send to a recipient, \
            Then: the borrow allowance should be 23.5e8 - 12.5e18"
        );
        /// THEN: the total borrow amount should increase by 12.5e18 ether
        assertEq(
            _firstDeltaSystemSnapshot.delta.lendingPool.totalBorrow.amount,
            _borrowAmount,
            "When a validatorPool borrows 12.5e18 ether to send to a recipient, then: the total borrow amount should increase by 0.05e18 ether"
        );

        {
            // (
            //     uint256 _interestAccrued,
            //     uint256 _ethTotalBalanced,
            //     uint256 _totalNonValidatorEthSum,
            //     uint256 _optimisticValidatorEth,
            //     uint256 _ttlSystemEth
            // ) =
            printAndReturnSystemStateInfo("======== AT CHECK 1 ========", true);
        }

        console.log("====================== UTILITY RATE CHECK #1 ======================");
        /// THEN: the utilization should be 50%
        assertEq(lendingPool.getUtilization(true, false), 0.5e5, "Utilization should be 50%");

        console.log("UTILIZATION STORED (before): ", lendingPool.utilizationStored());
        console.log("UTILITY RATE (live, cache not updated): ", lendingPool.getUtilization(true, false));
        console.log("UTILITY RATE (cached, cache not updated): ", lendingPool.getUtilization(false, false));
        console.log("UTILIZATION STORED (mid): ", lendingPool.utilizationStored());
        console.log("UTILITY RATE (cached, cache updated?): ", lendingPool.getUtilization(false, true));
        console.log("UTILITY RATE (live, cache updated): ", lendingPool.getUtilization(true, true));
        console.log("UTILIZATION STORED (after): ", lendingPool.utilizationStored());

        console.log("====================== SMALL BORROW ======================");
        uint256 _borrowAmountSmall = 1e18; // 16 ether
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(borrowRecipient, _borrowAmountSmall);

        /// THEN: the utilization should be 54%
        assertEq(lendingPool.getUtilization(true, false), 0.54e5, "Utilization should be 54%");

        /// THEN: the utilizationStored should be 54%
        assertEq(lendingPool.utilizationStored(), 0.54e5, "Utilization stored should be 54%");

        console.log("UTILIZATION STORED (before): ", lendingPool.utilizationStored());
        console.log("UTILITY RATE (live, cache not updated): ", lendingPool.getUtilization(true, false));
        console.log("UTILITY RATE (cached, cache not updated): ", lendingPool.getUtilization(false, false));
        console.log("UTILIZATION STORED (mid): ", lendingPool.utilizationStored());
        console.log("UTILITY RATE (cached, cache updated?): ", lendingPool.getUtilization(false, true));
        console.log("UTILITY RATE (live, cache updated): ", lendingPool.getUtilization(true, true));
        console.log("UTILIZATION STORED (after): ", lendingPool.utilizationStored());
    }

    function test_BorrowZeroUtilization() public {
        // Give a bunch of ETH to the EtherRouter to lower utility to 0
        vm.deal(etherRouterAddress, frxETH.totalSupply() + 1000 ether);

        /// GIVEN a borrower has 1 validator deposited
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0]
        });
        /// GIVEN Oracle has validated the signing message of the validator
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 1);

        /// GIVEN Oracle has validated that no ether has already been borrowed, and set the borrow allowance to 23.5 ether
        uint256 _borrowAllowance = _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);

        // WHEN the borrower borrows 0.05 ether
        InitialSystemSnapshot memory _initialSystemSnapshot = initialSystemSnapshot(
            borrowRecipient,
            bytes(""),
            lendingPool,
            validatorPool
        );
        uint256 _borrowAmount = 0.05e18; // 0.05 ether
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(borrowRecipient, _borrowAmount);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// THEN the borrow shares should be equal to an amount that represents 0.05 ether
        DeltaSystemSnapshot memory _firstDeltaSystemSnapshot = deltaSystemSnapshot(_initialSystemSnapshot);
        assertEq(
            lendingPool.toBorrowAmount(
                _firstDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowShares
            ),
            _borrowAmount,
            "When a borrower borrows 0.05e18 ether, then: the borrow shares should be equal to an amount that represents 0.05e18 ether"
        );

        /// THEN: the ether balance should have changed by 0.05e18 ether
        assertEq(
            _borrowAmount,
            _firstDeltaSystemSnapshot.delta.user.etherBalance,
            "When a validatorPool borrows 0.05e18 ether to send to a recipient, then: the ether balance should have changed by 0.05e18 ether"
        );
        /// THEN: the borrow allowance should be 0
        assertEq(
            _firstDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowAllowance,
            (23.5 ether) - 0.05e18,
            "Given a starting allowance of 23.5, \
            When a validatorPool borrows 0.05e18 ether to send to a recipient, \
            Then: the borrow allowance should be 23.5e8 - 0.05e18"
        );
        /// THEN: the total borrow amount should increase by 0.05e18 ether
        assertEq(
            _firstDeltaSystemSnapshot.delta.lendingPool.totalBorrow.amount,
            _borrowAmount,
            "When a validatorPool borrows 0.05e18 ether to send to a recipient, then: the total borrow amount should increase by 0.05e18 ether"
        );

        console.log("====================== UTILITY RATE ======================");
        console.log("UTILIZATION STORED (before): ", lendingPool.utilizationStored());
        console.log("UTILITY RATE (live, cache not updated): ", lendingPool.getUtilization(true, false));
        console.log("UTILITY RATE (cached, cache not updated): ", lendingPool.getUtilization(false, false));
        console.log("UTILIZATION STORED (mid): ", lendingPool.utilizationStored());
        console.log("UTILITY RATE (cached, cache updated?): ", lendingPool.getUtilization(false, true));
        console.log("UTILITY RATE (live, cache updated): ", lendingPool.getUtilization(true, true));
        console.log("UTILIZATION STORED (after): ", lendingPool.utilizationStored());
    }

    function test_BorrowRepaySteppedUtilization() public {
        uint256 NUM_STEPS = 50;
        uint256 STEP_INCREMENT_ETH = (frxETH.totalSupply() + 1000 ether) / NUM_STEPS;

        // For code coverage
        console.log("variableInterestRate.name(): ", variableInterestRate.name());
        variableInterestRate.version();

        /// GIVEN a borrower has 1 validator deposited
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0]
        });

        /// GIVEN Oracle has validated the signing message of the validator
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 1);

        // Try borrowing without setting the allowance (should fail)
        hoax(validatorPoolOwner);
        vm.expectRevert(abi.encodeWithSignature("AllowanceWouldBeNegative()"));
        validatorPool.borrow(validatorPoolAddress, 0.1 ether);

        /// GIVEN Oracle has validated that no ether has already been borrowed, and set the borrow allowance to 23.5 ether
        uint256 _borrowAllowance = _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);

        // Do multiple borrows, giving some ETH to the Ether Router each time
        for (uint256 i = 0; i < NUM_STEPS; ++i) {
            vm.prank(validatorPoolOwner);
            validatorPool.borrow(validatorPoolAddress, 0.1 ether);

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();

            // Dump ETH into the EtherRouter to alter the utilization
            vm.deal(etherRouterAddress, address(etherRouterAddress).balance + STEP_INCREMENT_ETH);

            console.log("====================== UTILITY RATE (BORROW PHASE) ======================");
            console.log("Borrowed Amount: ", validatorPool.getAmountBorrowed());
            console.log("EtherRouter ETH Balance: ", address(etherRouterAddress).balance);
            console.log("UTILITY RATE (live, cache updated): ", lendingPool.getUtilization(true, true));
            console.log("UTILITY RATE (live, cache not updated): ", lendingPool.getUtilization(true, false));
            console.log("UTILITY RATE (cached, cache updated?): ", lendingPool.getUtilization(false, true));
            console.log("UTILITY RATE (cached, cache not updated): ", lendingPool.getUtilization(false, false));
        }

        // Switch to the repay phase
        console.log("");
        console.log("==================================================================");
        console.log("========================== REPAY PHASE ===========================");
        console.log("==================================================================");
        console.log("");

        // Do multiple repays, taking some ETH to the Ether Router each time
        for (uint256 i = 0; i < NUM_STEPS; ++i) {
            vm.prank(validatorPoolOwner);
            validatorPool.repayWithPoolAndValue{ value: 0 }(0.1 ether);

            // Take ETH from the EtherRouter to alter the utilization
            vm.deal(etherRouterAddress, address(etherRouterAddress).balance - STEP_INCREMENT_ETH);

            console.log("====================== UTILITY RATE (REPAY PHASE) ======================");
            console.log("Borrowed Amount: ", validatorPool.getAmountBorrowed());
            console.log("EtherRouter ETH Balance: ", address(etherRouterAddress).balance);
            console.log("UTILITY RATE (live, cache updated): ", lendingPool.getUtilization(true, true));
            console.log("UTILITY RATE (live, cache not updated): ", lendingPool.getUtilization(true, false));
            console.log("UTILITY RATE (cached, cache updated?): ", lendingPool.getUtilization(false, true));
            console.log("UTILITY RATE (cached, cache not updated): ", lendingPool.getUtilization(false, false));
        }
    }

    function test_BorrowFuzz(uint256 _borrowAmount, uint256 _ethDumpAmount) public {
        // Bound the fuzz amounts
        _borrowAmount = bound(_borrowAmount, 1000 gwei, 23.5 ether);
        _ethDumpAmount = bound(_ethDumpAmount, 1 wei, frxETH.totalSupply() + 1000 ether);

        // Dump ETH into the EtherRouter to alter the utilization
        vm.deal(etherRouterAddress, address(etherRouterAddress).balance + _ethDumpAmount);

        /// GIVEN a borrower has 1 validator deposited
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0]
        });
        /// GIVEN Oracle has validated the signing message of the validator
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 1);

        /// GIVEN Oracle has validated that no ether has already been borrowed, and set the borrow allowance to 23.5 ether
        uint256 _borrowAllowance = _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);

        // WHEN the borrower borrows 0.5 ether
        InitialSystemSnapshot memory _initialSystemSnapshot = initialSystemSnapshot(
            borrowRecipient,
            bytes(""),
            lendingPool,
            validatorPool
        );
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(borrowRecipient, _borrowAmount);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// THEN the borrow shares should be equal to an amount that represents _borrowAmount ether
        DeltaSystemSnapshot memory _firstDeltaSystemSnapshot = deltaSystemSnapshot(_initialSystemSnapshot);
        assertEq(
            lendingPool.toBorrowAmount(
                _firstDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowShares
            ),
            _borrowAmount,
            "When a borrower borrows _borrowAmount ether, then: the borrow shares should be equal to an amount that represents _borrowAmount ether"
        );

        /// THEN: the ether balance should have changed by _borrowAmount ether
        assertEq(
            _borrowAmount,
            _firstDeltaSystemSnapshot.delta.user.etherBalance,
            "When a validatorPool borrows _borrowAmount ether to send to a recipient, then: the ether balance should have changed by _borrowAmount ether"
        );
        /// THEN: the borrow allowance should be 0
        assertEq(
            _firstDeltaSystemSnapshot.end.validatorPool.lendingPool_validatorPoolAccount.borrowAllowance,
            (23.5 ether) - _borrowAmount,
            "Given a starting allowance of 23.5, \
            When a validatorPool borrows _borrowAmount ether to send to a recipient, \
            Then: the borrow allowance should be 23.5 - _borrowAmount"
        );
        /// THEN: the total borrow amount should increase by _borrowAmount ether
        assertEq(
            _firstDeltaSystemSnapshot.delta.lendingPool.totalBorrow.amount,
            _borrowAmount,
            "When a validatorPool borrows _borrowAmount ether to send to a recipient, then: the total borrow amount should increase by _borrowAmount ether"
        );

        console.log("====================== UTILITY RATE ======================");
        console.log("UTILIZATION STORED (before): ", lendingPool.utilizationStored());
        console.log("UTILITY RATE (live, cache not updated): ", lendingPool.getUtilization(true, false));
        console.log("UTILITY RATE (cached, cache not updated): ", lendingPool.getUtilization(false, false));
        console.log("UTILIZATION STORED (mid): ", lendingPool.utilizationStored());
        console.log("UTILITY RATE (cached, cache updated?): ", lendingPool.getUtilization(false, true));
        console.log("UTILITY RATE (live, cache updated): ", lendingPool.getUtilization(true, true));
        console.log("UTILIZATION STORED (after): ", lendingPool.utilizationStored());
    }

    function test_RecoverStrandedEth() public {
        // Throw some ETH into the Lending Pool, where it technically should not accumulate
        deal(lendingPoolAddress, 100 ether);

        // Note balances before
        uint256 _lendingPoolEthBefore = lendingPoolAddress.balance;
        uint256 _etherRouterEthBefore = etherRouterAddress.balance;

        // Change to the operator so you can trigger the recovery
        vm.startPrank(Constants.Mainnet.TIMELOCK_ADDRESS);

        // Do the recovery
        uint256 _amountRecovered = lendingPool.recoverStrandedEth();

        // Do checks
        assertEq(
            etherRouterAddress.balance - _etherRouterEthBefore,
            _amountRecovered,
            "Ether Router should have recovered some ETH"
        );
        assertEq(
            _lendingPoolEthBefore - lendingPoolAddress.balance,
            _amountRecovered,
            "Lending Pool should have sent out the ETH"
        );
    }

    // function test_ZachFullUtilRateStuck() public {
    //     // Remove amo so the calculations are simpler
    //     vm.prank(ConstantsDep.Mainnet.TIMELOCK_ADDRESS);
    //     etherRouter.removeAmo(address(curveLsdAmo));

    //     console.log("Starting Utilization: ", lendingPool.getUtilization(false, false));
    //     (, , uint64 fullUtilRate1) = lendingPool.currentRateInfo();
    //     console.log("Starting Full Util Rate: ", fullUtilRate1);
    //     vm.warp(block.timestamp + 10 days);

    //     console.log("******");

    //     uint256 etherRouterBalance = etherRouterAddress.balance;
    //     vm.prank(etherRouterAddress);
    //     payable(address(123)).transfer(etherRouterBalance);

    //     console.log("Midstream Utilization: ", lendingPool.getUtilization(false, false));
    //     lendingPool.addInterest(false);
    //     (, , uint64 fullUtilRate2) = lendingPool.currentRateInfo();
    //     console.log("Midstream Full Util Rate: ", fullUtilRate2);
    //     vm.warp(block.timestamp + 10 days);

    //     console.log("******");
    //     vm.prank(address(123));
    //     payable(etherRouterAddress).transfer(etherRouterBalance);

    //     console.log("Final Utilization: ", lendingPool.getUtilization(false, false));
    //     lendingPool.addInterest(false);
    //     (, , uint64 fullUtilRate3) = lendingPool.currentRateInfo();
    //     console.log("Final Full Util Rate: ", fullUtilRate3);
    // }
}
