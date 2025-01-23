// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./02_TestCMDeposit.t.sol";

contract TestCMLiquidate is CombinedMegaBaseTest, depositValidatorFunctions {
    using LendingPoolStructHelper for LendingPool;
    using RedemptionQueueStructHelper for FraxEtherRedemptionQueueV2;

    /// FEATURE: Users can eject validators and collect ether

    function setUp() public {
        /// BACKGROUND: All base contracts have been deployed and configured
        _defaultSetup();

        /// BACKGROUND: Beacon oracle has set the credit per validator to 28E
        _beaconOracle_setVPoolCreditPerValidatorI48_E12(validatorPoolAddress, 28e12);

        // Zero out any ETH and frxETH in the EtherRouter and CurveLsdAMO
        vm.deal(etherRouterAddress, 0);
        vm.deal(curveLsdAmoAddress, 0);

        // Test user deposits some ETH for frxETH
        vm.startPrank(testUserAddress);
        vm.deal(testUserAddress, 60 ether);
        fraxEtherMinter.mintFrxEth{ value: 60 ether }();
        vm.stopPrank();

        // Sweep 60 ETH to the Redemption Queue and/or Curve AMO(s)
        // This is to simulate mixed ETH in various places and force LP unwinding at the Curve AMO
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        etherRouter.sweepEther(60 ether, true); // Put in LP
        vm.stopPrank();

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// Take initial snapshots
        // -----------------------------------------
        _validatorDepositInfoSnapshotInitial = validatorDepositInfoSnapshot(validatorPublicKeys[0], lendingPool);
        _validatorPoolAccountingSnapshotInitial = validatorPoolAccountingSnapshot(validatorPool);
        _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);
        _initialSystemSnapshot = initialSystemSnapshot(validatorPoolOwner, bytes(""), lendingPool, validatorPool);
        // -----------------------------------------

        /// Create 2 fully-funded validator deposits
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0]
        });
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[1],
            _validatorSignature: validatorSignatures[1]
        });

        /// GIVEN the beacon oracle has verified the deposits
        _beaconOracle_setValidatorApproval(validatorPublicKeys[0], validatorPoolAddress, uint32(block.timestamp));
        _beaconOracle_setValidatorApproval(validatorPublicKeys[1], validatorPoolAddress, uint32(block.timestamp));

        /// GIVEN the beacon oracle has updated the count and allowance
        _beaconOracle_setVPoolValidatorCountAndBorrowAllowanceWithBuffer(validatorPoolAddress, 2, 0);
    }

    function becomeInsolvent() public {
        // Borrow 55.95 ETH, close to the max of ((28 - 0.0 [buffer]) * 2) = 56
        uint256 _borrowAmount = 55.95 ether;
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(validatorPoolOwner, _borrowAmount);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Wait 15 days
        mineBlocksBySecond(15 days);

        // Accrue some interest
        lendingPool.addInterest(false);

        /// The position should be insolvent now
        assertEq(lendingPool.isSolvent(payable(validatorPool)), false, "Position should be insolvent now");

        // Print info
        printAndReturnSystemStateInfo("======== AFTER BORROW, MINE, AND ACCRUE ========", true);
        uint256 _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
        console.log("_borrowShares (in shares): ", _borrowShares);
        console.log("_borrowShares (in ETH): ", lendingPool.toBorrowAmount(_borrowShares));

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();
    }

    // function becomeInsolventLighter() public {
    //     // Borrow 54.5 ETH, close to the max of (27.5 * 2) = 55
    //     uint256 _borrowAmount = 54.5 ether;
    //     vm.prank(validatorPoolOwner);
    //     validatorPool.borrow(validatorPoolOwner, _borrowAmount);

    //     // Wait 1 month
    //     mineBlocksBySecond(30 days);

    //     // Accrue some interest
    //     lendingPool.addInterest(false);

    //     /// The position should be insolvent now
    //     assertEq(lendingPool.isSolvent(payable(validatorPool)), false, "Position should be insolvent now");

    //     uint256 _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
    //     console.log("======== AFTER WAITING ONE MONTH ========");
    //     console.log("_borrowShares (in shares): ", _borrowShares);
    //     console.log("_borrowShares (in ETH): ", lendingPool.toBorrowAmount(_borrowShares));
    // }

    function test_LiquidationFlowNormal() public {
        // Borrow ETH to become insolvent
        console.log("<<<Becoming insolvent>>>");
        becomeInsolvent();

        // Trigger 2 validators to exit
        // Done off-chain

        // Wait 1 days for the exit
        console.log("<<<Mining 1 days>>>");
        mineBlocksBySecond(1 days);

        // Accrue some interest
        console.log("<<<Adding Interest>>>");
        lendingPool.addInterest(false);

        // 64 ETH from the exit is dumped into the validator pool
        vm.deal(validatorPoolAddress, 64 ether);

        printAndReturnSystemStateInfo("======== AFTER ACCRUING AND EXITING ========", true);

        // Get the amount owed
        uint256 _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;

        /// GIVEN that the beacon oracle forces a liquidation repay
        console.log("<<<Liquidating>>>");
        vm.startPrank(beaconOracleAddress);
        lendingPool.liquidate(payable(validatorPool), lendingPool.toBorrowAmount(_borrowShares));
        vm.stopPrank();

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// GIVEN the beacon oracle has updated the count and allowance
        console.log("<<<Zeroing the count and borrow allowance>>>");
        _beaconOracle_setVPoolValidatorCountAndBorrowAllowanceManual(validatorPoolAddress, 0, 0);

        // NOTE: Because the liquidation was delayed, the protocol lost interest income, but nevertheless still got the lent Eth back
        // User originally put up 64 ETH for 2 full validators, then borrowed 54.5 ETH
        // For the liquidation, he lost all of his 64 ETH as collateral and welched on 21.78 - (64 - 54.5) = 12.28 ETH of interest income
        // To minimize this IRL, make sure interest accruals and liquidations are done in a timely manner.

        printAndReturnSystemStateInfo("======== AFTER PARTIAL LIQUIDATION ========", true);

        // Refresh _borrowShares
        _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;

        /// GIVEN that the VP owner is honest and repays the remaining ETH needed for the loan
        /// See note above
        vm.startPrank(validatorPoolOwner);
        console.log("<<<--- VP Owner Repays --->>>");
        uint256 _ttlToRepay = lendingPool.toBorrowAmount(_borrowShares);

        console.log("   - Throw 25% of the amount into the VP");
        payable(validatorPoolAddress).transfer(_ttlToRepay / 4);

        console.log("   - repayWithPoolAndValue 25% and 25%");
        validatorPool.repayWithPoolAndValue{ value: _ttlToRepay / 4 }(_ttlToRepay / 4);

        console.log("   - Throw 25% of the amount into the VP again");
        payable(validatorPoolAddress).transfer(_ttlToRepay / 4);

        console.log("   - repayAllWithPoolAndValue");
        validatorPool.repayAllWithPoolAndValue{ value: _ttlToRepay / 4 }();
        vm.stopPrank();

        // lendingPool.toBorrowAmount(_borrowShares)

        // Validator pool owner withdraws remaining crumbs
        console.log("<<<Liquidated VP owner withdraws crumbs>>>");
        vm.startPrank(validatorPoolOwner);
        validatorPool.withdraw(validatorPoolOwner, validatorPoolAddress.balance);
        vm.stopPrank();

        // Double check that it was liquidated
        assertEq(lendingPool.wasLiquidated(validatorPoolAddress), true, "Should have been liquidated");

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Attempt to deposit again. Should fail due to having been liquidated
        {
            vm.startPrank(validatorPoolOwner);

            // Generate credentials
            DepositCredentials memory _depositCredentials = generateDepositCredentials(
                validatorPool,
                validatorPublicKeys[5],
                validatorSignatures[5],
                32 ether
            );

            // Attempt to deposit (should fail)
            vm.expectRevert(abi.encodeWithSignature("ValidatorPoolWasLiquidated()"));
            validatorPool.deposit{ value: 32 ether }(
                _depositCredentials.publicKey,
                _depositCredentials.signature,
                _depositCredentials.depositDataRoot
            );

            vm.stopPrank();
        }
    }

    // function test_LiquidationFlowAlt() public {
    //     // Borrow ETH to become insolvent, but don't accrue too much interest
    //     console.log("<<<Becoming insolvent>>>");
    //     becomeInsolventLighter();

    //     // Trigger 2 validators to exit
    //     // Done off-chain

    //     // Wait 3 days for the exit
    //     console.log("<<<Mining 3 days>>>");
    //     mineBlocksBySecond(3 days);

    //     // Accrue some interest
    //     console.log("<<<Adding Interest>>>");
    //     lendingPool.addInterest(false);

    //     // 64 ETH from the exit is dumped into the validator pool
    //     vm.deal(validatorPoolAddress, 64 ether);

    //     printAndReturnSystemStateInfo("======== AFTER ACCRUING AND EXIT DEALING ========", true);

    //     // Get the amount owed
    //     uint256 _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;

    //     /// GIVEN that a random user forces a liquidation repay
    //     console.log("<<<Liquidating>>>");
    //     vm.startPrank(testUserAddress);
    //     lendingPool.liquidate(payable(validatorPool), lendingPool.toBorrowAmount(_borrowShares));
    //     vm.stopPrank();

    //     printAndReturnSystemStateInfo("======== AFTER LIQUIDATION ========", true);

    //     /// GIVEN the beacon oracle has updated the count and allowance
    //     _beaconOracle_setVPoolValidatorCountAndBorrowAllowanceManual(validatorPoolAddress, 0, 0);

    //     printAndReturnSystemStateInfo("======== AFTER BEACONING ========", true);

    //     // Validator pool owner withdraws remaining crumbs
    //     console.log("<<<Liquidated VP owner withdraws crumbs>>>");
    //     vm.startPrank(validatorPoolOwner);
    //     validatorPool.withdraw(validatorPoolOwner, validatorPoolAddress.balance);
    //     vm.stopPrank();
    // }

    function test_LiquidationVoluntaryRepayBeforeLiquidation() public {
        // Borrow ETH to become insolvent
        becomeInsolvent();

        // Trigger 2 validators to exit
        // Done off-chain

        // Wait 2 days for the exit
        mineBlocksBySecond(2 days);

        // Accrue some interest
        console.log("<<<Adding Interest>>>");
        lendingPool.addInterest(false);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // 64 ETH from the exit is dumped into the validator pool
        vm.deal(validatorPoolAddress, 64 ether);

        // Print info
        printAndReturnSystemStateInfo("======== AFTER BEACON EXIT, MINING, and ACCRUING ========", true);

        // Get the amount owed
        uint256 _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;

        // WHEN owner voluntarily repays before the liquidation (1st half)
        console.log("<<<Repaying 1st half of shares>>>");
        vm.prank(validatorPoolOwner);
        validatorPool.repayShares(_borrowShares / 2);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Print info
        printAndReturnSystemStateInfo("======== AFTER HALF REPAY ========", true);

        // WHEN owner voluntarily repays before the liquidation (2nd half)
        console.log("<<<Repaying 2nd half of shares>>>");
        // Re-fetch _borrowShares due to potential rounding
        _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
        vm.prank(validatorPoolOwner);
        validatorPool.repayShares(_borrowShares);

        // Random user tries to liquidate (should fail)
        console.log("<<<Liquidating (as disallowed sender, should fail)>>>");
        vm.startPrank(testUserAddress);
        try lendingPool.liquidate(payable(validatorPool), lendingPool.toBorrowAmount(_borrowShares)) {
            revert("Should not have succeeded");
        } catch (bytes memory reason) {
            assertEq(LendingPoolCore.NotAllowedLiquidator.selector, bytes4(reason));
        }
        vm.stopPrank();

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Try to liquidate while still solvent (should fail)
        console.log("<<<Liquidating (still solvent, should fail)>>>");
        vm.startPrank(beaconOracleAddress);
        try lendingPool.liquidate(payable(validatorPool), lendingPool.toBorrowAmount(_borrowShares)) {
            revert("Should not have succeeded");
        } catch (bytes memory reason) {
            assertEq(LendingPoolCore.ValidatorPoolIsSolvent.selector, bytes4(reason));
        }
        vm.stopPrank();

        // Print info
        printAndReturnSystemStateInfo("======== AFTER LIQUIDATING ========", true);

        // Validator pool owner withdraws remaining crumbs
        console.log("<<<Withdrawing>>>");
        hoax(validatorPoolOwner);
        validatorPool.withdraw(validatorPoolOwner, validatorPoolAddress.balance);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Print info
        printAndReturnSystemStateInfo("======== AFTER WITHDRAWING ========", true);
    }

    // function test_LiquidationFlowOutOfSyncBorrowAndBeaconLiquidation() public {
    //     // Borrow ETH to become insolvent
    //     becomeInsolvent();
    // }

    // function test_LiquidationFlowOutOfSyncWithdrawAndBeaconLiquidation() public {
    //     // Borrow ETH to become insolvent
    //     becomeInsolvent();
    // }

    // // TEST BAD BEACON SYNC ISSUES, PERHAPS IN OTHER PLACES TOO

    // CONTINUE HERE!!!
}
