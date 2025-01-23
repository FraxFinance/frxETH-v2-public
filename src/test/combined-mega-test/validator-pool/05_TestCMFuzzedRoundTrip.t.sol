// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./02_TestCMDeposit.t.sol";

contract TestCMFuzzedRoundTrip is CombinedMegaBaseTest, depositValidatorFunctions {
    using logSnapshot for *;
    using LendingPoolStructHelper for LendingPool;
    using RedemptionQueueStructHelper for FraxEtherRedemptionQueueV2;

    // A lot of these are put here to remove the size of the stack
    bool _isRedeemable;
    uint120 _maxAmountRedeemable;
    uint256[10] borrowAllowancesTracked; // Keep track of borrow allowances
    uint256[10] borrowAmountsTracked; // Keep track of borrow amounts
    uint256 expectedExitEth; // Expected amount of Eth that should exit from the validators
    bool firstFullDepSucceeded; // If the first full deposit succeeded
    bool firstFullDepProperlyBeaconed; // If the first full deposit succeeded and was beaconed
    bool middlePartialDepSucceeded; // If the second partial deposit succeeded
    bool middlePartialFinalizeShouldFail; // If the second partial deposit should fail
    uint256 borrowSharesTemp; // Temporary variable for tracking borrow shares
    uint256 secondPartialDepositBorrowAmt; // Borrow balance right before the second partial deposit
    bool liq1Succeeded; // If the liquidation succeeded
    bool depositOnSweepEther; // If sweepEther simply dumps ETH into the Curve AMO, or if it additionally puts it into LP
    bool[3] doBeacon; // Whether to do beacon actions at certain parts of the test
    bool[2] tryLiquidations; // Whether to try liquidating at certain parts of the test
    bool[3] completedNftRedemptions; // If an NFT redemption completed
    bool[2] redeemRequests; // Whether the testUser requests to redeem frxETH for ETH at certain parts of the test
    uint120 REDEEM_0_AMT = 35 ether;
    uint120 REDEEM_1_AMT = 15 ether;
    uint256[3] rdmTcktNftIds; // Possible redemption ticket NFT ids.

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
        vm.deal(testUserAddress, 35 ether);
        fraxEtherMinter.mintFrxEth{ value: 35 ether }();
        vm.stopPrank();

        // Sweep 25 ETH to the Redemption Queue and/or Curve AMO(s) and leave 10 ETH in the EtherRouter
        // This is to simulate mixed ETH in various places and force LP unwinding at the Curve AMO
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        etherRouter.sweepEther(25 ether, true); // Put in LP
        vm.stopPrank();

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// BACKGROUND: All 3 validators (2 full, 1 partial have been setup)
        _setupThreeValidators();
        expectedExitEth = 96 ether;

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Test user deposits some additional ETH for frxETH
        vm.startPrank(testUserAddress);
        vm.deal(testUserAddress, 95.5 ether);
        fraxEtherMinter.mintFrxEth{ value: 95.5 ether }();
        vm.stopPrank();

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Give the validator pool owner an additional 97.5 ETH
        vm.deal(validatorPoolOwner, 97.5 ether);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // // Assume the Curve AMO has ample frxETH
        // deal(address(frxETH), curveLsdAmoAddress, 100000e18, true);

        // Maximum "clean" credit for free borrows should be
        // 2 initial full validators: 27.5 * 2 = 55
        // 1 later full validator: 27.5
        // = 82.5

        // Maximum amount the validator pool / owner should ever need (assuming 0 interest)
        // 2 initial full validators: 64
        // 1 initial partial validator: 8
        // 1 later full validator: 32
        // 1 later partial validator: 8
        // = 112

        // Maximum amount the lending pool should ever need
        // Clean credit: 82.5
        // 2x Partial deposits: 48
        // = 130.5

        // Maximum amount before insolvency / liquidation
        // 5 x 28 = 140

        // NOTE: 35 ETH was from frxETH minting in super.setUp(), 72 ETH was from the validator pool owner,
        // 95.5 ETH was further minted above (130.5 ETH total for the lending system), and we are giving
        // the validator pool owner an extra 97.5 ETH above (169.5 ETH total for the validator owner/pool).
        // Total ETH in circulation everywhere should be 300

        /// Take initial snapshots
        // -----------------------------------------
        _validatorDepositInfoSnapshotInitial = validatorDepositInfoSnapshot(validatorPublicKeys[0], lendingPool);
        _validatorPoolAccountingSnapshotInitial = validatorPoolAccountingSnapshot(validatorPool);
        _amoAccountingFinals[0] = initialAmoSnapshot(curveLsdAmoAddress);
        _amoPoolAccountingFinals[0] = initialPoolSnapshot(curveLsdAmoAddress);
        _initialSystemSnapshot = initialSystemSnapshot(validatorPoolOwner, bytes(""), lendingPool, validatorPool);
        // -----------------------------------------

        {
            (
                uint256 _interestAccrued,
                uint256 _ethTotalBalanced,
                uint256 _totalNonValidatorEthSum,
                uint256 _optimisticValidatorEth,
                uint256 _ttlSystemEth
            ) = printAndReturnSystemStateInfo("======== AT START ========", true);
            totalNonValidatorEthSums[0] = _totalNonValidatorEthSum;
            totalSystemEthSums[0] = _ttlSystemEth;
        }

        // Make sure the total system ETH is 300
        assertApproxEqAbs(
            totalSystemEthSums[0],
            300e18,
            0.15e18,
            "Total ETH in the contracts + validators should be 300"
        );
    }

    function _setupThreeValidators() internal {
        // Make 2 full deposits and 1 partial one
        // ======================================

        // Validator fully deposits 32 ETH for pkey 0
        console.log("<<<_fullValidatorDeposit [pkey 0]>>>");
        DepositCredentials memory _depositCredentialsPkey0 = _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0]
        });

        // Validator fully deposits 32 ETH for pkey 1
        console.log("<<<_fullValidatorDeposit [pkey 1]>>>");
        DepositCredentials memory _depositCredentialsPkey1 = _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[1],
            _validatorSignature: validatorSignatures[1]
        });

        // Validator partially deposits 8 ETH for pkey 2
        console.log("<<<_partialValidatorDeposit [pkey 2]>>>");
        DepositCredentials memory _depositCredentialsPkey2 = _partialValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[2],
            _validatorSignature: validatorSignatures[2],
            _depositAmount: PARTIAL_DEPOSIT_AMOUNT
        });

        // Wait a day
        mineBlocksBySecond(1 days);

        // Beacon oracle approves both public keys
        console.log("<<<_beaconOracle_setValidatorApproval [pkeys 0-2]>>>");
        _beaconOracle_setValidatorApproval(validatorPublicKeys[0], validatorPoolAddress, uint32(block.timestamp));
        _beaconOracle_setValidatorApproval(validatorPublicKeys[1], validatorPoolAddress, uint32(block.timestamp));
        _beaconOracle_setValidatorApproval(validatorPublicKeys[2], validatorPoolAddress, uint32(block.timestamp));

        // Borrow the remaining 24 ETH for the pkey 2 validator
        console.log("<<<_requestFinalValidatorDepositByPkeyIdx [pkey 2]>>>");
        _requestFinalValidatorDepositByPkeyIdx(2);

        /// Update the validator count and allowance
        console.log("<<<setVPoolValidatorCount & setVPoolBorrowAllowanceWithBuffer>>>");
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 3);
        _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);

        // {
        //     (
        //         uint256 _interestAccrued,
        //         uint256 _ethTotalBalanced,
        //         uint256 _totalNonValidatorEthSum,
        //         uint256 _optimisticValidatorEth,
        //         uint256 _ttlSystemEth
        //     ) = printAndReturnSystemStateInfo("======== AFTER 3 VALIDATOR (2 FULL, 1 PARTIAL) ========", true);
        //     // totalNonValidatorEthSums[0] = _totalNonValidatorEthSum;
        //     // totalSystemEthSums[0] = _ttlSystemEth;
        // }
    }

    function testFuzz_MainPath(
        uint256[2] memory _borrowFzAmts,
        uint256[3] memory _accrueFzTimes,
        uint256[2] memory _repayWithdrawFzAmts,
        bool[10] memory _miscFzBools,
        uint256[2] memory _depositAndDumpFzAmts
    ) public {
        // ============= FILL STACK-REDUCING STATE VARIABLES ============

        // Fill in bools
        // Beacons
        for (uint256 i = 0; i < 3; i++) {
            doBeacon[i] = _miscFzBools[i];
        }

        // Liquidations
        for (uint256 i = 0; i < 2; i++) {
            tryLiquidations[i] = _miscFzBools[3 + i];
        }

        // Redeems
        for (uint256 i = 0; i < 2; i++) {
            redeemRequests[i] = _miscFzBools[5 + i];
        }

        // Depositing on sweepEther
        // depositOnSweepEther = _miscFzBools[9];
        depositOnSweepEther = false; // Override to false for now

        // ======================== BOUND INPUTS ========================
        // Don't want to accrue an obscene amount of interest
        _accrueFzTimes[0] = bound(_accrueFzTimes[0], 0, 365 days);
        _accrueFzTimes[1] = bound(_accrueFzTimes[1], 0, 365 days);
        _accrueFzTimes[2] = bound(_accrueFzTimes[2], 0, 365 days);

        // If this is too low, the Curve fee / slippage amount will cause it to revert. 1000 gwei is the minimum anyways
        _borrowFzAmts[0] = bound(_borrowFzAmts[0], 1000 gwei, 500 ether);
        _borrowFzAmts[1] = bound(_borrowFzAmts[1], 1000 gwei, 500 ether);

        // Repay amounts should be reasonable
        _repayWithdrawFzAmts[0] = bound(_repayWithdrawFzAmts[0], 0, 500 ether);

        // Withdrawal amounts should be reasonable
        _repayWithdrawFzAmts[1] = bound(_repayWithdrawFzAmts[1], 0, 500 ether);

        // Deposit amounts should be reasonable
        // ----------------------------------
        // _depositAndDumpFzAmts[0] = 8 ether; // For testing before refactor
        _depositAndDumpFzAmts[0] = bound(_depositAndDumpFzAmts[0], 0, 65 ether);

        // Truncate to the nearest ether
        _depositAndDumpFzAmts[0] = (_depositAndDumpFzAmts[0] / (1 ether)) * (1 ether);

        // Calculate the borrow amount for finalizing the second partial deposit
        if ((_depositAndDumpFzAmts[0] >= 1 ether) && (_depositAndDumpFzAmts[0] < 32 ether)) {
            secondPartialDepositBorrowAmt = (32 ether) - _depositAndDumpFzAmts[0];
        }

        // Dumped-in ETH should be reasonable
        // ----------------------------------
        _depositAndDumpFzAmts[1] = bound(_depositAndDumpFzAmts[1], 1 wei, frxETH.totalSupply() + 1000 ether);

        // Dump ETH into the Ether Router to alter the utilization
        console.log("<<<Dump in fuzzed ETH to Ether Router to alter utilization>>>");
        vm.deal(etherRouterAddress, address(etherRouterAddress).balance + _depositAndDumpFzAmts[1]);

        // Manually add interest / update utilization to account for dump-in case
        lendingPool.addInterest(false);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        console.log("===================================================");
        console.log("=================== FUZZ VALUES ===================");
        console.log("===================================================");
        console.log("_borrowFzAmts[0]: ", _borrowFzAmts[0]);
        console.log("_borrowFzAmts[1]: ", _borrowFzAmts[1]);
        console.log("_accrueFzTimes[0]: ", _accrueFzTimes[0]);
        console.log("_accrueFzTimes[1]: ", _accrueFzTimes[1]);
        console.log("_accrueFzTimes[2]: ", _accrueFzTimes[2]);
        console.log("_repayWithdrawFzAmts[0] (repay): ", _repayWithdrawFzAmts[0]);
        console.log("doBeacon[0]: ", doBeacon[0]);
        console.log("doBeacon[1]: ", doBeacon[1]);
        console.log("doBeacon[2]: ", doBeacon[2]);
        console.log("_repayWithdrawFzAmts[1] (withdrawal): ", _repayWithdrawFzAmts[1]);
        console.log("_depositAndDumpFzAmts[0]: ", _depositAndDumpFzAmts[0]);
        console.log("_depositAndDumpFzAmts[1]: ", _depositAndDumpFzAmts[1]);
        console.log("tryLiquidations[0]: ", tryLiquidations[0]);
        console.log("tryLiquidations[1]: ", tryLiquidations[1]);
        console.log("redeemRequests[0]: ", redeemRequests[0]);
        console.log("redeemRequests[1]: ", redeemRequests[1]);
        console.log("secondPartialDepositBorrowAmt: ", secondPartialDepositBorrowAmt);

        // Start impersonating the validator pool owner
        vm.startPrank(validatorPoolOwner);

        // ======================== BORROW #1 ========================
        // See how much you are allowed to borrow, and how much you already did
        {
            (, , , , , borrowAllowancesTracked[0], borrowSharesTemp) = lendingPool.validatorPoolAccounts(
                validatorPoolAddress
            );
            borrowAmountsTracked[0] = lendingPool.toBorrowAmount(borrowSharesTemp);
        }

        // 24 ether from the 1st partial validator
        require(borrowAmountsTracked[0] == (24 ether), "Borrow amount should be 24 ether");

        // 84 - (0.5 buffer * 3) - (24 ether existing borrow) = 58.5 ether
        console.log("<<<Attempting first borrow, allowed to fail>>>");
        if (_borrowFzAmts[0] > 58.5 ether) {
            console.log("   ---> Expected to revert");
            vm.expectRevert();
        }
        validatorPool.borrow(validatorPoolOwner, _borrowFzAmts[0]);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        printAndReturnSystemStateInfo("======== AFTER FIRST BORROW ========", true);

        // ======================== ACCRUE #1 ========================
        // Wait some time
        mineBlocksBySecond(_accrueFzTimes[0]);

        // Accrue some interest
        console.log("<<<Add interest>>>");
        lendingPool.addInterest(false);

        printAndReturnSystemStateInfo("======== AFTER FIRST ACCRUE ========", true);

        // ======================== Enter Redemption Queue #1 (OPTIONAL) ========================
        // Test user wants to redeem some frxETH
        if (redeemRequests[0]) {
            vm.stopPrank();
            vm.startPrank(testUserAddress);
            frxETH.approve(redemptionQueueAddress, REDEEM_0_AMT);
            rdmTcktNftIds[0] = redemptionQueue.enterRedemptionQueue(testUserAddress, REDEEM_0_AMT);
            vm.stopPrank();

            console.log("<<<Enter redemption queue #1>>>");
        }

        // ======================== DEPOSIT #1 (FULL) ========================
        // Deposit a full validator
        console.log("<<<Trying full deposit #1>>>");
        {
            // Get the solvency details assuming you did the full deposit
            (bool _wouldBeSolvent, , ) = lendingPool.wouldBeSolvent(validatorPoolAddress, true, 1, 0);

            // Make credentials
            DepositCredentials memory _depositCredentials = generateDepositCredentials(
                validatorPool,
                validatorPublicKeys[3],
                validatorSignatures[3],
                32 ether
            );

            // Check for expected failures
            if (!_wouldBeSolvent) {
                console.log("   ---> Expected to revert: Expected to be insolvent");
                vm.expectRevert();
            } else {
                // No revert expected
                firstFullDepSucceeded = true;
                expectedExitEth += 32 ether;
            }

            // Try the deposit
            vm.stopPrank();
            vm.prank(validatorPoolOwner);
            validatorPool.deposit{ value: 32 ether }(
                _depositCredentials.publicKey,
                _depositCredentials.signature,
                _depositCredentials.depositDataRoot
            );

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();

            console.log("<<<Full deposit #1 succeeded>>>");
        }

        printAndReturnSystemStateInfo("======== AFTER DEPOSIT #1 (FULL) [Not beaconed yet] ========", true);

        // Beacon Oracle has validated the signing message of the validator
        if (firstFullDepSucceeded && doBeacon[0]) {
            console.log("<<<Beacon deposit #1>>>");
            _beaconOracle_setVPoolValidatorCountAndBorrowAllowanceWithBuffer(validatorPoolAddress, 4, 0);

            // Mark that everything succeeded
            firstFullDepProperlyBeaconed = true;
        } else {
            console.log("<<<Skip beaconing the deposit>>>");
        }

        // Make sure you cannot withdraw yet
        console.log("<<<Attempting a withdrawal, must fail>>>");
        vm.prank(validatorPoolOwner);
        vm.expectRevert();
        validatorPool.withdraw(validatorPoolOwner, 1 ether);

        // Make sure the total amount of ETH everywhere adds up
        {
            (, , , , uint256 _ttlSystemEth) = printAndReturnSystemStateInfo(
                "======== AFTER FIRST DEPOSIT (FULL) ========",
                true
            );
            // If beacon[0] never hits, 32 ETH "disappears" because the validator count is never increased
            uint256 _beacon0Correction;

            // If the deposit even succeeded in the first place
            if (firstFullDepSucceeded) {
                // Account for the lack or presence of the beacon
                _beacon0Correction = doBeacon[0] ? 0 : 32 ether;
            }

            // Check total ETH
            assertApproxEqRel(
                _ttlSystemEth + _beacon0Correction,
                300e18 + _depositAndDumpFzAmts[1],
                HALF_PCT_DELTA,
                "Total ETH in the contracts + validators should be 300"
            );
        }

        // ======================== BORROW #2 ========================
        // See how much you are allowed to borrow, and how much you already did
        console.log("<<<Calling lendingPool.validatorPoolAccounts>>>");
        (, , , , , borrowAllowancesTracked[1], borrowSharesTemp) = lendingPool.validatorPoolAccounts(
            validatorPoolAddress
        );
        borrowAmountsTracked[1] = lendingPool.toBorrowAmount(borrowSharesTemp);

        {
            // See how much ETH is available to the Ether Router
            uint256 _maxBorrow = lendingPool.getMaxBorrow();

            // Get the solvency details assuming you did the additional borrow
            (bool _wouldBeSolvent, , ) = lendingPool.wouldBeSolvent(validatorPoolAddress, true, 0, _borrowFzAmts[1]);

            // If the beacon oracle didn't update AND you are trying to borrow more than the previous borrow allowance
            // Or if it did update and you are borrowing too much
            // Or there is not enough ETH in the Curve AMO
            // Then this should fail, otherwise it will succeed
            console.log("<<<Attempting second borrow, allowed to fail>>>");
            if (!firstFullDepProperlyBeaconed && (_borrowFzAmts[1] > borrowAllowancesTracked[0])) {
                console.log(
                    "   ---> Expected to revert: !firstFullDepProperlyBeaconed && (_borrowFzAmts[1] > borrowAllowancesTracked[0])"
                );
                vm.expectRevert();
            } else if (_borrowFzAmts[1] > borrowAllowancesTracked[1]) {
                console.log("   ---> Expected to revert: Trying to borrow more than your allowance");
                vm.expectRevert();
            } else if (_borrowFzAmts[1] > _maxBorrow) {
                console.log(
                    "   ---> Expected to revert: Ether Router does not have enough ETH, after any RQ shortages"
                );
                vm.expectRevert();
            } else if (!_wouldBeSolvent) {
                console.log("   ---> Expected to revert: Expected to be insolvent");
                vm.expectRevert();
            }
            vm.prank(validatorPoolOwner);
            validatorPool.borrow(validatorPoolOwner, _borrowFzAmts[1]);

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();
        }

        printAndReturnSystemStateInfo("======== AFTER SECOND BORROW ========", true);

        // ======================== ACCRUE #2 ========================

        // Wait some time
        mineBlocksBySecond(_accrueFzTimes[1]);

        // Accrue some interest
        console.log("<<<Add interest>>>");
        lendingPool.addInterest(false);

        printAndReturnSystemStateInfo("======== AFTER SECOND ACCRUE ========", true);

        // ======================== SWEEP SOME ETHER ========================

        // Sweep some ETH, optionally depositing it
        if (depositOnSweepEther) console.log("<<<Sweep Ether, with deposit>>>");
        else console.log("<<<Sweep Ether, no deposit>>>");

        // Do the sweep
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        etherRouter.sweepEther(0, depositOnSweepEther);

        printAndReturnSystemStateInfo("======== AFTER SWEEPETHER ========", true);

        // ======================== REPAY #1 ========================
        // See how much you are allowed to borrow, and how much you already did
        (, , , , , borrowAllowancesTracked[2], borrowSharesTemp) = lendingPool.validatorPoolAccounts(
            validatorPoolAddress
        );
        borrowAmountsTracked[2] = lendingPool.toBorrowAmount(borrowSharesTemp);

        // Give the validator pool enough for a repayment. Will fail if it is more than the balance of the pool owner
        console.log("<<<Attempting first repay>>>");

        {
            uint256 _amtVPoolLackingFuzzRepay = 0;
            if (validatorPoolAddress.balance < _repayWithdrawFzAmts[0]) {
                _amtVPoolLackingFuzzRepay = _repayWithdrawFzAmts[0] - validatorPoolAddress.balance;
            }

            vm.prank(validatorPoolOwner);
            if (_amtVPoolLackingFuzzRepay > address(validatorPoolOwner).balance) {
                vm.expectRevert();
                console.log(
                    "   ---> Expected to revert [_amtVPoolLackingFuzzRepay > address(validatorPoolOwner).balance]"
                );
            }
            validatorPoolAddress.call{ value: _amtVPoolLackingFuzzRepay }("");
        }

        // Trying to repay more than you owe should fail, so if the fuzz hits this, just repay what you owe
        vm.prank(validatorPoolOwner);
        if (_repayWithdrawFzAmts[0] > borrowAmountsTracked[2]) {
            console.log("   ---> Expected to revert: fuzz repay amount > amount owed");
            vm.expectRevert();
            validatorPool.repayWithPoolAndValue{ value: 0 }(_repayWithdrawFzAmts[0]);

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();

            // In this case, just repay what you owe
            console.log("   ---> Trying to repay just what you owe");
            {
                // See how much the validator pool is lacking for the repay
                uint256 _amtVPoolLackingFullRepay = 0;
                if (validatorPoolAddress.balance < borrowAmountsTracked[2]) {
                    _amtVPoolLackingFullRepay = borrowAmountsTracked[2] - validatorPoolAddress.balance;
                }

                vm.prank(validatorPoolOwner);
                if (_amtVPoolLackingFullRepay > address(validatorPoolOwner).balance) {
                    console.log(
                        "   ---> Expected to revert: VP owner has less than what the VPool needs to repay the loan"
                    );
                    vm.expectRevert();
                }
                validatorPoolAddress.call{ value: _amtVPoolLackingFullRepay }("");
            }
            vm.prank(validatorPoolOwner);
            if (borrowAmountsTracked[2] > validatorPoolAddress.balance) {
                console.log("   ---> Expected to revert: VPool doesn't have enough ETH to repay the loan");
                vm.expectRevert();
            }
            validatorPool.repayWithPoolAndValue{ value: 0 }(borrowAmountsTracked[2]);

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();
        } else {
            // If the owner and the pool both don't have enough, expect a revert
            if (_repayWithdrawFzAmts[0] > (validatorPoolAddress.balance + address(validatorPoolOwner).balance)) {
                console.log("   ---> Expected to revert: VPool + VP Owner don't have enough ETH to repay the loan");
                vm.expectRevert();
            }
            validatorPool.repayWithPoolAndValue{ value: 0 }(_repayWithdrawFzAmts[0]);

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();
        }

        printAndReturnSystemStateInfo("======== AFTER FIRST REPAY ========", true);

        // ======================== Enter Redemption Queue #2 (OPTIONAL) ========================
        // Test user wants to redeem some frxETH again
        if (redeemRequests[1]) {
            vm.stopPrank();
            vm.startPrank(testUserAddress);
            frxETH.approve(redemptionQueueAddress, REDEEM_1_AMT);
            rdmTcktNftIds[1] = redemptionQueue.enterRedemptionQueue(testUserAddress, REDEEM_1_AMT);
            vm.stopPrank();

            console.log("<<<Enter redemption queue #2>>>");
        }

        // ======================== Early (or Regular) Redemption Exit #1 (OPTIONAL) ========================
        // Test user wants to exit the redemption queue early, or regularly if enough time elapsed
        if (redeemRequests[0]) {
            vm.stopPrank();
            vm.startPrank(testUserAddress);

            // See if you can redeem normally first
            (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(rdmTcktNftIds[0], 0, false);
            if (_isRedeemable) {
                // Exit fully if you can
                redemptionQueue.fullRedeemNft(rdmTcktNftIds[0], testUserAddress);
                console.log("<<<Early Full Redeem #1 [normal burn]>>>");

                // Make sure _maxAmountRedeemable and REDEEM_0_AMT match
                assertEq(
                    _maxAmountRedeemable,
                    REDEEM_0_AMT,
                    "Early Full Redeem #1: _maxAmountRedeemable doesn't match full redeem amount"
                );
            } else {
                // Exit partially if you can
                if (_maxAmountRedeemable > 0) {
                    redemptionQueue.partialRedeemNft(rdmTcktNftIds[0], testUserAddress, _maxAmountRedeemable);
                    console.log("<<<Early Partial Redeem #1 [normal method]>>>");
                }
            }
            vm.stopPrank();
        }

        printAndReturnSystemStateInfo("======== AFTER EARLY FULL REDEEM 1 ========", true);

        // ======================== FIRST LIQUIDATION ATTEMPT ========================

        // Try liquidating if fuzzed
        if (tryLiquidations[0]) {
            (bool _wouldBeSolvent, uint256 _borrowAmt, ) = lendingPool.wouldBeSolvent(validatorPoolAddress, true, 0, 0);
            uint256 _amtToRepay = _borrowAmt > validatorPoolAddress.balance ? validatorPoolAddress.balance : _borrowAmt;

            console.log("<<<Attempting first liquidation>>>");
            vm.prank(beaconOracleAddress);
            if (_wouldBeSolvent) {
                console.log("   ---> Expected to revert: Cannot liquidate because position is not insolvent");
                vm.expectRevert();
                lendingPool.liquidate(validatorPoolAddress, _amtToRepay);
            } else {
                lendingPool.liquidate(validatorPoolAddress, _amtToRepay);
                liq1Succeeded = true;
            }

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();

            printAndReturnSystemStateInfo("======== AFTER FIRST LIQUIDATION ATTEMPT ========", true);
        }

        // ======================== DEPOSIT #2 (PARTIAL) ========================
        // Deposit a partial validator
        console.log("<<<Attempting the partial validator deposit>>>");
        {
            // FROM _partialValidatorDeposit
            // Make credentials
            DepositCredentials memory _depositCredentials = generateDepositCredentials(
                validatorPool,
                validatorPublicKeys[4],
                validatorSignatures[4],
                _depositAndDumpFzAmts[0]
            );

            // Simulate a partial (or full, depending on the fuzz) deposit event
            uint256 _neededAmt = 0;
            uint256 _vpEthBalance = validatorPoolAddress.balance;
            if (_vpEthBalance < (_depositAndDumpFzAmts[0])) {
                _neededAmt = ((_depositAndDumpFzAmts[0]) - _vpEthBalance);
            }

            // Do the partial deposit
            vm.startPrank(validatorPoolOwner);
            if (liq1Succeeded) {
                console.log("   ---> Expected to revert: Cannot deposit after a liquidation");
                vm.expectRevert();
            } else if (_depositAndDumpFzAmts[0] < 1 ether) {
                console.log("   ---> Expected to revert: Need at least 1 ether");
                vm.expectRevert();
            } else if (_depositAndDumpFzAmts[0] > 32 ether) {
                console.log("   ---> Expected to revert: Deposit must be at most 32 ETH");
                vm.expectRevert();
            } else if ((address(validatorPoolOwner).balance) < _depositAndDumpFzAmts[0]) {
                console.log("   ---> Expected to revert: VP owner does not have enough ETH");
                vm.expectRevert();
            } else {
                // Special case if you are "partial" depositing exactly 32 ETH
                bool _willRevert;
                if (_depositAndDumpFzAmts[0] == 32 ether) {
                    // Get the solvency details assuming you did the full deposit
                    (bool _wouldBeSolvent, , ) = lendingPool.wouldBeSolvent(validatorPoolAddress, true, 1, 0);

                    // Check for solvency
                    if (!_wouldBeSolvent) {
                        _willRevert = true;
                        console.log("   ---> Expected to revert: Would be insolvent");
                        vm.expectRevert();
                    }
                }

                // Check for reverts
                if (!_willRevert) {
                    // No revert expected
                    expectedExitEth += _depositAndDumpFzAmts[0];
                    middlePartialDepSucceeded = true;
                }
            }

            // Do the deposit
            validatorPool.deposit{ value: _depositAndDumpFzAmts[0] }(
                _depositCredentials.publicKey,
                _depositCredentials.signature,
                _depositCredentials.depositDataRoot
            );

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();

            vm.stopPrank();
        }

        // Beacon Oracle approves the partial pubkey deposit
        // If doBeacon[1] is false, the partial deposit will never complete
        // If doBeacon[1] is true, but doBeacon[2] is false, the partial deposit will complete, but the validator count and allowance will be wrong.
        // We want to test for both conditions
        console.log("<<<Possibly doing the final deposit and/or beaconing>>>");
        if ((!liq1Succeeded) && middlePartialDepSucceeded && doBeacon[1]) {
            console.log("   ---> Calling setValidatorApproval and requestFinalDeposit");
            _beaconOracle_setValidatorApproval(validatorPublicKeys[4], validatorPoolAddress, uint32(block.timestamp));

            // See how much ETH is available to the Ether Router
            uint256 _maxBorrow = lendingPool.getMaxBorrow();

            // Get the solvency details assuming you finalized the partial deposit
            (bool _wouldBeSolvent, , ) = lendingPool.wouldBeSolvent(
                validatorPoolAddress,
                true,
                1,
                secondPartialDepositBorrowAmt
            );

            // Request secondPartialDepositBorrowAmt to complete the deposit
            // Prep the Deposit credentials
            DepositCredentials memory _finalDepositCredentials = generateDepositCredentials(
                validatorPool,
                validatorPublicKeys[4],
                validatorSignatures[4],
                secondPartialDepositBorrowAmt
            );

            // Do the requestFinalDeposit
            // Will revert if Ether Router does not have secondPartialDepositBorrowAmt available, or you would end up in an insolvent state
            vm.prank(validatorPoolOwner);
            if (secondPartialDepositBorrowAmt > _maxBorrow) {
                console.log(
                    "   ---> Expected to revert: Ether Router does not have enough ETH, after any RQ shortages"
                );
                middlePartialFinalizeShouldFail = true;
                vm.expectRevert();
            } else if (!_wouldBeSolvent) {
                console.log("   ---> Expected to revert: Would be insolvent");
                middlePartialFinalizeShouldFail = true;
                vm.expectRevert();
            } else if (_depositAndDumpFzAmts[0] == 32 ether) {
                console.log("   ---> Expected to revert: Already have 32 ETH finalized for this pubkey");
                middlePartialFinalizeShouldFail = true;
                vm.expectRevert();
            } else {
                // Assuming it doesn't revert
                expectedExitEth += secondPartialDepositBorrowAmt;
            }
            validatorPool.requestFinalDeposit(
                _finalDepositCredentials.publicKey,
                _finalDepositCredentials.signature,
                _finalDepositCredentials.depositDataRoot
            );

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();

            // Oracle has validated the signing message of the validator
            if (doBeacon[2] && !middlePartialFinalizeShouldFail) {
                console.log("   ---> Calling setVPoolValidatorCount and setVPoolBorrowAllowanceWithBuffer");
                _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 5);
                _beaconOracle_setVPoolBorrowAllowanceManualBuffer(validatorPoolAddress, 0);
            } else {
                console.log("<<<Skipping setVPoolValidatorCount and setVPoolBorrowAllowanceWithBuffer>>>");
            }
        }

        // Make sure you cannot withdraw, unless you repaid everything and the partial deposit never finalizes
        console.log("<<<Attempting a withdrawal, can succeed>>>");
        {
            // See how much you borrowed
            (, , , , , borrowAllowancesTracked[3], borrowSharesTemp) = lendingPool.validatorPoolAccounts(
                validatorPoolAddress
            );
            borrowAmountsTracked[3] = lendingPool.toBorrowAmount(borrowSharesTemp);

            // If you have any borrowed amount, it should fail
            // It will also fail if the validator pool has less than 1 ether
            if (borrowAmountsTracked[3] > 0) {
                console.log("   ---> Expected to revert, still have an outstanding loan");
                vm.expectRevert();
            } else if (validatorPoolAddress.balance < 1 ether) {
                console.log("   ---> Expected to revert, not enough ETH in validator pool");
                vm.expectRevert();
            }
            vm.prank(validatorPoolOwner);
            validatorPool.withdraw(validatorPoolOwner, 1 ether);

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();
        }

        // ======================== Early (or Regular) Redemption Exit #2 (OPTIONAL) ========================
        // Test user wants to exit the redemption queue early, or regularly if enough time elapsed
        if (redeemRequests[1]) {
            vm.stopPrank();
            vm.startPrank(testUserAddress);

            // See if you can redeem normally first
            (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(rdmTcktNftIds[1], 0, false);
            if (_isRedeemable) {
                // Shouldn't be able to redeem more than the max amount
                vm.expectRevert();
                redemptionQueue.partialRedeemNft(rdmTcktNftIds[1], testUserAddress, _maxAmountRedeemable + 1);

                // Exit fully if you can
                redemptionQueue.fullRedeemNft(rdmTcktNftIds[1], testUserAddress);
                console.log("<<<Early Full Redeem #2 [normal burn]>>>");

                // Make sure _maxAmountRedeemable and REDEEM_1_AMT match
                assertEq(
                    _maxAmountRedeemable,
                    REDEEM_1_AMT,
                    "Early Full Redeem #2: _maxAmountRedeemable doesn't match full redeem amount"
                );
            } else {
                // Exit partially if you can
                if (_maxAmountRedeemable > 0) {
                    redemptionQueue.partialRedeemNft(rdmTcktNftIds[1], testUserAddress, _maxAmountRedeemable);
                    console.log("<<<Early Partial Redeem #2 [normal method]>>>");
                }
            }

            vm.stopPrank();
        }

        printAndReturnSystemStateInfo("======== AFTER EARLY FULL REDEEM 2 ========", true);

        // ======================== CHECK ETH SUMS ========================

        // Make sure the total amount of ETH everywhere adds up
        console.log("<<<Checking ETH sums>>>");
        {
            (, , , , uint256 _ttlSystemEth) = printAndReturnSystemStateInfo(
                "======== AFTER SECOND DEPOSIT (PARTIAL) ========",
                true
            );

            // 4 outcomes
            // Also account for middlePartialFinalizeShouldFail
            // liq1Succeeded is true, meaning no partial deposit occured.
            // doBeacon[1] is false, doBeacon[2] is irrelevant: _depositAndDumpFzAmts[0], but account for doBeacon[0] from before too
            // doBeacon[1] and doBeacon[2] are true: No adjustment needed
            // doBeacon[1] is true, doBeacon[2] is false: 32 ether, but account for doBeacon[0] from before too
            // Deal with the success/failure of the 1st full deposit later

            uint256 _noBeaconCorrection = 0;
            if (liq1Succeeded || !middlePartialDepSucceeded) {
                // Do nothing, partial deposit never happened
                console.log("<<<NBC Part 1: +0 ETH [liq1Succeeded || !middlePartialDepSucceeded]>>>");
            } else if (doBeacon[1] && !middlePartialFinalizeShouldFail && doBeacon[2]) {
                // Do nothing, this is the optimistic path with everything registered
                console.log("<<<NBC Part 1: +0 ETH [optimal path]>>>");
            } else if (!doBeacon[1] || (doBeacon[1] && middlePartialFinalizeShouldFail)) {
                // No beacon1 OR beacon1, but insufficient ETH to finalize
                // doBeacon[2] irrelevant here
                // Partial deposit never finalized
                _noBeaconCorrection = _depositAndDumpFzAmts[0];
                console.log("<<<NBC Part 1: +_depositAndDumpFzAmts[0] ETH>>>");
            } else if (doBeacon[1] && !middlePartialFinalizeShouldFail && !doBeacon[2]) {
                // Beacon1 and sufficient ETH, but beacon2 never called
                // Partial deposit completed, but beacon never registered it
                _noBeaconCorrection = 32 ether;
                console.log("<<<NBC Part 1: +32 ETH>>>");
            }

            // If _beaconOracle_setVPoolValidatorCount was not called anywhere
            if (
                (firstFullDepSucceeded && !doBeacon[0]) &&
                (!(doBeacon[1] && !middlePartialFinalizeShouldFail && doBeacon[2]) ||
                    liq1Succeeded ||
                    !middlePartialDepSucceeded)
            ) {
                // Beacon0 (from earlier) was never called
                // AND (the partial deposit finalized properly and was registered
                //      OR the liquidation succeeded and the partial deposit never happened
                //      OR the partial deposit never happened for another reason)
                _noBeaconCorrection += 32 ether;
                console.log("<<<NBC Part 2a: Extra +32 ETH>>>");

                // // If the first deposit actually never happened, subtract 32 ether
                // if (!firstFullDepSucceeded) {
                //     // Remove the 32 ETH from above
                //     _noBeaconCorrection -= 32 ether;
                //     console.log("<<<NBC Part 2b: -32 ETH [1st full deposit never happened]>>>");
                // }
            }

            // If _beaconOracle_setVPoolValidatorCount was not called anywhere

            console.log("<<<NBC Total: +", _noBeaconCorrection / 1e18, "ETH>>>");
            // Check total ETH
            assertApproxEqRel(
                _ttlSystemEth + _noBeaconCorrection,
                300e18 + _depositAndDumpFzAmts[1],
                HALF_PCT_DELTA,
                "Total ETH in the contracts + EOAs + validators should be 300"
            );
        }

        // ======================== ACCRUE #3 ========================
        // Wait some time
        mineBlocksBySecond(_accrueFzTimes[2]);

        // Accrue some interest
        console.log("<<<Add interest>>>");
        lendingPool.addInterest(false);

        printAndReturnSystemStateInfo("======== AFTER THIRD ACCRUE ========", true);

        // ======================== VALIDATOR EXIT ========================
        console.log("<<<Exit all validators, beacon 0 validators but not the buffer>>>");
        vm.deal(validatorPoolAddress, validatorPoolAddress.balance + expectedExitEth);

        // Beacon
        {
            _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 0);
        }

        printAndReturnSystemStateInfo("======== AFTER EXITING THE VALIDATORS ========", true);

        // ======================== SECOND LIQUIDATION ATTEMPT ========================

        // Try liquidating if fuzzed
        if (tryLiquidations[1]) {
            (bool _wouldBeSolvent, uint256 _borrowAmt, ) = lendingPool.wouldBeSolvent(validatorPoolAddress, true, 0, 0);
            uint256 _amtToRepay = _borrowAmt > validatorPoolAddress.balance ? validatorPoolAddress.balance : _borrowAmt;

            console.log("<<<Attempting second liquidation, allowed to fail>>>");
            vm.prank(beaconOracleAddress);
            if (_wouldBeSolvent) {
                console.log("   ---> Expected to revert: Cannot liquidate because position is not insolvent");
                vm.expectRevert();
            }
            lendingPool.liquidate(validatorPoolAddress, _amtToRepay);

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();

            printAndReturnSystemStateInfo("======== AFTER SECOND LIQUIDATION ATTEMPT ========", true);
        }

        // ======================== REPAY REMAINING ========================
        // See how much you borrowed / you owe
        (, , , , , borrowAllowancesTracked[4], borrowSharesTemp) = lendingPool.validatorPoolAccounts(
            validatorPoolAddress
        );
        borrowAmountsTracked[4] = lendingPool.toBorrowAmount(borrowSharesTemp);

        // Find out how much the validator pool is missing for the repay
        {
            uint256 _amtNeededFinalRepay = 0;
            if (validatorPoolAddress.balance < borrowAmountsTracked[4]) {
                _amtNeededFinalRepay = borrowAmountsTracked[4] - validatorPoolAddress.balance;
            }

            // Transfer in ETH, if you can and the validator pool needs it
            vm.prank(validatorPoolOwner);
            if (_amtNeededFinalRepay > address(validatorPoolOwner).balance) {
                console.log("   ---> Expected to revert [_amtNeededFinalRepay > address(validatorPoolOwner).balance]");
                vm.expectRevert();
            }
            validatorPoolAddress.call{ value: _amtNeededFinalRepay }("");

            // Repay the remaining balance
            console.log("<<<Repay the remaining balance>>>");
            vm.prank(validatorPoolOwner);
            if (borrowAmountsTracked[4] > (address(validatorPoolOwner).balance + validatorPoolAddress.balance)) {
                console.log("   ---> Expected to revert, not enough ETH owned by VP owner + VP pool");
                vm.expectRevert();
            }
            validatorPool.repayWithPoolAndValue{ value: 0 }(borrowAmountsTracked[4]);

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();
        }

        printAndReturnSystemStateInfo("======== AFTER REMAINING REPAY ========", true);

        // ======================== REPAY BEACON ========================
        // See how much you borrowed / you owe
        console.log("<<<Checking to see if you repaid everything>>>");
        (, , , , , borrowAllowancesTracked[5], borrowSharesTemp) = lendingPool.validatorPoolAccounts(
            validatorPoolAddress
        );
        borrowAmountsTracked[5] = lendingPool.toBorrowAmount(borrowSharesTemp);

        if (borrowAmountsTracked[5] == 0) {
            console.log("<<<  ---> Everything repaid, beaconing now>>>");
            _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 0);
            _beaconOracle_setVPoolBorrowAllowanceManualBuffer(validatorPoolAddress, 0);
        }

        printAndReturnSystemStateInfo("======== AFTER POSSIBLE POST-REPAY BEACONING ========", true);

        // ======================== WITHDRAW #1 (PARTIAL) ========================
        // See how much you borrowed / you owe
        (, , , , , borrowAllowancesTracked[6], borrowSharesTemp) = lendingPool.validatorPoolAccounts(
            validatorPoolAddress
        );
        borrowAmountsTracked[6] = lendingPool.toBorrowAmount(borrowSharesTemp);

        // If you are trying to withdraw more than what the validator pool has, it will revert
        // Also revert if the repay above reverted
        if ((_repayWithdrawFzAmts[1] > validatorPoolAddress.balance)) {
            console.log("   ---> Expected to revert, trying to withdraw more than the VP pool has");
            vm.expectRevert();
        } else if (borrowAmountsTracked[5] > 0) {
            console.log("   ---> Expected to revert, still have an outstanding loan");
            vm.expectRevert();
        }
        console.log("<<<Withdrawing a partial amount>>>");
        vm.prank(validatorPoolOwner);
        validatorPool.withdraw(validatorPoolOwner, _repayWithdrawFzAmts[1]);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        printAndReturnSystemStateInfo("======== AFTER PARTIAL WITHDRAWAL ========", true);

        // ======================== WITHDRAW #2 (REMAINING AMOUNT) ========================
        // See how much you borrowed / you owe
        (, , , , , borrowAllowancesTracked[7], borrowSharesTemp) = lendingPool.validatorPoolAccounts(
            validatorPoolAddress
        );
        borrowAmountsTracked[7] = lendingPool.toBorrowAmount(borrowSharesTemp);

        // Do some checks
        console.log("<<<Withdrawing the remaining amount>>>");
        if (borrowAmountsTracked[7] > 0) {
            console.log("   ---> Expected to revert, still have an outstanding loan");
            vm.expectRevert();
        }

        // If you are trying to withdraw more than what the validator pool has, it will revert
        vm.prank(validatorPoolOwner);
        validatorPool.withdraw(validatorPoolOwner, validatorPoolAddress.balance);
        printAndReturnSystemStateInfo("======== AFTER REMAINING WITHDRAWAL ========", true);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // ======================== REDEEM REMAINING NFTS, IF APPLICABLE ========================

        // Request exits if you haven't done so already
        // ------------
        vm.stopPrank();
        vm.startPrank(testUserAddress);

        // Request to redeem REDEEM_0_AMT
        if (!redeemRequests[0]) {
            console.log("<<<Entering redemption queue for NFT #0>>>");
            console.log("   ---> REDEEM_0_AMT is %s (%e)", REDEEM_0_AMT, REDEEM_0_AMT);
            frxETH.approve(redemptionQueueAddress, REDEEM_0_AMT);
            rdmTcktNftIds[0] = redemptionQueue.enterRedemptionQueue(testUserAddress, REDEEM_0_AMT);
        }

        // Request to redeem REDEEM_1_AMT
        if (!redeemRequests[1]) {
            console.log("<<<Entering redemption queue for NFT #1>>>");
            console.log("   ---> REDEEM_1_AMT is %s (%e)", REDEEM_1_AMT, REDEEM_1_AMT);
            frxETH.approve(redemptionQueueAddress, REDEEM_1_AMT);
            rdmTcktNftIds[1] = redemptionQueue.enterRedemptionQueue(testUserAddress, REDEEM_1_AMT);
        }

        // Request to redeem any remaining frxETH you have
        uint120 _leftoverFrxEth = uint120(frxETH.balanceOf(testUserAddress));
        console.log("<<<Entering redemption queue for NFT #2>>>");
        console.log("   ---> _leftoverFrxEth is %s (%e)", _leftoverFrxEth, _leftoverFrxEth);
        frxETH.approve(redemptionQueueAddress, _leftoverFrxEth);
        rdmTcktNftIds[2] = redemptionQueue.enterRedemptionQueue(testUserAddress, _leftoverFrxEth);

        // Wait until they all mature
        mineBlocksBySecond(3 weeks);

        // Burn all of the NFTs

        // NFT #0
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(rdmTcktNftIds[0], 0, false);
        if (_isRedeemable) {
            // Shouldn't be able to redeem more than the max amount
            vm.expectRevert();
            redemptionQueue.partialRedeemNft(rdmTcktNftIds[0], testUserAddress, _maxAmountRedeemable + 1);

            // Should be able to partially redeem right below _maxAmountRedeemable
            redemptionQueue.canRedeem(rdmTcktNftIds[0], _maxAmountRedeemable - 1, true);

            // Do the redemption
            console.log("<<<Redeeming/burning NFT #0>>>");
            console.log("   ---> Amount is %s (%e) ETH", REDEEM_0_AMT, REDEEM_0_AMT);
            redemptionQueue.fullRedeemNft(rdmTcktNftIds[0], testUserAddress);
        }

        // NFT #1
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(rdmTcktNftIds[1], 0, false);
        if (_isRedeemable) {
            // Shouldn't be able to redeem more than the max amount
            vm.expectRevert();
            redemptionQueue.partialRedeemNft(rdmTcktNftIds[1], testUserAddress, _maxAmountRedeemable + 1);

            // Should be able to partially redeem right below _maxAmountRedeemable
            redemptionQueue.canRedeem(rdmTcktNftIds[1], _maxAmountRedeemable - 1, true);

            // Do the redemption
            console.log("<<<Redeeming/burning NFT #1>>>");
            console.log("   ---> Amount is %s (%e) ETH", REDEEM_1_AMT, REDEEM_1_AMT);
            redemptionQueue.fullRedeemNft(rdmTcktNftIds[1], testUserAddress);
        }

        // NFT #2
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(rdmTcktNftIds[2], 0, false);
        if (_isRedeemable) {
            // Shouldn't be able to redeem more than the max amount
            vm.expectRevert();
            redemptionQueue.partialRedeemNft(rdmTcktNftIds[2], testUserAddress, _maxAmountRedeemable + 1);

            // Should be able to partially redeem right below _maxAmountRedeemable
            redemptionQueue.canRedeem(rdmTcktNftIds[2], _maxAmountRedeemable - 1, true);

            // Do the redemption
            console.log("<<<Redeeming/burning NFT #2>>>");
            console.log("   ---> Amount is %s (%e) ETH", _leftoverFrxEth, _leftoverFrxEth);
            redemptionQueue.fullRedeemNft(rdmTcktNftIds[2], testUserAddress);
        }

        vm.stopPrank();

        printAndReturnSystemStateInfo("======== AFTER TRYING TO REDEEM ALL NFTS ========", true);

        // ======================== FINAL BALANCE CHECKS [PHASE 1]??? ========================
        {
            console.log("<<<Checking ETH sums>>>");
            uint256 _interestAccrued;
            (_interestAccrued, , totalNonValidatorEthSums[2], , totalSystemEthSums[2]) = printAndReturnSystemStateInfo(
                "======== FINAL BALANCE CHECKS ========",
                true
            );

            // Check ending vs starting balance. Should be the same except for the fuzzed ETH dump-in to the Ether Router
            assertApproxEqRel(
                totalSystemEthSums[0] + _depositAndDumpFzAmts[1],
                totalSystemEthSums[2],
                HALF_PCT_DELTA,
                "Total ETH in the contracts + EOAs + (exited) validators should be 300"
            );
        }

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();
    }
}
