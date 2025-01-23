// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "../CombinedMegaBaseTest.t.sol";
import "../../SharedBaseTestState.t.sol";
import { SafeCastLibrary } from "../../../contracts/libraries/SafeCastLibrary.sol";

abstract contract beaconOracleFunctions is SharedBaseTestState {
    using SafeCastLibrary for int128; // Compiler complained about the comma in `using SafeCastLibrary for int128, uint256;`
    using SafeCastLibrary for uint256;

    function _beaconOracle_setVPoolCreditPerValidatorI48_E12(
        address _validatorPoolAddress,
        uint48 _creditPerValidatorI48_E12
    ) public {
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolCreditPerValidatorI48_E12(_validatorPoolAddress, _creditPerValidatorI48_E12);
    }

    function _beaconOracle_setValidatorApproval(
        bytes memory _validatorPublicKey,
        address _validatorPoolAddress,
        uint32 _approvalTime
    ) public {
        // Fetch the last withdrawal timestamp
        uint32 _lastWithdrawalTimestamp = lendingPool.getLastWithdrawalTimestamp(_validatorPoolAddress);

        // Set the approval
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setValidatorApproval(
            _validatorPublicKey,
            _validatorPoolAddress,
            _approvalTime,
            _lastWithdrawalTimestamp
        );
    }

    function _beaconOracle_setValidatorApprovals(
        bytes[] memory _validatorPublicKeys,
        address[] memory _validatorPoolAddresses,
        uint32[] memory _approvalTimes
    ) public {
        // Fetch the last withdrawal timestamp
        uint32[] memory _lastWithdrawalTimestamps = lendingPool.getLastWithdrawalTimestamps(_validatorPoolAddresses);

        // Set the approvals
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setValidatorApprovals(
            _validatorPublicKeys,
            _validatorPoolAddresses,
            _approvalTimes,
            _lastWithdrawalTimestamps
        );
    }

    function _beaconOracle_setVPoolValidatorCount(address _validatorPoolAddress, uint32 _newValidatorCount) public {
        // Fetch the last withdrawal timestamp
        uint32 _lastWithdrawalTimestamp = lendingPool.getLastWithdrawalTimestamp(_validatorPoolAddress);

        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolValidatorCount(_validatorPoolAddress, _newValidatorCount, _lastWithdrawalTimestamp);
    }

    function _beaconOracle_setVPoolValidatorCountAndBorrowAllowanceWithBuffer(
        address _validatorPoolAddress,
        uint32 _newValidatorCount,
        uint128 _bufferAmount
    ) public returns (uint128 _newBorrowAllowance) {
        // Get the borrow allowance
        (, , , , uint48 _creditPerValidatorI48_E12, , uint256 _borrowShares) = lendingPool.validatorPoolAccounts(
            _validatorPoolAddress
        );
        uint256 _borrowAmount = lendingPool.toBorrowAmount(_borrowShares);

        // Accounts for existing borrow. Use 5e17 as the buffer as in _beaconOracle_setVPoolBorrowAllowanceWithBuffer
        // Also use the _newValidatorCount
        uint128 _credit = uint128(_newValidatorCount * ((uint128(_creditPerValidatorI48_E12) * (1e6)) - _bufferAmount));
        console.log("_credit: ", _credit);
        console.log("_borrowAmount: ", _borrowAmount);
        _newBorrowAllowance = _credit - uint128(_borrowAmount);
        console.log("_newBorrowAllowance: ", _newBorrowAllowance);

        // Fetch the last withdrawal timestamp
        uint32 _lastWithdrawalTimestamp = lendingPool.getLastWithdrawalTimestamp(_validatorPoolAddress);

        // Set the validator count and borrow allowance
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolValidatorCountAndBorrowAllowance(
            _validatorPoolAddress,
            _newValidatorCount,
            _newBorrowAllowance,
            _lastWithdrawalTimestamp
        );
    }

    function _beaconOracle_setVPoolValidatorCountAndBorrowAllowanceManual(
        address _validatorPoolAddress,
        uint32 _newValidatorCount,
        uint128 _newBorrowAllowance
    ) public {
        // Fetch the last withdrawal timestamp
        uint32 _lastWithdrawalTimestamp = lendingPool.getLastWithdrawalTimestamp(validatorPoolAddress);

        // Set the validator count and borrow allowance
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolValidatorCountAndBorrowAllowance(
            _validatorPoolAddress,
            _newValidatorCount,
            _newBorrowAllowance,
            _lastWithdrawalTimestamp
        );
    }

    function _beaconOracle_setVPoolBorrowAllowanceManualBuffer(
        address _validatorPoolAddress,
        uint256 _bufferAmt
    ) public returns (uint128 _newBorrowAllowance) {
        (, , , uint32 _validatorCount, uint48 _creditPerValidatorI48_E12, , uint256 _borrowShares) = lendingPool
            .validatorPoolAccounts(_validatorPoolAddress);
        uint256 _borrowAmount = lendingPool.toBorrowAmount(_borrowShares);

        // Accounts for existing borrow
        _newBorrowAllowance = uint128(
            _validatorCount * ((uint128(_creditPerValidatorI48_E12) * 1e6) - _bufferAmt) - _borrowAmount
        );

        // Fetch the last withdrawal timestamp
        uint32 _lastWithdrawalTimestamp = lendingPool.getLastWithdrawalTimestamp(_validatorPoolAddress);

        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolBorrowAllowance(_validatorPoolAddress, _newBorrowAllowance, _lastWithdrawalTimestamp);
    }

    function _beaconOracle_setVPoolBorrowAllowanceWithBuffer(
        address _validatorPoolAddress
    ) public returns (uint256 _newBorrowAllowance) {
        // 0.5 ether buffer so that people dont get immediately liquidated
        _beaconOracle_setVPoolBorrowAllowanceManualBuffer(_validatorPoolAddress, 5e17);
    }

    function _beaconOracle_setVPoolBorrowAllowanceNoBuffer(
        address _validatorPoolAddress
    ) public returns (uint128 _newBorrowAllowance) {
        (, , , uint32 _validatorCount, uint48 _creditPerValidatorI48_E12, , uint256 _borrowShares) = lendingPool
            .validatorPoolAccounts(_validatorPoolAddress);
        uint256 _borrowAmount = lendingPool.toBorrowAmount(_borrowShares);

        // Fetch the last withdrawal timestamp
        uint32 _lastWithdrawalTimestamp = lendingPool.getLastWithdrawalTimestamp(_validatorPoolAddress);

        // No buffer here
        // Accounts for existing borrow
        uint128 _creditAmt = uint128(_validatorCount) * (uint128(_creditPerValidatorI48_E12) * 1e6);
        if (uint128(_borrowAmount) > _creditAmt) _newBorrowAllowance = 0;
        else _newBorrowAllowance = _creditAmt - uint128(_borrowAmount);

        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolBorrowAllowance(_validatorPoolAddress, _newBorrowAllowance, _lastWithdrawalTimestamp);
    }
}

