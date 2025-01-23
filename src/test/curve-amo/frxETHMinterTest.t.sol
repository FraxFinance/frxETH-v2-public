// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import "./CurveAmoBaseTest.t.sol";
import { Test } from "forge-std/Test.sol";

contract frxETHMinterTestV2 is CurveAmoBaseTest {
    function setUp() public {
        defaultSetup();

        // Clear the CURVEAMO_OPERATOR_ADDRESS prank
        vm.stopPrank();
    }

    function testSubmitAndDepositEther() public {
        vm.startPrank(FRXETH_COMPTROLLER);

        // Give the comptroller 320 ETH
        vm.deal(FRXETH_COMPTROLLER, 320 ether);

        // Deposit 16 ETH for frxETH
        vm.expectEmit(true, true, false, true);
        emit TokenMinterMinted(address(fraxEtherMinter), FRXETH_COMPTROLLER, 16 ether);
        vm.expectEmit(true, true, false, true);
        emit EthSubmitted(FRXETH_COMPTROLLER, FRXETH_COMPTROLLER, 16 ether);
        fraxEtherMinter.mintFrxEth{ value: 16 ether }();

        // Deposit 15 ETH for frxETH, pure send (tests receive fallback)
        vm.expectEmit(true, true, false, true);
        emit TokenMinterMinted(address(fraxEtherMinter), FRXETH_COMPTROLLER, 15 ether);
        vm.expectEmit(true, true, false, true);
        emit EthSubmitted(FRXETH_COMPTROLLER, FRXETH_COMPTROLLER, 15 ether);
        address(fraxEtherMinter).call{ value: 15 ether }("");

        // Deposit last 1 ETH for frxETH, making the total 32.
        // Uses mintFrxEthAndGive as an alternate method. Timelock will get the frxETH but the validator doesn't care
        vm.expectEmit(true, true, false, true);
        emit TokenMinterMinted(address(fraxEtherMinter), FRAX_TIMELOCK, 1 ether);
        vm.expectEmit(true, true, false, true);
        emit EthSubmitted(FRXETH_COMPTROLLER, FRAX_TIMELOCK, 1 ether);
        fraxEtherMinter.mintFrxEthAndGive{ value: 1 ether }(FRAX_TIMELOCK);

        // Pause submits
        fraxEtherMinter.togglePauseSubmits();

        // Try submitting while paused (should fail)
        vm.expectRevert(abi.encodeWithSignature("MintFrxEthIsPaused()"));
        fraxEtherMinter.mintFrxEth{ value: 1 ether }();

        // Unpause submits
        fraxEtherMinter.togglePauseSubmits();

        vm.stopPrank();
    }

    function testRecoverEther() public {
        vm.startPrank(FRXETH_COMPTROLLER);

        // Note the starting ETH balance of the comptroller
        uint256 starting_eth = FRXETH_COMPTROLLER.balance;

        // Give minter 10 eth
        vm.deal(address(fraxEtherMinter), 10 ether);
        address fraxEtherMinter_operator = fraxEtherMinter.operatorAddress();

        // Recover 5 ETH
        vm.expectEmit(false, false, false, true);
        emit EmergencyEtherRecovered(5 ether);
        fraxEtherMinter.recoverEther(5 ether);

        // Make sure the FRXETH_COMPTROLLER got 5 ether back
        assertEq(FRXETH_COMPTROLLER.balance, starting_eth + (5 ether));

        vm.stopPrank();
    }

    function testRecoverERC20() public {
        vm.startPrank(FRXETH_COMPTROLLER);

        // Note the starting ETH balance of the comptroller
        uint256 starting_frxETH = frxETH.balanceOf(FRXETH_COMPTROLLER);

        // Give the comptroller 5 eth
        vm.deal(FRXETH_COMPTROLLER, 5 ether);

        // Deposit 5 ETH for frxETH first
        vm.expectEmit(true, true, true, true);
        emit TokenMinterMinted(address(fraxEtherMinter), FRXETH_COMPTROLLER, 5 ether);
        fraxEtherMinter.mintFrxEth{ value: 5 ether }();

        // Throw the newly minted frxETH into the fraxEtherMinter "by accident"
        frxETH.transfer(address(fraxEtherMinter), 5 ether);

        // Get the intermediate frxETH balance of the comptroller
        uint256 intermediate_frxETH = frxETH.balanceOf(FRXETH_COMPTROLLER);

        // Make sure you are back to where you started from, frxETH balance wise
        assertEq(starting_frxETH, intermediate_frxETH);

        // Recover 5 frxETH
        vm.expectEmit(false, false, false, true);
        emit EmergencyErc20Recovered(address(frxETH), 5 ether);
        fraxEtherMinter.recoverErc20(address(frxETH), 5 ether);

        // Get the ending frxETH balance of the comptroller
        uint256 ending_frxETH = frxETH.balanceOf(FRXETH_COMPTROLLER);

        // Make sure the FRXETH_COMPTROLLER got 5 frxETH back
        assertEq(ending_frxETH, starting_frxETH + (5 ether));

        vm.stopPrank();
    }

    event EmergencyEtherRecovered(uint256 amount);
    event EmergencyErc20Recovered(address tokenAddress, uint256 tokenAmount);
    event EthSubmitted(address indexed sender, address indexed recipient, uint256 sent_amount);
    event TokenMinterMinted(address indexed sender, address indexed to, uint256 amount);
}
