// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./CurveAmoBaseTest.t.sol";

interface CurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function get_virtual_price() external view returns (uint256);
    function balances(uint256 i) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract EtherRouterTest is CurveAmoBaseTest {
    function etherRouterSetUp() public {
        defaultSetup();

        // Add FrxETHWETH as the default FXS vault
        setupFrxETHWETHInAmo(0);
        // curveLsdAmo.createFxsVault(address(frxETHWETH_Pool), 219); // No stkcvxLP yet

        // Clear the CURVEAMO_OPERATOR_ADDRESS prank
        vm.stopPrank();

        // Throw away all the frxETH in the Curve AMO from the CurveAmoBase Test (not needed yet)
        vm.startPrank(curveLsdAmoAddress);
        frxETH.burn(1000e18);
        vm.stopPrank();

        // Remove the ETH in the Curve AMO from the CurveAmoBase Test
        vm.deal(curveLsdAmoAddress, 0 ether);
    }

    function testAddAMOFails() public {
        etherRouterSetUp();

        // Try adding an address as a random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS,
                testUserAddress
            )
        );
        etherRouter.addAmo(payable(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));

        // Try adding a random address that doesn't fit the required ABI (should fail)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert();
        etherRouter.addAmo(payable(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
    }

    function testRemoveAMO() public {
        etherRouterSetUp();

        // Try to remove the AMO, as a random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS,
                testUserAddress
            )
        );
        etherRouter.removeAmo(payable(curveLsdAmo));

        // Remove the AMO correctly, as the timelock (should pass)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        etherRouter.removeAmo(payable(curveLsdAmo));
    }

    function testSetLendingPool() public {
        etherRouterSetUp();

        // Try setting the lending pool as a random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS,
                testUserAddress
            )
        );
        etherRouter.setLendingPool(payable(lendingPool));

        // Set the lending pool as timelock (should pass)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        etherRouter.setLendingPool(payable(lendingPool));
    }

    function testsetPreferredDepositAndWithdrawalAMOs() public {
        etherRouterSetUp();

        // Try setting the addresses as a random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        etherRouter.setPreferredDepositAndWithdrawalAMOs(payable(curveLsdAmo), payable(curveLsdAmo));

        // Set the addresses as the timelock (should pass)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        etherRouter.setPreferredDepositAndWithdrawalAMOs(payable(curveLsdAmo), payable(curveLsdAmo));
    }

    function testSweepEther() public {
        etherRouterSetUp();

        // Set ETH for EtherRouter
        vm.deal(address(etherRouter), 100 ether);

        // Try sweeping the ETH as a random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOrOperator()"));
        etherRouter.sweepEther(0, true);

        // Tighten minTkn0ToTkn1RatioE6 and maxTkn0ToTkn1RatioE6
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setSlippages(600, 1000, 100, 10_000, 350_000, 650_000);

        // Sweep most of the ETH as the timelock (will fail due to tight Tkn0ToTkn1RatioE6s)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("PoolTooImbalanced()"));
        etherRouter.sweepEther(95 ether, true);

        // Loosen minTkn0ToTkn1RatioE6 and maxTkn0ToTkn1RatioE6 back to normal
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        curveLsdAmo.setSlippages(600, 1000, 100, 10_000, 150_000, 850_000);

        // Sweep most of the ETH as the timelock (should pass)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        etherRouter.sweepEther(95 ether, true);

        // Sweep the remaining ETH balance
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        etherRouter.sweepEther(0, true);

        // All of the ETH should have been deposited into the Redemption Queue and/or Curve AMO(s)
        // ================================

        // Check showAllocations
        {
            uint256[10] memory allocations = amoHelper.showAllocations(curveLsdAmoAddress);
            assertApproxEqRel(
                allocations[9],
                100 ether,
                0.01e18,
                "[ICAA]: showAllocations (Total ETH + WETH deposited into Pools)"
            );
        }

        // Make sure all of the funds are in cvxLP vault (not cvxLP ERC20)
        // {
        //     (, , uint256[5] memory _poolAllocations) = amoHelper.showPoolAccounting(curveLsdAmoAddress);
        //     // console.log("_poolAllocations [0]: Vanilla Curve LP balance: ", _poolAllocations[0]);
        //     // console.log("_poolAllocations [1]: cvxLP in booster: ", _poolAllocations[1]);
        //     // console.log("_poolAllocations [2]: stkcvxLP in farm: ", _poolAllocations[2]);
        //     // console.log("_poolAllocations [3]: Total LP in vaults: ", _poolAllocations[3]);
        //     // console.log("_poolAllocations [4]: Total LP: ", _poolAllocations[4]);
        //     // assertApproxEqRel(
        //     //     _poolAllocations[1],
        //     //     100 ether,
        //     //     ONE_PCT_DELTA,
        //     //     "TSE: _poolAllocations [1] (cvxLP in booster)"
        // }

        // Check ETH, frxETH, ankrETH, and stETH balances
        {
            assertEq(curveLsdAmoAddress.balance, 0, "[TSE]: ETH balance");
            assertEq(ankrETHERC20.balanceOf(curveLsdAmoAddress), 0, "[TSE]: ankrETHERC20 balance");
            assertEq(stETHERC20.balanceOf(curveLsdAmoAddress), 0, "[TSE]: stETHERC20 balance");
            assertEq(WETH.balanceOf(curveLsdAmoAddress), 0, "[TSE]: WETH balance");
        }

        // Check LP, cvxLP, and stkcvxLP balances
        {
            // frxETH/ETH
            assertEq(frxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: frxETHETH_LP balance");
            assertEq(cvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: cvxfrxETHETH_LP balance");
            assertEq(stkcvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: stkcvxfrxETHETH_LP balance");

            // ankrETH/ETH
            assertEq(ankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: ankrETHfrxETH_LP balance");
            assertEq(cvxankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: cvxankrETHfrxETH_LP balance");
            assertEq(stkcvxankrETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: stkcvxankrETHfrxETH_LP balance");

            // stETH/ETH
            assertEq(stETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: stETHfrxETH_LP balance");
            assertEq(cvxstETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: cvxstETHfrxETH_LP balance");
            assertEq(stkcvxstETHfrxETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: stkcvxstETHfrxETH_LP balance");

            // frxETH/WETH
            assertEq(frxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: frxETHWETH_LP balance");
            assertEq(cvxfrxETHWETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: cvxfrxETHWETH_LP balance");
            // assertEq(stkcvxfrxETHETH_LP.balanceOf(curveLsdAmoAddress), 0, "[TSE]: stkcvxfrxETHETH_LP balance");
        }

        // Try sweeping ETH that doesn't exist (should fail)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert();
        etherRouter.sweepEther(50 ether, true);
    }

    function testRequestEtherSimple() public {
        etherRouterSetUp();

        // Set some ETH for the EtherRouter
        vm.deal(address(etherRouter), 1000 ether);

        // Sweep the ether into the Redemption Queue and/or Curve AMO(s)
        console.log("<<<Sweep the ether>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        etherRouter.sweepEther(1000 ether, true);

        // Set some ETH for the EtherRouter again
        vm.deal(address(etherRouter), 525 ether);

        // Try requesting ETH as a random person (should fail)
        console.log("<<<Request ETH as a random person (should fail)>>>");
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSignature("NotLendingPoolOrRedemptionQueue()"));
        etherRouter.requestEther(testUserAddress, 100 ether, false);

        // Try requesting ETH as the lending pool (should pass)
        console.log("<<<Request ETH as the lending pool (should pass)>>>");
        hoax(address(lendingPool));
        etherRouter.requestEther(payable(lendingPool), 25 ether, false);

        // Try requesting more ETH than the EtherRouter has free, so it has to unwind 50 LP at the CurveAMO
        console.log("<<<Request ether again with insufficient free ETH so it should unwind LP>>>");
        hoax(address(lendingPool));
        etherRouter.requestEther(payable(lendingPool), 550 ether, false);

        // Try sweeping Ether that doesn't exist (should fail)
        console.log("<<<Try sweeping ether that doesn't exist (should fail)>>>");
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert();
        etherRouter.sweepEther(50 ether, true);
    }

    function testRequestEtherSingleLpSet() public {
        etherRouterSetUp();
    }

    function testRequestEtherTripleLpSet() public {
        etherRouterSetUp();
    }

    function testRecoverERC20() public {
        etherRouterSetUp();

        // Test user accidentally sends frxETH
        hoax(testUserAddress2);
        frxETH.transfer(etherRouterAddress, 1e18);

        // Try recovering the frxETH as the test user (should fail)
        hoax(testUserAddress2);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS,
                testUserAddress2
            )
        );
        etherRouter.recoverErc20(address(frxETH), 1e18);

        // Try recovering the frxETH as the operator (should fail)
        hoax(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS,
                ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS
            )
        );
        etherRouter.recoverErc20(address(frxETH), 1e18);

        // Recover the frxETH as the timelock
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        etherRouter.recoverErc20(address(frxETH), 1e18);
    }

    // Will fail unless timelock has a fallback
    function testRecoverEther() public {
        etherRouterSetUp();

        // Give ETH to the Ether Router contract
        vm.deal(etherRouterAddress, 1 ether);
        hoax(etherRouterAddress);
        redemptionQueueAddress.transfer(1e18);

        // Change the timelock to one that CAN accept ETH
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        etherRouter.transferTimelock(ConstantsSBTS.Mainnet.FRAX_WHALE);

        // Accept the new timelock address
        hoax(ConstantsSBTS.Mainnet.FRAX_WHALE);
        etherRouter.acceptTransferTimelock();

        // Try recovering the ETH as the testUserAddress2 (should fail)
        hoax(testUserAddress2);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.FRAX_WHALE,
                testUserAddress2
            )
        );
        etherRouter.recoverEther(1e18);

        // Try recovering the ETH as the operator (should fail)
        hoax(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AddressIsNotTimelock(address,address)",
                ConstantsSBTS.Mainnet.FRAX_WHALE,
                ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS
            )
        );
        etherRouter.recoverEther(1e18);

        // Recover half of the ETH as the timelock
        hoax(ConstantsSBTS.Mainnet.FRAX_WHALE);
        etherRouter.recoverEther(0.5e18);

        // Change the timelock to one that cannot accept ETH
        hoax(ConstantsSBTS.Mainnet.FRAX_WHALE);
        etherRouter.transferTimelock(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS_REAL);

        // Accept the new timelock address
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS_REAL);
        etherRouter.acceptTransferTimelock();

        // Try to collect the ETH with an address that has no fallback() / receive() (should fail)
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS_REAL);
        vm.expectRevert(abi.encodeWithSignature("InvalidRecoverEtherTransfer()"));
        etherRouter.recoverEther(0.5e18);

        // Change the timelock back to one that can accept ETH
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS_REAL);
        etherRouter.transferTimelock(ConstantsSBTS.Mainnet.FRAX_WHALE);

        // Accept the new timelock address
        hoax(ConstantsSBTS.Mainnet.FRAX_WHALE);
        etherRouter.acceptTransferTimelock();

        // Recover the remaining half of the ETH as the ETH-compatible timelock
        hoax(ConstantsSBTS.Mainnet.FRAX_WHALE);
        etherRouter.recoverEther(0.5e18);
    }

    function testZach_CurveManipulation() public {
        // // Tighten minTkn0ToTkn1RatioE6 and maxTkn0ToTkn1RatioE6
        // hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        // curveLsdAmo.setSlippages(600, 1000, 100, 10_000, 350_000, 650_000);

        // set up router and add eth
        etherRouterSetUp();
        vm.deal(address(etherRouter), 10_000 ether);

        // set up callable curve pool
        CurvePool curvePool = CurvePool(0x9c3B46C0Ceb5B9e304FCd6D88Fc50f7DD24B31Bc);

        // assert we are starting with no weth and no frxETH
        assert(WETH.balanceOf(address(this)) == 0);
        assert(frxETH.balanceOf(address(this)) == 0);

        // "flashloan" 1200 frxETH
        deal(address(frxETH), address(this), 1200 ether);

        // attacker swaps frxeth to eth to throw off balance
        frxETH.approve(address(curvePool), 1200 ether);
        curvePool.exchange(1, 0, 1200 ether, 0);

        // sandwiched deposit transaction, adding liquidity reduces slippage
        // Should fail due to the imbalance check
        hoax(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("PoolTooImbalanced()"));
        etherRouter.sweepEther(1000 ether, true);

        // // attacker swaps back and profits
        // uint wethBal = WETH.balanceOf(address(this));
        // WETH.approve(address(curvePool), wethBal);
        // curvePool.exchange(0, 1, wethBal, 0);

        // // "return the flashloan" by burning frxeth we dealt
        // frxETH.transfer(address(1), 1200 ether);

        // // resulting profit
        // assertEq(frxETH.balanceOf(address(this)), 120455520335216745);
    }

    function testZach_CurveBalances() public {
        // set up contract and callable curve pool
        etherRouterSetUp();
        CurvePool curvePool = CurvePool(0x9c3B46C0Ceb5B9e304FCd6D88Fc50f7DD24B31Bc);

        // swap 10_000 frxETH to create imbalance
        deal(address(frxETH), address(this), 10_000 ether);
        frxETH.approve(address(curvePool), 10_000 ether);
        curvePool.exchange(1, 0, 10_000 ether, 0);

        // now let's look at some data
        uint256 amountOfEthToWithdraw = 100 ether;
        (uint256 lpAmount, , , , ) = amoHelper.calcMiscBalancedInfo(curveLsdAmoAddress, 0, amountOfEthToWithdraw);
        uint256 amountOfEthWithdrawn = (curvePool.balances(0) * lpAmount) / curvePool.totalSupply();

        console.log("amountOfEthWithdrawn: %s", amountOfEthWithdrawn);

        assertApproxEqRel(amountOfEthWithdrawn, 100 ether, 0.01e18, "testZach_CurveBalances: amountOfEthWithdrawn");
    }
}