abstract contract depositValidatorFunctions is beaconOracleFunctions {
    function _partialValidatorDeposit(
        ValidatorPool _validatorPool,
        bytes memory _validatorPublicKey,
        bytes memory _validatorSignature,
        uint256 _depositAmount
    ) public returns (DepositCredentials memory _depositCredentials) {
        // make credentials
        _depositCredentials = generateDepositCredentials(
            _validatorPool,
            _validatorPublicKey,
            _validatorSignature,
            _depositAmount
        );

        // Simulate a partial deposit event
        vm.startPrank(validatorPoolOwner);
        _validatorPool.deposit{ value: _depositAmount }(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );
        vm.stopPrank();
    }

    function _requestFinalValidatorDeposit() public {
        _requestFinalValidatorDepositByPkeyIdx(0);
    }

    function _requestFinalValidatorDepositByPkeyIdx(uint256 pkeyIdx) public {
        DepositCredentials memory _finalDepositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[pkeyIdx],
            validatorSignatures[pkeyIdx],
            32 ether - PARTIAL_DEPOSIT_AMOUNT
        );

        // requestFinalDeposit
        vm.startPrank(validatorPoolOwner);
        console.log("<<<requestFinalDeposit starting for pkey idx: %s>>>", pkeyIdx);
        validatorPool.requestFinalDeposit(
            _finalDepositCredentials.publicKey,
            _finalDepositCredentials.signature,
            _finalDepositCredentials.depositDataRoot
        );
        console.log("<<<requestFinalDeposit completed for pkey idx: %s>>>", pkeyIdx);
        vm.stopPrank();
    }

    function _fullValidatorDeposit(
        ValidatorPool _validatorPool,
        bytes memory _validatorPublicKey,
        bytes memory _validatorSignature
    ) public returns (DepositCredentials memory _depositCredentials) {
        uint256 depositAmount = 32 ether;
        _depositCredentials = generateDepositCredentials(
            _validatorPool,
            _validatorPublicKey,
            _validatorSignature,
            depositAmount
        );

        // Simulate a deposit event to lendingPool
        vm.startPrank(validatorPoolOwner);
        console.log("<<<deposit starting [in _fullValidatorDeposit]>>>");
        _validatorPool.deposit{ value: 32 ether }(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );
        console.log("<<<deposit completed [in _fullValidatorDeposit]>>>");
        vm.stopPrank();
    }
}

