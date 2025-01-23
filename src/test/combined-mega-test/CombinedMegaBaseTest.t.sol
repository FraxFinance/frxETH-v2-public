// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "frax-std/FraxTest.sol";
import "src/test/helpers/Helpers.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "src/contracts/BeaconOracle.sol";
import "src/contracts/curve-amo/CurveLsdAmo.sol";
import "src/contracts/curve-amo/CurveLsdAmoHelper.sol";
import "src/contracts/ether-router/EtherRouter.sol";
import "src/contracts/frax-ether-minter/FraxEtherMinter.sol";
import "src/contracts/lending-pool/LendingPool.sol";
import "src/contracts/lending-pool/LendingPoolCore.sol";
import "src/contracts/curve-amo/interfaces/curve/IPoolLSDETH.sol";
import "src/contracts/curve-amo/interfaces/curve/IPool2LSDStable.sol";
import "src/contracts/curve-amo/interfaces/curve/IPool2Crypto.sol";
import "src/contracts/curve-amo/interfaces/convex/IConvexBaseRewardPool.sol";
import "src/contracts/curve-amo/interfaces/convex/IConvexBooster.sol";
import "src/contracts/curve-amo/interfaces/convex/IConvexClaimZap.sol";
import "src/contracts/curve-amo/interfaces/convex/IcvxRewardPool.sol";
import { IDepositContract, DepositContract } from "src/contracts/interfaces/IDepositContract.sol";
import { ValidatorPool } from "src/contracts/ValidatorPool.sol";
import "../../script/DeployAll.s.sol";
import "../curve-amo/CurveAmoBaseTest.t.sol" as CurveAmoBsTst;
import "../../Constants.sol" as ConstantsCMBT;

