// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./CurveAmoBaseTest.t.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract CurveAMOHelperTest is CurveAmoBaseTest {
    function amoHelperSetup() public {
        defaultSetup();
        vm.stopPrank();

        // Give 10000 WETH to the AMO (from a WETH whale)
        startHoax(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        WETH.transfer(curveLsdAmoAddress, 10_000e18);

        // Switch back to the timelock
        vm.startPrank(ConstantsSBTS.Mainnet.TIMELOCK_ADDRESS);

        // Setup the frxETH/WETH farm
        setupFrxETHWETHInAmo(0);

        // Set up and fund the frxETHWETH pool
        fundFrxETHWETHVault(0);

        vm.stopPrank();
    }

    function testSetOracles() public {
        amoHelperSetup();

        // Try setting the oracles as a random person (should fail)
        hoax(testUserAddress);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, testUserAddress));
        amoHelper.setOracles(address(1), address(1));

        // Try setting the oracles with bad addresses (should fail)
        hoax(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        vm.expectRevert();
        amoHelper.setOracles(address(1), address(1));

        // Try setting the oracles valid Chainlink addresses (though for different tokens [AAVE & DAI]) (should pass)
        hoax(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);
        amoHelper.setOracles(0x547a514d5e3769680Ce22B2361c10Ea13619e8a9, 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);
    }

    function testShowPoolVaults() public {
        amoHelperSetup();

        // Get the pool vault info
        (uint256 _lpDepositPid, address _rewardsContractAddress, ) = amoHelper.showPoolVaults(curveLsdAmoAddress);

        // Verify the info
        assertEq(_lpDepositPid, 219, "testShowPoolVaults: _lpDepositPid");
        assertEq(
            _rewardsContractAddress,
            cvxfrxETHWETH_BaseRewardPool_address,
            "testShowPoolVaults: _rewardsContractAddress"
        );
    }

    function testshowPoolFreeCoinBalances() public {
        amoHelperSetup();

        // Get the pool vault info
        (uint256 _lpDepositPid, address _rewardsContractAddress, ) = amoHelper.showPoolVaults(curveLsdAmoAddress);

        // Verify the info
        assertEq(_lpDepositPid, 219, "testShowPoolVaults: _lpDepositPid");
        assertEq(
            _rewardsContractAddress,
            cvxfrxETHWETH_BaseRewardPool_address,
            "testShowPoolVaults: _rewardsContractAddress"
        );
    }

    function testShowPoolRewardsAndAlsoCvxRewards() public {
        amoHelperSetup();

        // Wait some time, so you can earn rewards
        mineBlocksBySecond(2 weeks);

        // Get the reward info for the frxETHWETH pool
        (
            uint256 _crvReward,
            uint256[] memory _extraRewardAmounts,
            address[] memory _extraRewardTokens,
            uint256 _extraRewardsLength
        ) = amoHelper.showPoolRewards(curveLsdAmoAddress);

        // Get the CVX rewards for the entire Curve AMO
        uint256 _cvxReward = amoHelper.showCVXRewards(curveLsdAmoAddress);

        // Print the rewards
        console.log("_crvReward: ", _crvReward);
        console.log("_cvxReward: ", _cvxReward);
        console.log("_extraRewardsLength: ", _extraRewardsLength);

        // Loop through the extra rewards
        for (uint256 i = 0; i < _extraRewardsLength; i++) {
            console.log(_extraRewardTokens[i], ": ", _extraRewardAmounts[i]);
        }

        // Verify the CRV Reward
        assertGt(_crvReward, 0, "testshowPoolRewards: _crvReward");
    }

    function testShowPoolLPTokenAddress() public {
        amoHelperSetup();

        // Get the lp address for the frxETHWETH pool
        address _lpAddress = amoHelper.showPoolLPTokenAddress(curveLsdAmoAddress);

        assertEq(_lpAddress, address(frxETHWETH_LP), "testShowPoolLPTokenAddress: _lpAddress");
    }

    function testGetEstLpPriceEthOrUsdE18() public {
        amoHelperSetup();

        // Try getting the LP price for a non-existent pool
        vm.expectRevert();
        amoHelper.getEstLpPriceEthOrUsdE18(address(0));
    }

    function testLpInVaults() public {
        amoHelperSetup();

        // Get the values
        (uint256 inCvxRewPool, uint256 inStkCvxFarm, uint256 totalVaultLP) = amoHelper.lpInVaults(curveLsdAmoAddress);

        // Check the values
        assertEq(inCvxRewPool, INITIAL_CVXLP_VAULTED, "testLpInVaults: inCvxRewPool");
        assertEq(inStkCvxFarm, INITIAL_STKCVXLP_VAULTED, "testLpInVaults: inStkCvxFarm");
        assertEq(totalVaultLP, INITIAL_CVXLP_VAULTED + INITIAL_STKCVXLP_VAULTED, "testLpInVaults: totalVaultLP");
    }

    function testCalcOneCoinsFullLPExit() public {
        amoHelperSetup();

        // Get the calculated values
        uint256[2] memory _withdrawables = amoHelper.calcOneCoinsFullLPExit(curveLsdAmoAddress);

        // Check the values
        // Should be very similar
        assertApproxEqRel(
            _withdrawables[0],
            INITIAL_CURVE_LP_RECEIVED_FROM_BAL_DEPOSIT,
            HALF_PCT_DELTA,
            "testCalcOneCoinsFullLPExit: _withdrawables[0] (WETH)"
        );
        assertApproxEqRel(
            _withdrawables[1],
            INITIAL_CURVE_LP_RECEIVED_FROM_BAL_DEPOSIT,
            HALF_PCT_DELTA,
            "testCalcOneCoinsFullLPExit: _withdrawables[1] (frxETH)"
        );
    }

    function testCalcBalancedFullLPExit() public {
        amoHelperSetup();

        // Get the calculated values
        uint256[2] memory _withdrawables = amoHelper.calcBalancedFullLPExit(curveLsdAmoAddress);

        // Check the values
        assertApproxEqRel(
            _withdrawables[0],
            INITIAL_CURVE_LP_ETH_BALANCED_DEPOSIT,
            HALF_PCT_DELTA,
            "testCalcBalancedFullLPExit: _withdrawables[0] (WETH)"
        );
        assertApproxEqRel(
            _withdrawables[1],
            INITIAL_FRXETH_USED_IN_BAL_DEPOSIT,
            HALF_PCT_DELTA,
            "testCalcBalancedFullLPExit: _withdrawables[1] (frxETH)"
        );
    }

    function testCalcTknsForLPBalanced() public {
        amoHelperSetup();

        // Get the calculated values
        uint256[2] memory _withdrawables = amoHelper.calcTknsForLPBalanced(
            curveLsdAmoAddress,
            INITIAL_CURVE_LP_RECEIVED_FROM_BAL_DEPOSIT
        );

        // Check the values
        assertApproxEqRel(
            _withdrawables[0],
            INITIAL_CURVE_LP_ETH_BALANCED_DEPOSIT,
            HALF_PCT_DELTA,
            "testCalcTknsForLPBalanced: _withdrawables[0] (WETH)"
        );
        assertApproxEqRel(
            _withdrawables[1],
            INITIAL_FRXETH_USED_IN_BAL_DEPOSIT,
            HALF_PCT_DELTA,
            "testCalcTknsForLPBalanced: _withdrawables[1] (frxETH)"
        );
    }
}