contract TestCMDeposit is CombinedMegaBaseTest, beaconOracleFunctions, depositValidatorFunctions {
    /// FEATURE: Deposit ether for validators

    DeltaValidatorDepositInfoSnapshot _firstDeltaValidatorDepositInfo;

    event DepositEvent(bytes pubkey, bytes withdrawal_credentials, bytes amount, bytes signature, bytes index);

    function setUp() public {
        /// BACKGROUND: All base contracts have been deployed and configured
        /// Validator Pool has been created, and Curve
        _defaultSetup();

        /// BACKGROUND: Beacon oracle has set the credit per validator to 28E
        _beaconOracle_setVPoolCreditPerValidatorI48_E12(validatorPoolAddress, 28e12);
    }

    function _quickDepositWithdraw(uint256 _pkeyIdx) internal {
        // Make a full deposit
        DepositCredentials memory _depositCredentials = _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[_pkeyIdx],
            _validatorSignature: validatorSignatures[_pkeyIdx]
        });

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Simulate dropping in 32 ETH from an immediate exit
        vm.deal(validatorPoolAddress, validatorPoolAddress.balance + (32 ether));

        // Withdraw everything
        hoax(validatorPoolOwner);
        validatorPool.withdraw(validatorPoolOwner, validatorPoolAddress.balance);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();
    }

    function test_MiscDepositFails() public {
        vm.startPrank(validatorPoolOwner);

        // Generate deposit credentials
        DepositCredentials memory _depositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[0],
            validatorSignatures[0],
            32 ether
        );

        // Simulate a deposit event (will fail as deposit amount is not an integer)
        vm.expectRevert(abi.encodeWithSignature("MustBeIntegerMultipleOf1Eth()"));
        validatorPool.deposit{ value: 15.5 ether }(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );

        vm.stopPrank();
    }

    function test_TryDoublePartialsInARow() public {
        vm.startPrank(validatorPoolOwner);

        // =================================================
        // ================== Validator 1 ==================
        // =================================================

        // Generate deposit credentials for 1 ether
        DepositCredentials memory _depositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[0],
            validatorSignatures[0],
            1 ether
        );

        // Partial deposit 1 ether
        validatorPool.deposit{ value: 1 ether }(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );

        // Approve the validator
        vm.stopPrank();
        _beaconOracle_setValidatorApproval(validatorPublicKeys[0], validatorPoolAddress, uint32(block.timestamp));
        vm.startPrank(validatorPoolOwner);

        // Regenerate deposit credentials for 31 ether
        _depositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[0],
            validatorSignatures[0],
            31 ether
        );

        // Request a final deposit.
        // Should fail because they can only have 28 ETH credit per validator and thus need 3 more ETH.
        vm.expectRevert(
            abi.encodeWithSignature("ValidatorPoolIsNotSolventDetailed(uint256,uint256)", 31 ether, 28 ether)
        );
        validatorPool.requestFinalDeposit(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );

        // Regenerate deposit credentials for 3 ether this time
        _depositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[0],
            validatorSignatures[0],
            3 ether
        );

        // Partial deposit 3 ether
        validatorPool.deposit{ value: 3 ether }(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );

        // Regenerate deposit credentials for the remaining 28 ether
        _depositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[0],
            validatorSignatures[0],
            28 ether
        );

        // Request a final deposit. Should succeed now
        validatorPool.requestFinalDeposit(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );

        // =================================================
        // ================== Validator 2 ==================
        // =================================================
        // Start again for a 2nd validator

        // Generate deposit credentials for 1 ether
        _depositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[1],
            validatorSignatures[1],
            1 ether
        );

        // Partial deposit 1 ether
        validatorPool.deposit{ value: 1 ether }(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );

        // Approve the validator
        vm.stopPrank();
        _beaconOracle_setValidatorApproval(validatorPublicKeys[1], validatorPoolAddress, uint32(block.timestamp));
        vm.startPrank(validatorPoolOwner);

        // Regenerate deposit credentials for 31 ether
        _depositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[1],
            validatorSignatures[1],
            31 ether
        );

        // Request a final deposit.
        // Should fail because they can only have 28 ETH credit per validator and thus need 3 more ETH.
        vm.expectRevert(
            abi.encodeWithSignature("ValidatorPoolIsNotSolventDetailed(uint256,uint256)", 59 ether, 28 ether)
        );
        validatorPool.requestFinalDeposit(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );

        // Regenerate deposit credentials for 3 ether this time
        _depositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[1],
            validatorSignatures[1],
            3 ether
        );

        // Partial deposit 3 ether
        validatorPool.deposit{ value: 3 ether }(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );

        // Regenerate deposit credentials for the remaining 28 ether
        _depositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[1],
            validatorSignatures[1],
            28 ether
        );

        // Request a final deposit.
        // Should fail because they can only have 28 ETH credit per validator and thus need 3 more ETH.
        // The beacon did not update the previous one yet.
        vm.expectRevert(
            abi.encodeWithSignature("ValidatorPoolIsNotSolventDetailed(uint256,uint256)", 56 ether, 28 ether)
        );
        validatorPool.requestFinalDeposit(
            _depositCredentials.publicKey,
            _depositCredentials.signature,
            _depositCredentials.depositDataRoot
        );

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        vm.stopPrank();
    }

    function test_SetValidatorApprovals() public {
        // Set arrays
        bytes[] memory vPkeysTmpArr = new bytes[](1);
        vPkeysTmpArr[0] = validatorPublicKeys[0];
        address[] memory vpAddrTmpArr = new address[](1);
        vpAddrTmpArr[0] = validatorPoolAddress;
        uint32[] memory whenApprovedTmpArr = new uint32[](1);
        whenApprovedTmpArr[0] = uint32(block.timestamp);
        uint32[] memory lwTimestampTmpArr = lendingPool.getLastWithdrawalTimestamps(vpAddrTmpArr);

        // Do a quick deposit
        DepositCredentials memory _depositCredentials = _partialValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0],
            _depositAmount: PARTIAL_DEPOSIT_AMOUNT
        });

        // Try to set the validator approval with the wrong associated validator pool (should revert)
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("ValidatorPoolKeyMismatch()"));
        beaconOracle.setValidatorApproval(
            vPkeysTmpArr[0],
            testUserAddress,
            whenApprovedTmpArr[0],
            lwTimestampTmpArr[0]
        );

        // Set the validator approval correctly
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setValidatorApproval(
            vPkeysTmpArr[0],
            validatorPoolAddress,
            whenApprovedTmpArr[0],
            lwTimestampTmpArr[0]
        );

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // lastWithdrawalTimestamp fail tests
        // ------------------------------------------------------

        // Fetch the last withdrawal timestamp before the deposit
        uint32 _lastWithdrawalTimestampBefore = lendingPool.getLastWithdrawalTimestamp(validatorPoolAddress);
        lwTimestampTmpArr[0] = _lastWithdrawalTimestampBefore;

        // Do a quick deposit, then exit, then withdraw immediately
        _quickDepositWithdraw(1);

        // Fetch the last withdrawal timestamp after the deposit
        uint32 _lastWithdrawalTimestampAfter = lendingPool.getLastWithdrawalTimestamp(validatorPoolAddress);

        // Try setting validator pool approval (single validator method) [should fail]
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "WithdrawalTimestampMismatch(uint32,uint32)",
                _lastWithdrawalTimestampBefore,
                _lastWithdrawalTimestampAfter
            )
        );
        beaconOracle.setValidatorApproval(
            vPkeysTmpArr[0],
            vpAddrTmpArr[0],
            whenApprovedTmpArr[0],
            lwTimestampTmpArr[0]
        );

        // Try setting validator pool approval (validator array method) [should fail]
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "WithdrawalTimestampMismatch(uint32,uint32)",
                _lastWithdrawalTimestampBefore,
                _lastWithdrawalTimestampAfter
            )
        );
        beaconOracle.setValidatorApprovals(vPkeysTmpArr, vpAddrTmpArr, whenApprovedTmpArr, lwTimestampTmpArr);
    }

    function test_SetValidatorPoolCreditsPerValidator() public {
        // Set temporary vars
        address[] memory vpAddrTmpArr = new address[](1);
        vpAddrTmpArr[0] = payable(validatorPoolAddress);
        uint48[] memory nvcrdTmpArr = new uint48[](1);
        nvcrdTmpArr[0] = 24e12;

        // Set validator pool credits per validator (single validator method)
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolCreditPerValidatorI48_E12(payable(validatorPoolAddress), nvcrdTmpArr[0]);

        // Set validator pool credits per validator (validator array method)
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolCreditsPerValidator(vpAddrTmpArr, nvcrdTmpArr);

        // Try setting validator pool credits per validator as a random person (single validator method) [should fail]
        vm.prank(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        beaconOracle.setVPoolCreditPerValidatorI48_E12(payable(validatorPoolAddress), nvcrdTmpArr[0]);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Try setting validator pool credits per validator as a random person (validator array method) [should fail]
        vm.prank(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        beaconOracle.setVPoolCreditsPerValidator(vpAddrTmpArr, nvcrdTmpArr);
    }

    function test_InvalidValidatorPool() public {
        // Try to repay to an invalid pool (should fail)
        vm.expectRevert(abi.encodeWithSignature("InvalidValidatorPool()"));
        lendingPool.repay{ value: 1 ether }(address(123_456));
    }

    function test_ValidatorNotInitialized() public {
        // Try to finalize an uninitialized validator (should fail)
        vm.expectRevert(abi.encodeWithSignature("ValidatorIsNotInitialized()"));
        // bytes memory _tempBytes = "";
        lendingPool.finalDepositValidator("", "", "", bytes32(0));
    }

    function test_SetValidatorPoolValidatorCounts() public {
        // Set temporary vars
        address[] memory vpAddrTmpArr = new address[](1);
        vpAddrTmpArr[0] = payable(validatorPoolAddress);
        uint32[] memory nvcTmpArr = new uint32[](1);
        nvcTmpArr[0] = 1;
        uint32[] memory lwTimestampTmpArr = lendingPool.getLastWithdrawalTimestamps(vpAddrTmpArr);

        // Set validator pool validator counts (single validator method)
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolValidatorCount(payable(validatorPoolAddress), nvcTmpArr[0], lwTimestampTmpArr[0]);

        // Set validator pool validator counts (validator array method)
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolValidatorCounts(vpAddrTmpArr, nvcTmpArr, lwTimestampTmpArr);

        // Try setting validator pool validator counts as a random person (single validator method) [should fail]
        vm.prank(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        beaconOracle.setVPoolValidatorCount(payable(validatorPoolAddress), nvcTmpArr[0], lwTimestampTmpArr[0]);

        // Try setting validator pool validator counts as a random person (validator array method) [should fail]
        vm.prank(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        beaconOracle.setVPoolValidatorCounts(vpAddrTmpArr, nvcTmpArr, lwTimestampTmpArr);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // lastWithdrawalTimestamp fail tests
        // ------------------------------------------------------

        // Fetch the last withdrawal timestamp before the deposit
        uint32 _lastWithdrawalTimestampBefore = lendingPool.getLastWithdrawalTimestamp(validatorPoolAddress);
        lwTimestampTmpArr[0] = _lastWithdrawalTimestampBefore;

        // Do a quick deposit, then exit, then withdraw immediately
        _quickDepositWithdraw(0);

        // Fetch the last withdrawal timestamp after the deposit
        uint32 _lastWithdrawalTimestampAfter = lendingPool.getLastWithdrawalTimestamp(validatorPoolAddress);

        // Try setting validator pool validator count (single validator method) [should fail]
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "WithdrawalTimestampMismatch(uint32,uint32)",
                _lastWithdrawalTimestampBefore,
                _lastWithdrawalTimestampAfter
            )
        );
        beaconOracle.setVPoolValidatorCount(payable(validatorPoolAddress), nvcTmpArr[0], lwTimestampTmpArr[0]);

        // Try setting validator pool validator count (validator array method) [should fail]
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "WithdrawalTimestampMismatch(uint32,uint32)",
                _lastWithdrawalTimestampBefore,
                _lastWithdrawalTimestampAfter
            )
        );
        beaconOracle.setVPoolValidatorCounts(vpAddrTmpArr, nvcTmpArr, lwTimestampTmpArr);
    }

    function test_SetValidatorBorrowAllowances() public {
        // Set temporary vars
        address[] memory vpAddrTmpArr = new address[](1);
        vpAddrTmpArr[0] = payable(validatorPoolAddress);
        uint128[] memory nbaTmpArr = new uint128[](1);
        nbaTmpArr[0] = 12 ether;
        uint32[] memory lwTimestampTmpArr = lendingPool.getLastWithdrawalTimestamps(vpAddrTmpArr);

        // Set one validator pool so the Borrow Allowance calls don't prematurely fail
        _beaconOracle_setVPoolValidatorCount(validatorPoolAddress, 1);
        _beaconOracle_setVPoolCreditPerValidatorI48_E12(payable(validatorPoolAddress), 24e12);

        // Set validator pool borrow allowances (single validator method)
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolBorrowAllowance(payable(validatorPoolAddress), nbaTmpArr[0], lwTimestampTmpArr[0]);

        // Set validator pool borrow allowances (single validator method, incorrect borrow allowance so it will fail)
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("IncorrectBorrowAllowance(uint256,uint256)", 24 ether, 55 ether));
        beaconOracle.setVPoolBorrowAllowance(payable(validatorPoolAddress), 55 ether, lwTimestampTmpArr[0]);

        // Set validator pool borrow allowances (validator array method)
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolBorrowAllowances(vpAddrTmpArr, nbaTmpArr, lwTimestampTmpArr);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Try setting validator pool borrow allowances as a random person (single validator method) [should fail]
        vm.prank(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        beaconOracle.setVPoolBorrowAllowance(payable(validatorPoolAddress), nbaTmpArr[0], lwTimestampTmpArr[0]);

        // Try setting validator pool borrow allowances as a random person (validator array method) [should fail]
        vm.prank(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        beaconOracle.setVPoolBorrowAllowances(vpAddrTmpArr, nbaTmpArr, lwTimestampTmpArr);

        // lastWithdrawalTimestamp fail tests
        // ------------------------------------------------------

        // Fetch the last withdrawal timestamp before the deposit
        uint32 _lastWithdrawalTimestampBefore = lendingPool.getLastWithdrawalTimestamp(validatorPoolAddress);
        lwTimestampTmpArr[0] = _lastWithdrawalTimestampBefore;

        // Do a quick deposit, then exit, then withdraw immediately
        _quickDepositWithdraw(0);

        // Fetch the last withdrawal timestamp after the deposit
        uint32 _lastWithdrawalTimestampAfter = lendingPool.getLastWithdrawalTimestamp(validatorPoolAddress);

        // Try setting validator pool borrow allowances (single validator method) [should fail]
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "WithdrawalTimestampMismatch(uint32,uint32)",
                _lastWithdrawalTimestampBefore,
                _lastWithdrawalTimestampAfter
            )
        );
        beaconOracle.setVPoolBorrowAllowance(payable(validatorPoolAddress), nbaTmpArr[0], lwTimestampTmpArr[0]);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Try setting validator pool borrow allowances (validator array method) [should fail]
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "WithdrawalTimestampMismatch(uint32,uint32)",
                _lastWithdrawalTimestampBefore,
                _lastWithdrawalTimestampAfter
            )
        );
        beaconOracle.setVPoolBorrowAllowances(vpAddrTmpArr, nbaTmpArr, lwTimestampTmpArr);
    }

    function test_SetValidatorPoolValidatorCountsAndBorrowAllowances() public {
        // Set temporary vars
        address[] memory vpAddrTmpArr = new address[](1);
        vpAddrTmpArr[0] = payable(validatorPoolAddress);
        uint32[] memory nvcTmpArr = new uint32[](1);
        nvcTmpArr[0] = 1;
        uint128[] memory nbaTmpArr = new uint128[](1);
        nbaTmpArr[0] = 12 ether;
        uint32[] memory lwTimestampTmpArr = lendingPool.getLastWithdrawalTimestamps(vpAddrTmpArr);

        // Set validator pool validator counts & borrow allowances (single validator method)
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolValidatorCountAndBorrowAllowance(
            payable(validatorPoolAddress),
            nvcTmpArr[0],
            nbaTmpArr[0],
            lwTimestampTmpArr[0]
        );

        // Set validator pool validator counts & borrow allowances (validator array method)
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        beaconOracle.setVPoolValidatorCountsAndBorrowAllowances(vpAddrTmpArr, nvcTmpArr, nbaTmpArr, lwTimestampTmpArr);

        // Try setting validator pool validator counts & borrow allowances as a random person (single validator method) [should fail]
        vm.prank(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        beaconOracle.setVPoolValidatorCountAndBorrowAllowance(
            payable(validatorPoolAddress),
            nvcTmpArr[0],
            nbaTmpArr[0],
            lwTimestampTmpArr[0]
        );

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Try setting validator pool validator counts & borrow allowances as a random person (validator array method) [should fail]
        vm.prank(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        beaconOracle.setVPoolValidatorCountsAndBorrowAllowances(vpAddrTmpArr, nvcTmpArr, nbaTmpArr, lwTimestampTmpArr);

        // Do some other checks
        LendingPoolCore.ValidatorPoolAccount memory _vPoolAccount = lendingPool.previewValidatorAccounts(
            validatorPoolAddress
        );
        assertEq(_vPoolAccount.isInitialized, true, "_vPoolAccount.isInitialized");
        assertEq(_vPoolAccount.wasLiquidated, false, "_vPoolAccount.wasLiquidated");
        assertEq(_vPoolAccount.validatorCount, 1, "_vPoolAccount.validatorCount");
        assertEq(_vPoolAccount.creditPerValidatorI48_E12, 28e12, "_vPoolAccount.creditPerValidatorI48_E12");
        assertEq(_vPoolAccount.borrowAllowance, 12e18, "_vPoolAccount.borrowAllowance");
        assertEq(_vPoolAccount.borrowShares, 0, "_vPoolAccount.borrowShares");

        // lastWithdrawalTimestamp fail tests
        // ------------------------------------------------------

        // Fetch the last withdrawal timestamp before the deposit
        uint32 _lastWithdrawalTimestampBefore = lendingPool.getLastWithdrawalTimestamp(validatorPoolAddress);
        lwTimestampTmpArr[0] = _lastWithdrawalTimestampBefore;

        // Do a quick deposit, then exit, then withdraw immediately
        _quickDepositWithdraw(0);

        // Fetch the last withdrawal timestamp after the deposit
        uint32 _lastWithdrawalTimestampAfter = lendingPool.getLastWithdrawalTimestamp(validatorPoolAddress);

        // Try setting validator pool validator counts & borrow allowances (single validator method) [should fail]
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "WithdrawalTimestampMismatch(uint32,uint32)",
                _lastWithdrawalTimestampBefore,
                _lastWithdrawalTimestampAfter
            )
        );
        beaconOracle.setVPoolValidatorCountAndBorrowAllowance(
            payable(validatorPoolAddress),
            nvcTmpArr[0],
            nbaTmpArr[0],
            lwTimestampTmpArr[0]
        );

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Try setting validator pool validator counts & borrow allowances (validator array method) [should fail]
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "WithdrawalTimestampMismatch(uint32,uint32)",
                _lastWithdrawalTimestampBefore,
                _lastWithdrawalTimestampAfter
            )
        );
        beaconOracle.setVPoolValidatorCountsAndBorrowAllowances(vpAddrTmpArr, nvcTmpArr, nbaTmpArr, lwTimestampTmpArr);

        // Do some other checks
        _vPoolAccount = lendingPool.previewValidatorAccounts(validatorPoolAddress);
        assertEq(_vPoolAccount.isInitialized, true, "_vPoolAccount.isInitialized");
        assertEq(_vPoolAccount.wasLiquidated, false, "_vPoolAccount.wasLiquidated");
        assertEq(_vPoolAccount.validatorCount, 1, "_vPoolAccount.validatorCount");
        assertEq(_vPoolAccount.creditPerValidatorI48_E12, 28e12, "_vPoolAccount.creditPerValidatorI48_E12");
        assertEq(_vPoolAccount.borrowAllowance, 0, "_vPoolAccount.borrowAllowance");
        assertEq(_vPoolAccount.borrowShares, 0, "_vPoolAccount.borrowShares");
    }

    function test_SetCreationCode() public {
        // Set the validator pool creation code
        vm.prank(Constants.Mainnet.TIMELOCK_ADDRESS);
        lendingPool.setCreationCode(hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

        // Try setting the validator pool creation code as a random person [should fail]
        vm.prank(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS,
                testUserAddress
            )
        );
        lendingPool.setCreationCode(hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
    }

    function test_InitialCurveAmoAccounting() public {
        // Call for coverage
        lendingPool.previewAddInterest();

        // Check showAllocations
        {
            uint256[10] memory allocations = amoHelper.showAllocations(curveLsdAmoAddress);
            // console.log("Deposit Allocations [2]: Total frxETH deposited into Pools: ", allocations[2]);
            // console.log("Deposit Allocations [3]: Total ETH + WETH deposited into Pools: ", allocations[3]);
            // console.log("Deposit Allocations [4]: Total withdrawable frxETH from LPs as ONE COIN: ", allocations[4]);
            // console.log("Deposit Allocations [5]: Total withdrawable ETH from LPs as ONE COIN: ", allocations[5]);
            // console.log("Deposit Allocations [6]: Total withdrawable frxETH from LPs as BALANCED: ", allocations[6]);
            // console.log("Deposit Allocations [7]: Total withdrawable ETH from LPs as BALANCED: ", allocations[7]);
            assertEq(
                allocations[2] + allocations[3] + allocations[4] + allocations[5] + allocations[6] + allocations[7],
                0,
                "[ICAA]: showAllocations"
            );
        }

        // Check ETH, frxETH, ankrETH, and stETH balances
        {
            assertEq(curveLsdAmoAddress.balance, 0, "[ICAA]: ETH balance");
            assertEq(ankrETHERC20.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: ankrETHERC20 balance");
            assertEq(stETHERC20.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: stETHERC20 balance");
        }

        // Check LP, cvxLP, and stkcvxLP balances
        {
            // frxETH/ETH
            assertEq(frxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: frxETHETH_LP balance");
            assertEq(cvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: cvxfrxETHETH_LP balance");
            assertEq(stkcvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: stkcvxfrxETHETH_LP balance");

            // frxETH/WETH
            assertEq(frxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: frxETHWETH_LP balance");
            assertEq(cvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: cvxfrxETHWETH_LP balance");
            assertEq(stkcvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: stkcvxfrxETHWETH_LP balance");

            // ankrETH/ETH
            assertEq(ankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: ankrETHfrxETH_LP balance");
            assertEq(cvxankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: cvxankrETHfrxETH_LP balance");
            assertEq(stkcvxankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: stkcvxankrETHfrxETH_LP balance");

            // stETH/ETH
            assertEq(stETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: stETHfrxETH_LP balance");
            assertEq(cvxstETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: cvxstETHfrxETH_LP balance");
            assertEq(stkcvxstETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[ICAA]: stkcvxstETHfrxETH_LP balance");
        }

        // EtherRouter should have 100 ETH seeded
        {
            assertEq(etherRouterAddress.balance, 100 ether, "[ICAA]: etherRouterAddress ETH balance");
        }
    }

    function CheckPartialDepositCurveAmoAccountingFinal() public {
        // Check showAllocations
        {
            uint256[10] memory allocations = amoHelper.showAllocations(curveLsdAmoAddress);
            // console.log("Deposit Allocations [2]: Total frxETH deposited into Pools: ", allocations[2]);
            // console.log("Deposit Allocations [3]: Total ETH + WETH deposited into Pools: ", allocations[3]);
            // console.log("Deposit Allocations [4]: Total withdrawable frxETH from LPs as ONE COIN: ", allocations[4]);
            // console.log("Deposit Allocations [5]: Total withdrawable ETH from LPs as ONE COIN: ", allocations[5]);
            // console.log("Deposit Allocations [6]: Total withdrawable frxETH from LPs as BALANCED: ", allocations[6]);
            // console.log("Deposit Allocations [7]: Total withdrawable ETH from LPs as BALANCED: ", allocations[7]);
            assertEq(
                allocations[2] + allocations[3] + allocations[4] + allocations[5] + allocations[6] + allocations[7],
                0,
                "[PDCAA]: showAllocations"
            );
        }

        // Check ETH, frxETH, ankrETH, and stETH balances
        {
            assertEq(curveLsdAmoAddress.balance, 0, "[PDCAA]: ETH balance");
            assertEq(ankrETHERC20.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: ankrETHERC20 balance");
            assertEq(stETHERC20.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: stETHERC20 balance");
        }

        // Check LP, cvxLP, and stkcvxLP balances
        {
            // frxETH/ETH
            assertEq(frxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: frxETHETH_LP balance");
            assertEq(cvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: cvxfrxETHETH_LP balance");
            assertEq(stkcvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: stkcvxfrxETHETH_LP balance");

            // frxETH/WETH
            assertEq(frxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: frxETHWETH_LP balance");
            assertEq(cvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: cvxfrxETHWETH_LP balance");
            assertEq(stkcvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: stkcvxfrxETHWETH_LP balance");

            // ankrETH/ETH
            assertEq(ankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: ankrETHfrxETH_LP balance");
            assertEq(cvxankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: cvxankrETHfrxETH_LP balance");
            assertEq(
                stkcvxankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress),
                0,
                "[PDCAA]: stkcvxankrETHfrxETH_LP balance"
            );

            // stETH/ETH
            assertEq(stETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: stETHfrxETH_LP balance");
            assertEq(cvxstETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: cvxstETHfrxETH_LP balance");
            assertEq(stkcvxstETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[PDCAA]: stkcvxstETHfrxETH_LP balance");
        }

        // EtherRouter should have gone down a little due to the partial deposit borrowing 24 ether to do the final deposit
        {
            assertEq(
                etherRouterAddress.balance,
                100 ether - (32 ether - PARTIAL_DEPOSIT_AMOUNT),
                "[PDCAA]: etherRouterAddress ETH balance"
            );
        }
    }

    function CheckFullDepositCurveAmoAccountingFinal() public {
        // Check showAllocations
        {
            uint256[10] memory allocations = amoHelper.showAllocations(curveLsdAmoAddress);
            // console.log("Deposit Allocations [2]: Total frxETH deposited into Pools: ", allocations[2]);
            // console.log("Deposit Allocations [3]: Total ETH + WETH deposited into Pools: ", allocations[3]);
            // console.log("Deposit Allocations [4]: Total withdrawable frxETH from LPs as ONE COIN: ", allocations[4]);
            // console.log("Deposit Allocations [5]: Total withdrawable ETH from LPs as ONE COIN: ", allocations[5]);
            // console.log("Deposit Allocations [6]: Total withdrawable frxETH from LPs as BALANCED: ", allocations[6]);
            // console.log("Deposit Allocations [7]: Total withdrawable ETH from LPs as BALANCED: ", allocations[7]);
            assertEq(
                allocations[2] + allocations[3] + allocations[4] + allocations[5] + allocations[6] + allocations[7],
                0,
                "[FDCAA]: showAllocations"
            );
        }

        // Check ETH, frxETH, ankrETH, and stETH balances
        {
            assertEq(curveLsdAmoAddress.balance, 0, "[FDCAA]: ETH balance");
            assertEq(ankrETHERC20.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: ankrETHERC20 balance");
            assertEq(stETHERC20.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: stETHERC20 balance");
        }

        // Check LP, cvxLP, and stkcvxLP balances
        {
            // frxETH/ETH
            assertEq(frxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: frxETHETH_LP balance");
            assertEq(cvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: cvxfrxETHETH_LP balance");
            assertEq(stkcvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: stkcvxfrxETHETH_LP balance");

            // frxETH/WETH
            assertEq(frxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: frxETHWETH_LP balance");
            assertEq(cvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: cvxfrxETHWETH_LP balance");
            assertEq(stkcvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: stkcvxfrxETHWETH_LP balance");

            // ankrETH/ETH
            assertEq(ankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: ankrETHfrxETH_LP balance");
            assertEq(cvxankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: cvxankrETHfrxETH_LP balance");
            assertEq(
                stkcvxankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress),
                0,
                "[FDCAA]: stkcvxankrETHfrxETH_LP balance"
            );

            // stETH/ETH
            assertEq(stETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: stETHfrxETH_LP balance");
            assertEq(cvxstETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: cvxstETHfrxETH_LP balance");
            assertEq(stkcvxstETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[FDCAA]: stkcvxstETHfrxETH_LP balance");
        }

        // EtherRouter should have gone down a little due to the partial deposit borrowing 24 ether to do the final deposit
        {
            assertEq(etherRouterAddress.balance, 100 ether, "[FDCAA]: etherRouterAddress ETH balance");
        }
    }

    function test_DepositFlowWithHostileValidatorPool() public {
        // WHEN A good user makes a partial deposit
        DepositCredentials memory _depositCredentials = _partialValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0],
            _depositAmount: PARTIAL_DEPOSIT_AMOUNT
        });

        // Create a second (hostile) validator pool with another user
        hoax(testUserAddress);
        address payable _validatorPoolHostileAddress = lendingPool.deployValidatorPool(
            testUserAddress,
            bytes32(block.timestamp)
        );

        // Beacon approves the hostile validator pool
        _beaconOracle_setVPoolCreditPerValidatorI48_E12(_validatorPoolHostileAddress, 28e12);

        // Hostile validator pool attempts to add another partial deposit to the good user's partial deposit (should fail)
        // ===============================================
        vm.startPrank(testUserAddress);
        try
            ValidatorPool(_validatorPoolHostileAddress).deposit{ value: PARTIAL_DEPOSIT_AMOUNT }(
                _depositCredentials.publicKey,
                _depositCredentials.signature,
                _depositCredentials.depositDataRoot
            )
        {
            revert("Should not have succeeded");
        } catch Error(string memory reason) {
            assertEq("DepositContract: reconstructed DepositData does not match supplied deposit_data_root", reason);
        }
        vm.stopPrank();

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Hostile validator pool attempts to complete the good user's partial deposit (should fail due to the pubkey not being added to the validators array)
        // ===============================================
        vm.startPrank(testUserAddress);

        DepositCredentials memory _finalDepositCredentialsBad = generateDepositCredentials(
            ValidatorPool(_validatorPoolHostileAddress),
            validatorPublicKeys[0],
            validatorSignatures[0],
            32 ether - PARTIAL_DEPOSIT_AMOUNT
        );

        try
            ValidatorPool(_validatorPoolHostileAddress).requestFinalDeposit(
                _finalDepositCredentialsBad.publicKey,
                _finalDepositCredentialsBad.signature,
                _finalDepositCredentialsBad.depositDataRoot
            )
        {
            revert("Should not have succeeded");
        } catch (bytes memory reason) {
            assertEq(ValidatorPool.ValidatorIsNotUsed.selector, bytes4(reason));
        }

        // Random user attempts to complete the good user's partial deposit on the good validator pool (should fail due to ownership check)
        // ===============================================
        DepositCredentials memory _finalDepositCredentialsGood = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[0],
            validatorSignatures[0],
            32 ether - PARTIAL_DEPOSIT_AMOUNT
        );

        // requestFinalDeposit
        try
            validatorPool.requestFinalDeposit(
                _finalDepositCredentialsBad.publicKey,
                _finalDepositCredentialsBad.signature,
                _finalDepositCredentialsBad.depositDataRoot
            )
        {
            revert("Should not have succeeded");
        } catch (bytes memory reason) {
            assertEq(ValidatorPool.SenderMustBeOwner.selector, bytes4(reason));
        }

        vm.stopPrank();
    }

    // EtherRouter: 100 ETH
    // CurveAmo: 0 ETH
    function test_PartialDepositFlowNoSweep() public {
        _PartialDepositFlowCore();
    }

    // // EtherRouter: 10 ETH
    // // CurveAmo: 0 ETH
    // function test_PartialDepositFlowPartialSweep() public {

    // }

    // function test_PartialDepositFlowFullSweep() public {

    // }

    function _PartialDepositFlowCore() public {
        /// SCENARIO: Successful Partial Deposit
        ValidatorDepositInfoSnapshot memory _initialValidatorDepositInfo = validatorDepositInfoSnapshot(
            validatorPublicKeys[0],
            lendingPool
        );
        ValidatorPoolAccountingSnapshot
            memory _initialValidatorPoolAccountingSnapshot = validatorPoolAccountingSnapshot(validatorPool);

        // WHEN a non-zero address calls validatorPool.deposit() with correct params
        DepositCredentials memory _depositCredentials = _partialValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0],
            _depositAmount: PARTIAL_DEPOSIT_AMOUNT
        });

        DeltaValidatorDepositInfoSnapshot memory _firstDeltaValidatorDepositInfo = deltaValidatorDepositInfoSnapshot(
            _initialValidatorDepositInfo
        );
        /// THEN userDepositedEther should match the deposit amount
        assertEq(
            _firstDeltaValidatorDepositInfo.end.lendingPool_validatorDepositInfo.userDepositedEther,
            PARTIAL_DEPOSIT_AMOUNT,
            "When validator Pool is partially deposited, then; userDepositedEther amount should match the deposit amount"
        );
        /// THEN validator public key should be positive
        assertGt(
            validatorPool.depositedAmts(_depositCredentials.publicKey),
            0,
            "When validator Pool is partially deposited, then: validator public key should be positive"
        );
        mineBlocksBySecond(1 days);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        // Try to finalize the deposit before the beacon approves the validator (should fail)
        {
            DepositCredentials memory _finalDepositCredentialsGood = generateDepositCredentials(
                validatorPool,
                validatorPublicKeys[0],
                validatorSignatures[0],
                32 ether - PARTIAL_DEPOSIT_AMOUNT
            );

            vm.startPrank(validatorPoolOwner);
            try
                validatorPool.requestFinalDeposit(
                    _finalDepositCredentialsGood.publicKey,
                    _finalDepositCredentialsGood.signature,
                    _finalDepositCredentialsGood.depositDataRoot
                )
            {
                revert("Should not have succeeded");
            } catch (bytes memory reason) {
                assertEq(LendingPoolCore.ValidatorIsNotApprovedLP.selector, bytes4(reason));
            }
            vm.stopPrank();
        }

        // WHEN validator approves the exit message from a validator
        _beaconOracle_setValidatorApproval(validatorPublicKeys[0], validatorPoolAddress, uint32(block.timestamp));

        // Try to finalize the deposit with a pubkey / pool mismatch (should fail)
        {
            vm.startPrank(testUserAddress);
            address payable _validatorPoolHostileAddress = lendingPool.deployValidatorPool(
                testUserAddress,
                bytes32(block.timestamp)
            );

            DepositCredentials memory _finalDepositCredentialsBad = generateDepositCredentials(
                ValidatorPool(_validatorPoolHostileAddress),
                validatorPublicKeys[0],
                validatorSignatures[0],
                32 ether - PARTIAL_DEPOSIT_AMOUNT
            );

            try
                ValidatorPool(_validatorPoolHostileAddress).requestFinalDeposit(
                    _finalDepositCredentialsBad.publicKey,
                    _finalDepositCredentialsBad.signature,
                    _finalDepositCredentialsBad.depositDataRoot
                )
            {
                revert("Should not have succeeded");
            } catch (bytes memory reason) {
                assertEq(ValidatorPool.ValidatorIsNotUsed.selector, bytes4(reason));
            }

            vm.stopPrank();
        }

        DeltaValidatorDepositInfoSnapshot memory _secondDeltaValidatorDepositInfo = deltaValidatorDepositInfoSnapshot(
            _firstDeltaValidatorDepositInfo.start
        );

        /// THEN lending pool should show validator is approved
        assertTrue(
            lendingPool.isValidatorApproved(validatorPublicKeys[0]),
            "When beacon oracle sees the a valid deposit message, then: lending pool should show validator is approved"
        );

        // You can borrow the remaining 24 ETH even with only a 8 ETH deposit. The credit flow is different here because it is fully
        // collateralize b/c the exit is controlled by the protocol.
        _requestFinalValidatorDepositByPkeyIdx(0);

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();

        DeltaValidatorDepositInfoSnapshot memory _thirdDeltaValidatorDepositInfo = deltaValidatorDepositInfoSnapshot(
            _secondDeltaValidatorDepositInfo.end
        );
        DeltaValidatorPoolAccountingSnapshot
            memory _firstDeltaValidatorPoolAccountingSnapshot = deltaValidatorPoolAccountingSnapshot(
                _initialValidatorPoolAccountingSnapshot
            );

        /// THEN lending pool accounting should have a total of 32 ether
        assertEq(
            _thirdDeltaValidatorDepositInfo.end.lendingPool_validatorDepositInfo.userDepositedEther +
                _thirdDeltaValidatorDepositInfo.end.lendingPool_validatorDepositInfo.lendingPoolDepositedEther,
            32 ether,
            "After final deposit, lending pool accounting should have total of 32 ether"
        );
        /// THEN lending pool should show that user deposited ether has not changed
        assertEq(
            _thirdDeltaValidatorDepositInfo.delta.lendingPool_validatorDepositInfo.userDepositedEther,
            0,
            "After final deposit, user deposited ether should not have changed"
        );
        /// THEN lending pool should show that lendingPoolDeposited ether should have changed by an amount equal to 32 less initial amount
        assertEq(
            _thirdDeltaValidatorDepositInfo.delta.lendingPool_validatorDepositInfo.lendingPoolDepositedEther,
            32 ether - PARTIAL_DEPOSIT_AMOUNT,
            "After final deposit, lending deposited ether should have changed by 32 ether less initial deposit amount"
        );
        /// THEN lending pool should show that borrowed amount is equal to the lending pool deposited amount
        assertEq(
            lendingPool.toBorrowAmount(
                _firstDeltaValidatorPoolAccountingSnapshot.end.lendingPool_validatorPoolAccount.borrowShares
            ),
            _thirdDeltaValidatorDepositInfo.delta.lendingPool_validatorDepositInfo.lendingPoolDepositedEther,
            "After final deposit, borrowed amount should be equal to the lending pool deposited amount"
        );

        CheckPartialDepositCurveAmoAccountingFinal();

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();
    }

    function fullDepositFlowCore() public {
        /// SCENARIO: Successful full deposit flow
        ValidatorDepositInfoSnapshot memory _initialValidatorDepositInfo = validatorDepositInfoSnapshot(
            validatorPublicKeys[0],
            lendingPool
        );
        ValidatorPoolAccountingSnapshot
            memory _initialValidatorPoolAccountingSnapshot = validatorPoolAccountingSnapshot(validatorPool);

        // WHEN a validator is deposited with 32 ether
        vm.expectEmit(true, true, true, true);
        // event DepositEvent(bytes pubkey, bytes withdrawal_credentials, bytes amount, bytes signature, bytes index);
        // Check that the deposit event went through
        emit DepositEvent(
            validatorPublicKeys[0],
            abi.encodePacked(validatorPool.withdrawalCredentials()),
            to_little_endian_64(32 ether / 1 gwei),
            validatorSignatures[0],
            depositContract.get_deposit_count()
        );
        DepositCredentials memory _depositCredentials = _fullValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0]
        });

        // Get delta snapshots
        _firstDeltaValidatorDepositInfo = deltaValidatorDepositInfoSnapshot(_initialValidatorDepositInfo);
        DeltaValidatorPoolAccountingSnapshot
            memory _firstDeltaValidatorPoolAccountingSnapshot = deltaValidatorPoolAccountingSnapshot(
                _initialValidatorPoolAccountingSnapshot
            );

        /// THEN userDepositedEther should match the deposit amount
        assertEq(
            _firstDeltaValidatorDepositInfo.end.lendingPool_validatorDepositInfo.userDepositedEther,
            32 ether,
            "When validator Pool is fully deposited, then; userDepositedEther amount should match 32 ether"
        );

        /// THEN validator public key should be positive
        assertGt(
            validatorPool.depositedAmts(_depositCredentials.publicKey),
            0,
            "When validator Pool is fully deposited, then: validator public key should be positive"
        );

        /// THEN lending pool accounting should have a total of 32 ether
        assertEq(
            _firstDeltaValidatorDepositInfo.end.lendingPool_validatorDepositInfo.userDepositedEther +
                _firstDeltaValidatorDepositInfo.end.lendingPool_validatorDepositInfo.lendingPoolDepositedEther,
            32 ether,
            "Lending pool accounting should have total of 32 ether"
        );

        /// THEN lending pool should show that borrowed amount is equal to zero
        assertEq(
            lendingPool.toBorrowAmount(
                _firstDeltaValidatorPoolAccountingSnapshot.end.lendingPool_validatorPoolAccount.borrowShares
            ),
            0,
            "After final deposit, borrowed amount should be zero"
        );

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();
    }

    function test_FullDepositFlow() public {
        fullDepositFlowCore();

        mineBlocksBySecond(1 days);

        // WHEN validator approves the exit message from a validator
        _beaconOracle_setValidatorApproval(validatorPublicKeys[0], validatorPoolAddress, uint32(block.timestamp));

        // Get delta snapshots
        DeltaValidatorDepositInfoSnapshot memory _secondDeltaValidatorDepositInfo = deltaValidatorDepositInfoSnapshot(
            _firstDeltaValidatorDepositInfo.start
        );

        /// THEN lending pool should show validator is approved
        assertTrue(
            lendingPool.isValidatorApproved(validatorPublicKeys[0]),
            "When beacon oracle sees the a valid deposit message, then: lending pool should show validator is approved"
        );

        // Generate a non-submitted pubkey (will fail after this)
        DepositCredentials memory _finalDepositCredentials = generateDepositCredentials(
            validatorPool,
            validatorPublicKeys[10],
            validatorSignatures[10],
            32 ether
        );

        // requestFinalDeposit (should fail because pubkeys have already been used)
        vm.startPrank(validatorPoolOwner);
        try
            validatorPool.requestFinalDeposit(
                _finalDepositCredentials.publicKey,
                _finalDepositCredentials.signature,
                _finalDepositCredentials.depositDataRoot
            )
        {
            revert("Should not have succeeded");
        } catch (bytes memory reason) {
            assertEq(ValidatorPool.ValidatorIsNotUsed.selector, bytes4(reason));
        }
        vm.stopPrank();

        // Check the Ether Router and Curve AMO accounting
        CheckFullDepositCurveAmoAccountingFinal();

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();
    }

    function test_FullDepositFlowFrontrunBeacon() public {
        fullDepositFlowCore();

        // Make sure validator pool is empty
        assertEq(validatorPoolAddress.balance, 0);

        // Assume beacon oracle hasn't hit yet
        // Dump in 32 ETH from an exit (assume instant exit)
        vm.deal(validatorPoolAddress, 32 ether);

        // Withdraw the 32 ETH immediately
        vm.prank(validatorPoolOwner);
        validatorPool.withdraw(validatorPoolOwner, 32 ether);

        // Beacon wrongly sets the validator count to 1, and increases the allowance
        // Assume this is frontrun in the same block as the withdrawal
        _beaconOracle_setVPoolValidatorCountAndBorrowAllowanceWithBuffer(validatorPoolAddress, 1, 5e17);

        // Beacon bot / logic finally sees what happened and corrects the validator count and allowance
        // The logic part is done off chain
        _beaconOracle_setVPoolValidatorCountAndBorrowAllowanceWithBuffer(validatorPoolAddress, 1, 5e17);

        // Should be able to borrow now
        vm.prank(validatorPoolOwner);
        validatorPool.borrow(validatorPoolOwner, 10 ether);

        vm.stopPrank();

        // Make sure stored utilization matches live utilization
        checkStoredVsLiveUtilization();
    }

    function testZach_LiquidatableAfterFinalize() public {
        DepositCredentials memory _depositCredentials = _partialValidatorDeposit({
            _validatorPool: validatorPool,
            _validatorPublicKey: validatorPublicKeys[0],
            _validatorSignature: validatorSignatures[0],
            _depositAmount: PARTIAL_DEPOSIT_AMOUNT
        });
        mineBlocksBySecond(1 days);
        _beaconOracle_setValidatorApproval(validatorPublicKeys[0], validatorPoolAddress, uint32(block.timestamp));
        _requestFinalValidatorDepositByPkeyIdx(0);

        // Give validator pool some ETH
        deal(validatorPoolAddress, 100 ether);

        vm.prank(beaconOracleAddress);
        lendingPool.liquidate(payable(address(validatorPool)), 1 ether);
        (, bool wasLiquidated, , , , , ) = lendingPool.validatorPoolAccounts(address(validatorPool));
        assertEq(wasLiquidated, true);
    }
}