contract CombinedMegaBaseTest is CurveAmoBsTst.CurveAmoBaseTest {
    // Setup the CurveAmo stuff first, which also includes some things the lending pool and validator tests use
    function megaSetup() public {
        super.defaultSetup();

        // Clear the timelock address prank
        vm.stopPrank();

        validatorPoolOwner = labelAndDeal(address(256), "validatorPoolOwner");

        // Fake deposit contract
        DepositContract _mockDeposit = new DepositContract();
        vm.etch(address(depositContract), address(_mockDeposit).code);

        // Deploy ValidatorPool with owner
        validatorPoolAddress = lendingPool.deployValidatorPool(validatorPoolOwner, bytes32(block.timestamp));
        validatorPool = ValidatorPool(validatorPoolAddress);

        // Evil / fake validator pool
        evilValPoolOwner = labelAndDeal(address(666), "evilValPoolOwner");
        evilValPoolAddress = lendingPool.deployValidatorPool(evilValPoolOwner, bytes32(block.timestamp));
        evilValPool = ValidatorPool(evilValPoolAddress);

        // Add frxETH/WETH as a Curve AMO pool and set stkcvxfrxETHWETH as the default pool
        vm.startPrank(address(0)); // Prevent test complaining
        setupFrxETHWETHInAmo(0);

        // Also add stkcvxfrxETHETH, stETHfrxETH and ankrETHfrxETH as valid pools
        // addFrxETHETHAsPool(0);
        // addStETHFrxETHAsPool(0);
        // addAnkrETHFrxETHAsPool(0);
        vm.stopPrank();

        // // Throw away all the frxETH in the Curve AMO from the CurveAmoBase Test (not needed yet)
        // vm.startPrank(curveLsdAmoAddress);
        // frxETH.burn(1000e18);
        // vm.stopPrank();

        // Remove the ETH in the Curve AMO from the CurveAmoBase Test
        vm.deal(curveLsdAmoAddress, 0 ether);

        // Put 100 ETH in the EtherRouter
        vm.deal(etherRouterAddress, 100 ether);

        // Give the validator pool owner 72 ETH
        vm.deal(validatorPoolOwner, 72 ether);

        // Zero out the ETH for the validator pool
        vm.deal(validatorPoolAddress, 0);
    }

    // For inherited lending pool tests
    function _defaultSetup() public {
        megaSetup();
    }

    // EtherRouter: 10 ETH
    // CurveAmo: Mix of ETH, frxETH, LP, cvxLP, stkcvxLP
    // function partialSweepMixedFrxEthLp() public {
    // MAY NOT NEED TO DO THIS IF YOUR EtherRouter tests are robust enough with complex LPs
    //     // Sweep 90 ETH, will go in as stkcvxfrxETHETH
    //     vm.startPrank(ConstantsCMBT.Mainnet.TIMELOCK_ADDRESS);
    //     etherRouter.sweepEther(90 ether);

    //     // 50% of the stkcvxLP -> LP
    //     {
    //         bytes32[] memory kekIds = curveLsdAmo.getVaultKekIds(address(frxETHETH_Pool));
    //         uint256 frxEELpBalance = frxETHETH_LP.balanceOf(curveLsdAmoAddress);
    //         curveLsdAmo.withdrawAndUnwrapFromFxsVault(address(frxETHETH_Pool), kekIds[0]);
    //     }

    //     vm.stopPrank();
    // }

    // EtherRouter: 10 ETH
    // CurveAmo: Mix of ETH, frxETH, ankrETH, stETH, their 3 LPs, their 3 cvxLPs, and their 3 stkcvxLPs
    function partialSweepMixedThreePairLp() public {
        // // Sweep 90 ETH, will go in as stkcvxfrxETHETH
        // vm.startPrank(ConstantsCMBT.Mainnet.TIMELOCK_ADDRESS);
        // etherRouter.sweepEther(90 ether);
        // // 50% of the stkcvxLP -> LP
        // frxETHETH_LP.balanceOf(curveLsdAmoAddress);
        // curveLsdAmo.withdrawAndUnwrapFromFxsVault(address(frxETHETH_Pool),)
        // vm.stopPrank();
    }

    function windDown(uint96 initialFrxEtherAmount, uint256 intermediateTtlEthSum) public {
        // Test user wants their ETH back
        vm.startPrank(testUserAddress);

        // Redeem some frxEther for a redemption ticket
        uint256 userEthBefore = testUserAddress.balance;
        frxETH.approve(redemptionQueueAddress, initialFrxEtherAmount);
        uint256 nftId = redemptionQueue.enterRedemptionQueue(testUserAddress, initialFrxEtherAmount);

        // Get the maturityTime and wait for after it
        {
            (, uint64 maturityTime, , , ) = redemptionQueue.nftInformation(nftId);

            // Wait until after the maturity
            mineBlocksBySecond((maturityTime - uint64(block.timestamp)) + 1);
        }

        // Redeem the NFT
        // NOTE: This might fail if there is was slippage, leaving a small amount lacking
        (uint120 _amountEtherPaidToUser, uint120 _redemptionFeeAmount) = redemptionQueue.fullRedeemNft(
            nftId,
            testUserAddress
        );

        console.log("======== AFTER FULL REDEEM  ========");
        console.log("_amountEtherPaidToUser: ", _amountEtherPaidToUser);
        console.log("_redemptionFeeAmount: ", _redemptionFeeAmount);

        // Collect redemption fees, if any
        vm.startPrank(ConstantsCMBT.Mainnet.RQ_OPERATOR_ADDRESS);
        redemptionQueue.collectAllRedemptionFees();
        vm.stopPrank();

        /// THEN the test user should have gotten their ether back
        assertEq(
            testUserAddress.balance - userEthBefore,
            initialFrxEtherAmount,
            "Test user should have gotten their ether back"
        );

        vm.stopPrank();

        {
            (
                uint256 _interestAccrued,
                uint256 _ethTotalBalanced,
                uint256 _totalNonValidatorEthSum,
                uint256 _optimisticValidatorEth,
                uint256 _ttlSystemEth
            ) = printAndReturnSystemStateInfo("======== AFTER WINDDOWN ========", true);
            totalNonValidatorEthSums[2] = _totalNonValidatorEthSum;
            totalSystemEthSums[2] = _ttlSystemEth;

            /// THEN the starting total sum should match the intermediate sum
            assertApproxEqRel(
                totalSystemEthSums[0],
                totalSystemEthSums[1],
                HALF_PCT_DELTA,
                "Starting total sum doesn't match the intermediate sum"
            );

            /// THEN the starting total sum should match the ending sum
            assertApproxEqRel(
                totalSystemEthSums[0],
                totalSystemEthSums[2],
                HALF_PCT_DELTA,
                "Starting total sum doesn't match the ending sum"
            );

            /// THEN after winding down, the only assets left in the frxETH V2 setup should be the interest and some
            /// small remainder due to Curve operations
            assertApproxEqAbs(
                _interestAccrued,
                _ethTotalBalanced,
                0.1e18,
                "Total ETH remaining should be accrued interest"
            );
        }
    }
}
