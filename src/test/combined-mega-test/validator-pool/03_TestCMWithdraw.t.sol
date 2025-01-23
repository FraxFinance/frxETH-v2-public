// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./02_TestCMDeposit.t.sol";

contract TestCMWithdraw is CombinedMegaBaseTest, depositValidatorFunctions {
    using LendingPoolStructHelper for LendingPool;
    using RedemptionQueueStructHelper for FraxEtherRedemptionQueueV2;

    /// FEATURE: Users can eject validators and collect ether

    function setUp() public {
        /// BACKGROUND: All base contracts have been deployed and configured
        _defaultSetup();

        /// BACKGROUND: Beacon oracle has set the credit per validator to 28E
        console.log("<<<_beaconOracle_setVPoolCreditPerValidatorI48_E12>>>");
        _beaconOracle_setVPoolCreditPerValidatorI48_E12(validatorPoolAddress, 28e12);

        // Zero out any ETH and frxETH in the EtherRouter and CurveLsdAMO
        vm.deal(etherRouterAddress, 0);
        vm.deal(curveLsdAmoAddress, 0);

        // Test user deposits some ETH for frxETH
        console.log("<<<Test user deposits some ETH for frxETH>>>");
        vm.startPrank(testUserAddress);
        vm.deal(testUserAddress, 480 ether);
        fraxEtherMinter.mintFrxEth{ value: 480 ether }();
        vm.stopPrank();

        // Sweep 480 ETH to the Redemption Queue and/or Curve AMO(s)
        // This is to simulate mixed ETH in various places and force LP unwinding at the Curve AMO
        vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        console.log("<<<etherRouter.sweepEther>>>");
        etherRouter.sweepEther(480 ether, true); // Put in LP
        vm.stopPrank();

        // Give the validator pool owner 96 ETH
        vm.deal(validatorPoolOwner, 96 ether);

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

        /// Create 3 fully-funded validator deposits
        console.log("<<<3x _fullValidatorDeposit>>>");
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
        _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[2],
            _validatorSignature: validatorSignatures[2]
        });

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// GIVEN the beacon oracle has verified the deposits
        console.log("<<<_beaconOracle_setValidatorApproval>>>");
        _beaconOracle_setValidatorApproval(validatorPublicKeys[0], validatorPoolAddress, uint32(block.timestamp));
        _beaconOracle_setValidatorApproval(validatorPublicKeys[1], validatorPoolAddress, uint32(block.timestamp));
        _beaconOracle_setValidatorApproval(validatorPublicKeys[2], validatorPoolAddress, uint32(block.timestamp));

        /// GIVEN the beacon oracle has updated the count and allowance
        console.log("<<<_beaconOracle_setVPoolValidatorCount>>>");
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 3);
        _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);

        // Fetch all of the validator DepositInfo structs and do some checks
        console.log("<<<Check DepositInfos>>>");
        {
            LendingPool.ValidatorDepositInfo[] memory _vpkInfos = new LendingPool.ValidatorDepositInfo[](3);

            // Check the DepositInfo structs
            for (uint256 i = 0; i < 3; i++) {
                // Get the deposit info
                _vpkInfos[i] = lendingPool.__validatorDepositInfo(validatorPublicKeys[i]);

                /// THEN validator public key should be marked as approved
                assertTrue(
                    lendingPool.isValidatorApproved(validatorPublicKeys[i]),
                    "Validator pubkey should be marked as approved"
                );

                /// THEN validator public key should be marked as wasFullDepositOrFinalized
                assertTrue(
                    _vpkInfos[i].wasFullDepositOrFinalized,
                    "Validator pubkey should be marked as being a full deposit and/or finalized"
                );
            }
        }
        console.log("<<<DepositInfos checked>>>");
    }

    function doABorrowAndWait(uint256 _borrowAmount) public {
        // Do the borrow
        vm.prank(validatorPoolOwner);
        console.log("<<<Do the borrow>>>");
        validatorPool.borrow(validatorPoolOwner, _borrowAmount);

        // Wait 5 days to earn some interest
        console.log("<<<Wait>>>");
        mineBlocksBySecond(5 days);

        // Accrue some interest
        console.log("<<<Add interest>>>");
        lendingPool.addInterest(false);
    }

    function testFuzz_doABorrowAndWait(uint256 _borrowAmount) public {
        // Will fail otherwise due to MINIMUM_BORROW_AMOUNT
        vm.assume(_borrowAmount > 1000 gwei);

        // Test borrow conditions
        if (_borrowAmount > 82.5 ether) vm.expectRevert();
        doABorrowAndWait(_borrowAmount);
    }

    function test_Withdraw3ExitClean() public {
        console.log("======== [W3EXCLN] START  ========");
        uint256 _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
        console.log("_borrowShares (in shares): ", _borrowShares);
        console.log("_borrowShares (in ETH): ", lendingPool.toBorrowAmount(_borrowShares));
        console.log("ValidatorPool ETH balance: ", validatorPoolAddress.balance);
        console.log("TU (Test User) ETH balance: ", testUserAddress.balance);

        // Borrow 80 ETH, close to the max of ((28 - 0.5 buffer) * 3) = 82.5
        doABorrowAndWait(80 ether);

        console.log("======== [W3EXCLN] AFTER BORROW AND WAIT  ========");
        _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
        console.log("_borrowShares (in shares): ", _borrowShares);
        console.log("_borrowShares (in ETH): ", lendingPool.toBorrowAmount(_borrowShares));
        console.log("ValidatorPool ETH balance: ", validatorPoolAddress.balance);
        console.log("TU (Test User) ETH balance: ", testUserAddress.balance);

        // Trigger 3 validators to exit
        // Done off-chain

        // Wait 3 days for the exit
        console.log("<<<Wait>>>");
        mineBlocksBySecond(3 days);

        // Accrue some interest
        console.log("<<<Add interest>>>");
        lendingPool.addInterest(false);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Try to set the validator pool as a random person (should fail)
        hoax(address(0x123456));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS,
                address(0x123456)
            )
        );
        lendingPool.setVPoolWithdrawalFee(3000);

        // Try to set the validator pool withdrawal fee to 5% (should fail due to being too high)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("ExceedsMaxWithdrawalFee(uint256,uint256)", 50_000, 3000));
        lendingPool.setVPoolWithdrawalFee(50_000);

        // 96 ETH from the exit is dumped into the validator pool
        vm.deal(validatorPoolAddress, 96 ether);

        vm.startPrank(validatorPoolOwner);

        // Try to withdraw before repaying (should fail)
        console.log("<<<Withdraw>>>");
        try validatorPool.withdraw(validatorPoolOwner, validatorPoolAddress.balance) {
            revert("Should not have succeeded");
        } catch (bytes memory reason) {
            assertEq(LendingPoolCore.BorrowBalanceMustBeZero.selector, bytes4(reason));
        }

        // Print accounting
        console.log("======== [W3EXCLN] BEFORE REPAYMENT  ========");
        _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
        console.log("_borrowShares (in shares): ", _borrowShares);
        console.log("_borrowShares (in ETH): ", lendingPool.toBorrowAmount(_borrowShares));
        console.log("ValidatorPool ETH balance: ", validatorPoolAddress.balance);
        console.log("TU (Test User) ETH balance: ", testUserAddress.balance);

        // Repay loans
        console.log("<<<Repay shares>>>");
        validatorPool.repayShares(_borrowShares);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Print accounting
        console.log("======== [W3EXCLN] AFTER REPAYMENT  ========");
        _borrowShares = lendingPool.__validatorPoolAccounts(validatorPoolAddress).borrowShares;
        console.log("_borrowShares (in shares): ", _borrowShares);
        console.log("_borrowShares (in ETH): ", lendingPool.toBorrowAmount(_borrowShares));
        console.log("ValidatorPool ETH balance: ", validatorPoolAddress.balance);
        console.log("TU (Test User) ETH balance: ", testUserAddress.balance);

        // Withdraw remaining crumbs
        console.log("<<<Withdraw>>>");
        validatorPool.withdraw(validatorPoolOwner, validatorPoolAddress.balance);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        /// GIVEN the beacon oracle has updated the count and allowance
        vm.stopPrank();
        console.log("<<<_beaconOracle_setVPoolValidatorCount>>>");
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 0);
        _beaconOracle_setVPoolBorrowAllowanceWithBuffer(validatorPoolAddress);
        vm.startPrank(validatorPoolOwner);

        // Check the sum of all of the ETH not in validators
        (totalNonValidatorEthSums[1], totalSystemEthSums[1]) = checkTotalSystemEth(
            "======== AFTER WITHDRAWAL ========",
            480 ether
        );

        // Wind down the test user
        windDown(480 ether, totalNonValidatorEthSums[1]);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();
    }
}
