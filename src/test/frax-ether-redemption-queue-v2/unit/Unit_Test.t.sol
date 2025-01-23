// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import { BaseTest } from "../BaseTest.sol";
import "forge-std/console.sol";
import {
    FraxEtherRedemptionQueueV2,
    FraxEtherRedemptionQueueCoreParams,
    FraxEtherRedemptionQueueCore
} from "../../../contracts/frxeth-redemption-queue-v2/FraxEtherRedemptionQueueV2.sol";
import { FraxTest } from "frax-std/FraxTest.sol";
import { SigUtils } from "../utils/SigUtils.sol";
import "../Constants.sol" as Constants;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Unit_Test is BaseTest {
    function miscSetup() internal {
        // Do nothing for now
    }

    function testRecoverERC20() public {
        defaultSetup();

        // Redeemer accidentally sends frxETH
        hoax(redeemer0);
        frxETH.transfer(redemptionQueueAddress, 10e18);

        // Try recovering the frxETH as redeemer0 (should fail)
        hoax(redeemer0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
                redeemer0
            )
        );
        redemptionQueue.recoverErc20(address(frxETH), 10e18);

        // Recover the frxETH as the timelock
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.recoverErc20(address(frxETH), 10e18);
    }

    // Will fail unless timelock has a fallback
    function testRecoverEther() public {
        defaultSetup();

        // Give ETH to the redemption queue contract
        vm.deal(redeemer0, 10 ether);
        hoax(redeemer0);
        redemptionQueueAddress.transfer(10e18);

        // Try recovering the ETH as redeemer0 (should fail)
        hoax(redeemer0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
                redeemer0
            )
        );
        redemptionQueue.recoverEther(10e18);

        // Try recovering the ETH as the operator (should fail)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
                Constants.Mainnet.RQ_OPERATOR_ADDRESS
            )
        );
        redemptionQueue.recoverEther(10e18);

        // Change the timelock to one that CAN accept ETH (Beeharvester)
        console.log("<<<Change the timelock to one that CAN accept ETH (Beeharvester)>>>");
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.transferTimelock(Constants.Mainnet.BEEHARVESTER_ADDRESS);

        // Accept the new timelock address (Beeharvester)
        console.log("<<<Accept the new timelock address (Beeharvester)>>>");
        hoax(Constants.Mainnet.BEEHARVESTER_ADDRESS);
        redemptionQueue.acceptTransferTimelock();

        // Recover half of the ETH as the timelock
        console.log("<<<Recover half of the ETH as the temporary timelock (Beeharvester)>>>");
        hoax(Constants.Mainnet.BEEHARVESTER_ADDRESS);
        redemptionQueue.recoverEther(5e18);

        // Change the timelock to one that CANNOT accept ETH
        hoax(Constants.Mainnet.BEEHARVESTER_ADDRESS);
        redemptionQueue.transferTimelock(Constants.Mainnet.FRXETH_ADDRESS);

        // Accept the new timelock address
        console.log("<<<Accept the new timelock address>>>");
        hoax(Constants.Mainnet.FRXETH_ADDRESS);
        redemptionQueue.acceptTransferTimelock();

        // Try to collect the ETH with an address that has no fallback() / receive() (should fail)
        hoax(Constants.Mainnet.FRXETH_ADDRESS);
        vm.expectRevert();
        redemptionQueue.recoverEther(5e18);

        // Change the timelock back to one that can accept ETH
        console.log("<<<Change the timelock back to one that can accept ETH>>>");
        hoax(Constants.Mainnet.FRXETH_ADDRESS);
        redemptionQueue.transferTimelock(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);

        // Accept the new timelock address
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.acceptTransferTimelock();

        // Change the timelock to one that CAN accept ETH (Beeharvester)
        console.log("<<<Change the timelock to one that CAN accept ETH (Beeharvester)>>>");
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.transferTimelock(Constants.Mainnet.BEEHARVESTER_ADDRESS);

        // Accept the new timelock address (Beeharvester)
        console.log("<<<Accept the new timelock address (Beeharvester)>>>");
        hoax(Constants.Mainnet.BEEHARVESTER_ADDRESS);
        redemptionQueue.acceptTransferTimelock();

        // Recover the remaining half of the ETH as the ETH-compatible timelock (Beeharvester)
        console.log("<<<Recover the remaining half of the ETH as an ETH-compatible timelock (Beeharvester)>>>");
        hoax(Constants.Mainnet.BEEHARVESTER_ADDRESS);
        redemptionQueue.recoverEther(5e18);
    }

    function testSetOperator() public {
        defaultSetup();

        // Try setting the operator as a random person (should fail)
        hoax(redeemer0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
                redeemer0
            )
        );
        redemptionQueue.setOperator(redeemer0);

        // Set the operator to the frxETH whale (should pass)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setOperator(Constants.Mainnet.FRXETH_WHALE);
        assertEq(
            redemptionQueue.operatorAddress(),
            Constants.Mainnet.FRXETH_WHALE,
            "Operator should now be FRXETH_WHALE"
        );
    }

    function testSetFeeRecipient() public {
        defaultSetup();

        // Try setting the fee recipient as a random person (should fail)
        hoax(redeemer0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
                redeemer0
            )
        );
        redemptionQueue.setFeeRecipient(redeemer0);

        // Set the fee recipient to the frxETH whale (should pass)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setFeeRecipient(Constants.Mainnet.FRXETH_WHALE);
        assertEq(
            redemptionQueue.feeRecipient(),
            Constants.Mainnet.FRXETH_WHALE,
            "Fee recipient should now be FRXETH_WHALE"
        );
    }

    function testSetMaxOperatorQueueLengthSecs() public {
        defaultSetup();

        // Try setting the max operator queue length as a random person (should fail)
        hoax(redeemer0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
                redeemer0
            )
        );
        redemptionQueue.setMaxQueueLengthSeconds(1000);

        // Set the queue length using as the timelock (should pass)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setMaxQueueLengthSeconds(1000);
        uint256 maxOperatorQueueLengthSecs = redemptionQueue.maxQueueLengthSeconds();
        assertEq(maxOperatorQueueLengthSecs, 1000, "Max Queue length should now be 1000");
    }

    function testSetQueueLengthSecs() public {
        defaultSetup();

        // Try setting the queue length as a random person (should fail)
        hoax(redeemer0);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        redemptionQueue.setQueueLengthSeconds(1000);

        // Try to set the queue length above the operator max, as the operator (should fail)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("ExceedsMaxQueueLengthSecs(uint64,uint256)", 105 days, 100 days));
        redemptionQueue.setQueueLengthSeconds(105 days);

        // Try to set the queue length above the operator max, as the timelock (should pass)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setQueueLengthSeconds(105 days);

        // Set the queue length using the operator (should pass)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        redemptionQueue.setQueueLengthSeconds(1000);
        (, uint64 queueLengthSecs, , , ) = redemptionQueue.redemptionQueueState();
        assertEq(queueLengthSecs, 1000, "Queue length should now be 1000");

        // Set the queue length using the timelock (should pass)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setQueueLengthSeconds(5000);
        (, queueLengthSecs, , , ) = redemptionQueue.redemptionQueueState();
        assertEq(queueLengthSecs, 5000, "Queue length should now be 5000");
    }

    function testSetRedemptionFee() public {
        defaultSetup();

        // Try setting the redemption fee as a random person (should fail)
        hoax(redeemer0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
                redeemer0
            )
        );
        redemptionQueue.setRedemptionFee(10_000);

        // Try to set the redemption fee using the operator (should fail)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
                Constants.Mainnet.RQ_OPERATOR_ADDRESS
            )
        );
        redemptionQueue.setRedemptionFee(10_000);

        // Try to set the redemption fee above the max (should fail)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        vm.expectRevert(abi.encodeWithSignature("ExceedsMaxRedemptionFee(uint64,uint64)", 13_371_337, 20_000));
        redemptionQueue.setRedemptionFee(13_371_337);

        // Set the redemption fee using the timelock (should pass)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setRedemptionFee(10_000);
        (, , uint64 redemptionFee, , ) = redemptionQueue.redemptionQueueState();
        assertEq(redemptionFee, 10_000, "Redemption fee should now be 10000");
    }

    function testTransferAcceptTimelock() public {
        defaultSetup();

        // Try setting the timelock as a random person (should fail)
        hoax(redeemer0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
                redeemer0
            )
        );
        redemptionQueue.transferTimelock(redeemer0);

        // Set the pending timelock to redeemer0 (should pass)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.transferTimelock(redeemer0);
        assertEq(redemptionQueue.pendingTimelockAddress(), redeemer0, "Pending timelock should now be FRXETH_WHALE");

        // Try to accept the timelock credentials as the FRXETH_WHALE (should fail)
        hoax(Constants.Mainnet.FRXETH_WHALE);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotPendingTimelock(address,address)",
                redeemer0,
                Constants.Mainnet.FRXETH_WHALE
            )
        );
        redemptionQueue.acceptTransferTimelock();

        // Accept the timelock credentials as redeemer0 (should pass)
        hoax(redeemer0);
        redemptionQueue.acceptTransferTimelock();
        assertEq(redemptionQueue.timelockAddress(), redeemer0, "Timelock should now be redeemer0");
    }

    function testRenounceTimelock() public {
        defaultSetup();

        // Try renouncing the timelock to redeemer0 TIMELOCK_ADDRESS_REAL as FRXETH_WHALE (should fail)
        hoax(Constants.Mainnet.FRXETH_WHALE);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
                Constants.Mainnet.FRXETH_WHALE
            )
        );
        redemptionQueue.renounceTimelock();

        // Try renouncing the timelock before setting TIMELOCK_ADDRESS_REAL as pending (should fail)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotPendingTimelock(address,address)",
                address(0),
                Constants.Mainnet.TIMELOCK_ADDRESS_REAL
            )
        );
        redemptionQueue.renounceTimelock();

        // Set the pending timelock as the timelock address too (required for renounce as a safety precaution) (should pass)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.transferTimelock(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        assertEq(
            redemptionQueue.pendingTimelockAddress(),
            Constants.Mainnet.TIMELOCK_ADDRESS_REAL,
            "Pending timelock should now be TIMELOCK_ADDRESS_REAL"
        );

        // Try renouncing the timelock as the TIMELOCK_ADDRESS_REAL (should pass)
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.renounceTimelock();
        assertEq(redemptionQueue.timelockAddress(), address(0), "Timelock should now be address(0)");
    }
}
