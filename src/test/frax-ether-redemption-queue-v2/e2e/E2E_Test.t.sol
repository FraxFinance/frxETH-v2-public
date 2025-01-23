// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import { BaseTest } from "../BaseTest.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "forge-std/console.sol";
import {
    EtherRouter,
    FraxEtherRedemptionQueueV2,
    FraxEtherRedemptionQueueCoreParams,
    FraxEtherRedemptionQueueCore
} from "../../../contracts/frxeth-redemption-queue-v2/FraxEtherRedemptionQueueV2.sol";
import { FraxTest } from "frax-std/FraxTest.sol";
import { SigUtils } from "../utils/SigUtils.sol";
import "src/test/helpers/RedemptionQueueStructHelper.sol";
import "../Constants.sol" as Constants;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract E2E_Test is BaseTest {
    // Avoid stack too deep
    bool _isRedeemable;
    uint120 _maxAmountRedeemable;

    function e2eSetup() internal {
        // Do nothing for now
    }

    function _printRqInfo(string memory _title) public {
        // Print the title
        console.log(_title);

        // Get the RQ state
        RedemptionQueueStructHelper.RedemptionQueueStateReturn memory _rqCurrState = RedemptionQueueStructHelper
            .__redemptionQueueState(redemptionQueue);

        // Print the RQ state
        console.log("================= RedemptionQueueState =================");
        console.log("ttlEthRequested: ", _rqCurrState.ttlEthRequested);
        console.log("ttlEthServed: ", _rqCurrState.ttlEthServed);

        // Get the RQ Accounting
        RedemptionQueueStructHelper.RedemptionQueueAccountingReturn
            memory _rqCurrAccounting = RedemptionQueueStructHelper.__redemptionQueueAccounting(redemptionQueue);

        // Print the RQ Accounting
        console.log("================= RedemptionQueueState =================");
        console.log("etherLiabilities: ", _rqCurrAccounting.etherLiabilities);
        console.log("unclaimedFees: ", _rqCurrAccounting.unclaimedFees);
        console.log("pendingFees: ", _rqCurrAccounting.pendingFees);
        console.log("ETH balance: ", redemptionQueueAddress.balance);
        console.log("WETH balance: ", WETH.balanceOf(redemptionQueueAddress));
        console.log("frxETH balance: ", frxETH.balanceOf(redemptionQueueAddress));

        // Loop through the NFTs and print
        for (uint256 i = 0; i < _rqCurrState.nextNftId; i++) {
            // Print some information
            RedemptionQueueStructHelper.NftInformationReturn memory _nftInfo = RedemptionQueueStructHelper
                .__nftInformation(redemptionQueue, i);

            console.log("================= NFT INFO #%s =================", i);
            console.log("hasBeenRedeemed: ", _nftInfo.hasBeenRedeemed);
            console.log("amount: ", _nftInfo.amount);
            console.log("redemptionFee: ", _nftInfo.redemptionFee);
            console.log("ttlEthRequestedSnapshot: ", _nftInfo.ttlEthRequestedSnapshot);
        }
    }

    function testEnterRedemptionQueue() public {
        defaultSetup();

        // Switch to redeemer0
        vm.startPrank(redeemer0);

        // Approve the 100 frxETH
        frxETH.approve(redemptionQueueAddress, 100e18);

        // Enter the queue with the recipient not supporting ERC721 (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Errors.ERC721InvalidReceiver.selector,
                0x853d955aCEf822Db058eb8505911ED77F175b99e
            )
        );
        redemptionQueue.enterRedemptionQueue(payable(0x853d955aCEf822Db058eb8505911ED77F175b99e), 100e18);

        // Enter the queue normally
        redemptionQueue.enterRedemptionQueue(redeemer0, 100e18);
        assertEq(frxETH.balanceOf(redeemer0), 0, "Redeemer0 should have 0 frxETH after entering the queue");

        vm.stopPrank();
    }

    function testEnterRedemptionQueueWithPermit() public {
        defaultSetup();

        // Switch to redeemer0
        vm.startPrank(redeemer0);

        // Sign the permit for 100 frxETH
        uint120 redeem_amt = 100e18;
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: redeemer0,
            spender: redemptionQueueAddress,
            value: redeem_amt,
            nonce: frxETH.nonces(redeemer0),
            deadline: block.timestamp + (1 days)
        });
        bytes32 digest = sigUtils_frxETH.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(redeemer0PrivateKey, digest);

        // Enter the queue using the permit
        redemptionQueue.enterRedemptionQueueWithPermit(redeem_amt, redeemer0, permit.deadline, v, r, s);
        assertEq(frxETH.balanceOf(redeemer0), 0, "Redeemer0 should have 0 frxETH after entering the queue");
    }

    function testEnterRedemptionQueueWithSfrxEthPermit() public {
        defaultSetup();

        // Switch to redeemer0
        vm.startPrank(redeemer0);

        // Sign the permit for the sfrxETH from the converted 100 frxETH
        uint120 redeem_amt_sfrxeth = uint120(initialSfrxETHFromRedeemer0);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: redeemer0,
            spender: redemptionQueueAddress,
            value: redeem_amt_sfrxeth,
            nonce: sfrxETH.nonces(redeemer0),
            deadline: block.timestamp + (1 days)
        });
        bytes32 digest = sigUtils_sfrxETH.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(redeemer0PrivateKey, digest);

        // Enter the queue using the permit
        redemptionQueue.enterRedemptionQueueWithSfrxEthPermit(redeem_amt_sfrxeth, redeemer0, permit.deadline, v, r, s);
        assertEq(sfrxETH.balanceOf(redeemer0), 0, "Redeemer0 should have 0 sfrxETH after entering the queue");
    }

    function testMassiveNFT() public {
        defaultSetup();

        // Set the redemption fee to 2%
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setRedemptionFee(20_000);

        // Give redeemer0 an extra 1250 frxETH
        hoax(0xac3E018457B222d93114458476f3E3416Abbe38F);
        frxETH.transfer(redeemer0, 1250e18);

        // Switch to redeemer0
        vm.startPrank(redeemer0);

        // Approve
        frxETH.approve(redemptionQueueAddress, 1250e18);

        // Try to create an NFT over MAX_FRXETH_PER_NFT (should fail)
        vm.expectRevert(abi.encodeWithSelector(FraxEtherRedemptionQueueCore.ExceedsMaxFrxEthPerNFT.selector));
        redemptionQueue.enterRedemptionQueue(redeemer0, 1250e18);
    }

    function testQueuePositioningForRedeem() public {
        defaultSetup();

        // Set the redemption fee to 2% first
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setRedemptionFee(20_000);

        // Switch to redeemer0
        vm.startPrank(redeemer0);

        // Approve the 100 frxETH
        frxETH.approve(redemptionQueueAddress, 100e18);

        // Redeemer0 enters the queue first
        redemptionQueue.enterRedemptionQueue(redeemer0, 100e18);
        assertEq(frxETH.balanceOf(redeemer0), 0, "Redeemer0 should have 0 frxETH after entering the queue");

        // Give the redemptionQueue some ETH
        vm.deal(redemptionQueueAddress, 105 ether);

        vm.stopPrank();

        // Switch to redeemer1
        vm.startPrank(redeemer1);

        // Approve the 100 frxETH
        frxETH.approve(redemptionQueueAddress, 100e18);

        // Redeemer1 enters the queue second
        redemptionQueue.enterRedemptionQueue(redeemer1, 100e18);
        assertEq(frxETH.balanceOf(redeemer1), 0, "Redeemer1 should have 0 frxETH after entering the queue");

        // Redeemer0 does a second and 3rd NFT
        {
            vm.stopPrank();

            // Give redeemer0 10 frxETH
            vm.startPrank(Constants.Mainnet.FRXETH_WHALE);
            frxETH.transfer(redeemer0, 10e18);

            // Approve
            frxETH.approve(redemptionQueueAddress, 10e18);

            // Enter the queue
            redemptionQueue.enterRedemptionQueue(redeemer0, 7e18);
            redemptionQueue.enterRedemptionQueue(redeemer0, 3e18);

            vm.stopPrank();
        }

        // Print some information
        _printRqInfo("\n---------================= AFTER SETUP =================---------");

        // Switch to redeemer0
        vm.startPrank(redeemer0);

        // Wait until after the maturity
        mineBlocksBySecond(2 weeks);

        // Print some information
        _printRqInfo("\n---------================= AFTER 2 WEEKS =================---------");

        // #1 can be partially redeemed up to 5 ether because the amount is low enough
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(1, 5 ether, true);
        assertEq(
            _maxAmountRedeemable,
            5 ether,
            "NFT #1 partial canRedeem: _maxAmountRedeemable doesn't match expected amount"
        );

        // Make sure redeemer1 cannot redeem more yet (redeemer0 has priority, not enough ETH for both)
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(1, 10 ether, false);
        assertEq(_isRedeemable, false, "redeemer1 canRedeem #1 [QueuePosition]: should have returned false");

        // Check if #1 can redeem 10 ether partially now (should revert due to queue position)
        vm.expectRevert(
            abi.encodeWithSelector(FraxEtherRedemptionQueueCore.QueuePosition.selector, 100 ether, 9.8 ether, 105 ether)
        );
        redemptionQueue.canRedeem(1, 10 ether, true);

        // Make sure redeemer0 can redeem NFT #0 fully
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(0, 0, true);
        assertEq(_isRedeemable, true, "NFT #0 redeem [A-1]: _isRedeemable should be true");
        assertEq(
            _maxAmountRedeemable,
            100 ether,
            "NFT #0 redeem [A-2]: _maxAmountRedeemable doesn't match full redeem amount"
        );

        // Make sure redeemer0 can redeem NFT #0 partially too
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(0, 5 ether, true);
        assertEq(_isRedeemable, true, "NFT #0 redeem [B-1]: _isRedeemable should be true");
        assertEq(
            _maxAmountRedeemable,
            100 ether,
            "NFT #0 redeem [B-2]: _maxAmountRedeemable doesn't match full redeem amount"
        );

        // Make sure redeemer0 CANNOT redeem NFT #2 yet
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(2, 0, false);
        assertEq(_isRedeemable, false, "redeemer0 canRedeem #2 [QueuePosition]: should have returned false");
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(2, 1 ether, false);
        assertEq(_isRedeemable, false, "redeemer0 canRedeem #2 [QueuePosition]: should have returned false");

        // Put enough ETH in so redeemer1 can redeem #1 fully
        // 100 + (100 * (1 - .02)) = 198
        vm.deal(redemptionQueueAddress, 198 ether);
        redemptionQueue.canRedeem(1, 0, true);

        // ==============================================
        // Actually do some redemptions
        // ==============================================

        // Put enough ETH in so #0 can be fully redeemed and #1 partially
        // ((100 * (1 - .02)) = 98) + ((1 * (1 - .02)) = .98)
        vm.deal(redemptionQueueAddress, 98.98 ether);

        // Switch to redeemer1 as a test
        vm.startPrank(redeemer1);

        // Try to redeem #0 as the wrong person (should revert)
        vm.expectRevert(abi.encodeWithSignature("Erc721CallerNotOwnerOrApproved()"));
        redemptionQueue.fullRedeemNft(0, redeemer0);

        // Switch to redeemer0
        vm.stopPrank();
        vm.startPrank(redeemer0);

        // Fully redeem #0
        redemptionQueue.fullRedeemNft(0, redeemer0);

        // Print some information
        _printRqInfo("\n---------================= AFTER #0 FULL =================---------");

        // Switch to redeemer1
        vm.stopPrank();
        vm.startPrank(redeemer1);

        // Partially redeem #1
        redemptionQueue.partialRedeemNft(1, redeemer1, 1 ether);

        // Print some information
        _printRqInfo("\n---------================= AFTER #1 PARTIAL (1 ether) =================---------");

        // Make sure #1 is not redeemable quite yet (insufficient Eth)
        // 99 * (1 - .02) = 97.02 needed
        vm.expectRevert(abi.encodeWithSelector(FraxEtherRedemptionQueueCore.InsufficientEth.selector, 97.02 ether, 0));
        redemptionQueue.fullRedeemNft(1, redeemer1);

        // Put enough ETH in so #1 can be fully redeemed
        // Most goes to RQ, some to ER
        vm.deal(redemptionQueueAddress, 87.02 ether);
        vm.deal(etherRouterAddress, 10 ether);

        // Make sure #2 is not redeemable yet (queue position)
        // 7 * (1 - .02) = 6.86
        // (100 + 1 = 101 served) + (97.02 free) = 198.02
        vm.expectRevert(
            abi.encodeWithSelector(
                FraxEtherRedemptionQueueCore.QueuePosition.selector,
                200 ether,
                6.86 ether,
                198.02 ether
            )
        );
        redemptionQueue.canRedeem(2, 0, true);

        // Redeem #1 fully
        redemptionQueue.fullRedeemNft(1, redeemer1);

        // Print some information
        _printRqInfo("\n---------================= AFTER #1 FULL =================---------");

        // Put enough ETH in the ETHER ROUTER (not RQ) so #2 can be fully redeemed
        // 10 * (1 - .02) = 9.8
        vm.deal(etherRouterAddress, 9.8 ether);

        // Switch to redeemer0
        vm.stopPrank();
        vm.startPrank(redeemer0);

        // Redeem #2 and #3 fully
        redemptionQueue.fullRedeemNft(2, redeemer0);
        redemptionQueue.fullRedeemNft(3, redeemer0);

        // Print some information
        _printRqInfo("\n---------================= AFTER #2 & #3 FULL =================---------");

        vm.stopPrank();

        // Deal with fee collection
        {
            // Operator triggers redemption fee collection (specified amount)
            uint256 _frxEthBeforeFees = frxETH.balanceOf(redemptionQueue.feeRecipient());
            hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
            redemptionQueue.collectRedemptionFees(1 ether);

            // Operator triggers redemption fee collection (remaining fees)
            hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
            redemptionQueue.collectAllRedemptionFees();
            uint256 _frxEthAfterFees = frxETH.balanceOf(redemptionQueue.feeRecipient());

            // See how much fees have been collected
            uint256 _ttlFrxEthCollectedAsFees = _frxEthAfterFees - _frxEthBeforeFees;

            // Make sure the total fees match what is expected
            // Normal redemptions (2% fee): (100 + 100 + 7 + 3) * 0.02 = 4.2
            assertEq(_ttlFrxEthCollectedAsFees, 4.2e18, "Fees collected not matching expected fees");
        }

        // Get the RQ state
        RedemptionQueueStructHelper.RedemptionQueueStateReturn memory _rqCurrState = RedemptionQueueStructHelper
            .__redemptionQueueState(redemptionQueue);

        // Make sure ttlEthRequested equals ttlEthServed
        assertEq(_rqCurrState.ttlEthRequested, _rqCurrState.ttlEthServed, "ttlEthRequested should equal ttlEthServed");

        // Get the RQ Accounting
        RedemptionQueueStructHelper.RedemptionQueueAccountingReturn
            memory _rqCurrAccounting = RedemptionQueueStructHelper.__redemptionQueueAccounting(redemptionQueue);

        // Make sure etherLiabilities is 0
        assertEq(_rqCurrAccounting.etherLiabilities, 0, "etherLiabilities should be 0");

        // The RQ should have no ETH
        assertEq(redemptionQueueAddress.balance, 0, "The RQ should have no ETH");

        // The RQ should have no frxETH
        assertEq(frxETH.balanceOf(redemptionQueueAddress), 0, "The RQ should have no frxETH");
    }

    function testQueuePositioningLineCutter() public {
        defaultSetup();

        // Set the redemption fee to 2% first
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setRedemptionFee(20_000);

        // Give Alice, Bob, and Charlie 100 extra frxETH each (so they have 200 frxETH total)
        vm.startPrank(Constants.Mainnet.FRXETH_WHALE);
        frxETH.transfer(alice, 100e18);
        frxETH.transfer(bob, 100e18);
        // frxETH.transfer(charlie, 100e18);
        vm.stopPrank();

        // Alice enters first with 150 frxETH
        vm.startPrank(alice);
        frxETH.approve(redemptionQueueAddress, 150e18);
        redemptionQueue.enterRedemptionQueue(alice, 150e18);
        vm.stopPrank();

        // Bob enters next with 50 frxETH
        vm.startPrank(bob);
        frxETH.approve(redemptionQueueAddress, 50e18);
        redemptionQueue.enterRedemptionQueue(bob, 50e18);
        vm.stopPrank();

        // Wait one hour
        mineBlocksBySecond(1 hours);

        // Give the redemptionQueue some ETH
        vm.deal(redemptionQueueAddress, 150 ether);

        // Wait two weeks
        mineBlocksBySecond(2 weeks);

        // Bob tries to redeem, but fails (cutting in line / QueuePosition)
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(FraxEtherRedemptionQueueCore.QueuePosition.selector, 150 ether, 49 ether, 150 ether)
        );
        redemptionQueue.fullRedeemNft(1, bob);
        vm.stopPrank();

        // Alice redeems
        vm.startPrank(alice);
        redemptionQueue.fullRedeemNft(0, alice);
        vm.stopPrank();
    }

    function testFullRedeemRedemptionTicketNFT() public {
        defaultSetup();

        console.log("=== PART 0 ===");

        // Set the redemption fee to 2% first
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setRedemptionFee(20_000);

        // Switch to redeemer0
        vm.startPrank(redeemer0);

        // Approve the 100 frxETH
        frxETH.approve(redemptionQueueAddress, 100e18);

        // Enter the queue using the approve
        redemptionQueue.enterRedemptionQueue(redeemer0, 100e18);
        assertEq(frxETH.balanceOf(redeemer0), 0, "Redeemer0 should have 0 frxETH after entering the queue");

        // Give the redemptionQueue some ETH
        vm.deal(redemptionQueueAddress, 100 ether);

        // Get the maturity time
        (, uint64 maturityTime, , , ) = redemptionQueue.nftInformation(0);

        console.log("=== PART 1 ===");

        // Check if you can redeem fully (should return false, not revert)
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(0, 0, false);
        assertEq(_isRedeemable, false, "canRedeem [too early]: should return false");

        // Check if you can redeem fully (should revert)
        vm.expectRevert(
            abi.encodeWithSelector(FraxEtherRedemptionQueueCore.NotMatureYet.selector, block.timestamp, maturityTime)
        );
        redemptionQueue.canRedeem(0, 0, true);

        // Try to actually redeem the NFT early (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(FraxEtherRedemptionQueueCore.NotMatureYet.selector, block.timestamp, maturityTime)
        );
        redemptionQueue.fullRedeemNft(0, redeemer0);

        // Wait until after the maturity
        mineBlocksBySecond(2 weeks);

        console.log("=== PART 2 ===");

        // Check if you can redeem fully (should return true)
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(0, 0, false);
        assertEq(_isRedeemable, true, "canRedeem [happy path]: should return true");

        // Check if you can redeem fully (should not revert)
        redemptionQueue.canRedeem(0, 0, true);

        // Temporarily drain ETH so InsufficientEth in canRedeem hits
        vm.deal(curveLsdAmoAddress, 0);
        vm.deal(etherRouterAddress, 0);
        vm.deal(redemptionQueueAddress, 0);

        // Check if you can redeem fully (should return false due to the drained ETH)
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(0, 0, false);
        assertEq(_isRedeemable, false, "canRedeem [drained ETH]: should return false");

        console.log("=== PART 3 ===");

        // Check if you can redeem fully (should revert due to the drained ETH -> Queue Position)
        // 100 * (1 - .02) = 98
        vm.expectRevert(abi.encodeWithSelector(FraxEtherRedemptionQueueCore.InsufficientEth.selector, 98 ether, 0));
        // sssss
        // vm.expectRevert(
        // abi.encodeWithSelector(FraxEtherRedemptionQueueCore.QueuePosition.selector, 0, 98 ether, 0)
        // );
        redemptionQueue.canRedeem(0, 0, true);

        // Put the ETH back, most in the RQ, some in the ER
        vm.deal(redemptionQueueAddress, 80 ether);
        vm.deal(etherRouterAddress, 20 ether);

        console.log("=== PART 4 ===");

        // Try to redeem the NFT to a non-payable contract (should fail)
        vm.expectRevert();
        redemptionQueue.fullRedeemNft(0, payable(0x853d955aCEf822Db058eb8505911ED77F175b99e));

        // Try to redeem the NFT again (should work this time)
        uint256 eth_before = redeemer0.balance;
        (, uint256 _initialUnclaimedFees, ) = redemptionQueue.redemptionQueueAccounting();
        redemptionQueue.fullRedeemNft(0, redeemer0);
        (, uint256 _finalUnclaimedFees, ) = redemptionQueue.redemptionQueueAccounting();

        // Checks
        assertEq(redeemer0.balance - eth_before, 98 ether, "Redeemer0 should have gained ETH after redeeming the NFT");
        assertEq(
            _finalUnclaimedFees - _initialUnclaimedFees,
            2e18,
            "2 frxETH should have been burned as the redemption fee"
        );

        // Wait 2 weeks again
        mineBlocksBySecond(2 weeks);

        console.log("=== PART 5 ===");

        // Try to redeem an already-redeemed NFT (should fail)
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        redemptionQueue.fullRedeemNft(0, redeemer0);

        vm.stopPrank();

        // Operator triggers redemption fee collection (specified amount)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        redemptionQueue.collectRedemptionFees(1 ether);

        // Operator triggers redemption fee collection (remaining fees)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        redemptionQueue.collectAllRedemptionFees();

        console.log("=== PART 6 ===");
    }

    function _partialRedeemCore() internal {
        defaultSetup();

        console.log("=== PRC Part 1 ===");

        // Set the redemption fee to 2% first
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setRedemptionFee(20_000);

        // Switch to redeemer0
        vm.startPrank(redeemer0);

        // Approve the 100 frxETH
        frxETH.approve(redemptionQueueAddress, 100e18);

        // Enter the queue using the approve
        redemptionQueue.enterRedemptionQueue(redeemer0, 100e18);
        assertEq(frxETH.balanceOf(redeemer0), 0, "Redeemer0 should have 0 frxETH after entering the queue");

        // Give the redemptionQueue some ETH
        vm.deal(redemptionQueueAddress, 100 ether);

        console.log("=== PRC Part 2 ===");

        // Get the maturity time
        (, uint64 maturityTime, uint120 amountInNFT, , ) = redemptionQueue.nftInformation(0);

        // Check if you can redeem partially now (should return false, not revert)
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(0, 1 ether, false);
        assertEq(_isRedeemable, false, "canRedeem [too early]: should have returned false");

        // Check if you can redeem partially now (should revert due to being too early)
        vm.expectRevert(
            abi.encodeWithSelector(FraxEtherRedemptionQueueCore.NotMatureYet.selector, block.timestamp, maturityTime)
        );
        redemptionQueue.canRedeem(0, 1 ether, true);

        // Try to actually redeem the NFT early (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(FraxEtherRedemptionQueueCore.NotMatureYet.selector, block.timestamp, maturityTime)
        );
        redemptionQueue.partialRedeemNft(0, redeemer0, 10e18);

        console.log("=== PRC Part 3 ===");

        // Wait until after the maturity
        mineBlocksBySecond(2 weeks);

        // Check if you can redeem partially (should return true)
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(0, 1 ether, false);
        assertEq(_isRedeemable, true, "canRedeem [happy path]: should return true");

        // Check if you can redeem partially, but with too much ETH (should return false)
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(0, 10_000 ether, false);
        assertEq(_isRedeemable, false, "canRedeem [too much ETH]: should have failed");

        // Check if you can redeem partially (should not revert)
        redemptionQueue.canRedeem(0, 1 ether, true);

        console.log("=== PRC Part 4 ===");

        // Check if you can redeem partially, but with too much ETH (should revert)
        vm.expectRevert(
            abi.encodeWithSelector(FraxEtherRedemptionQueueCore.InsufficientEth.selector, 9.8e21, 100 ether)
        );
        redemptionQueue.canRedeem(0, 10_000 ether, true);

        // Temporarily drain ETH so InsufficientEth in canRedeem hits
        vm.deal(redemptionQueueAddress, 0);

        // Check if you can redeem partially (should return false due to the drained ETH)
        (_isRedeemable, _maxAmountRedeemable) = redemptionQueue.canRedeem(0, 1 ether, false);
        assertEq(_isRedeemable, false, "canRedeem [drained ETH]: should return false");

        // Check if you can redeem partially (should revert due to the drained ETH)
        // 1 * (1 - .02) = .98
        vm.expectRevert(abi.encodeWithSelector(FraxEtherRedemptionQueueCore.InsufficientEth.selector, 0.98 ether, 0));
        redemptionQueue.canRedeem(0, 1 ether, true);

        console.log("=== PRC Part 5 ===");

        // Put the ETH back, half in the RQ and half in the ER
        vm.deal(redemptionQueueAddress, 50 ether);
        vm.deal(etherRouterAddress, 50 ether);

        // Try to redeem the NFT to a non-payable contract (should fail)
        vm.expectRevert();
        redemptionQueue.partialRedeemNft(0, payable(0x853d955aCEf822Db058eb8505911ED77F175b99e), 10e18);

        // Try to partial redeem 0 value (should fail)
        vm.expectRevert(abi.encodeWithSelector(FraxEtherRedemptionQueueV2.CannotRedeemZero.selector));
        redemptionQueue.partialRedeemNft(0, redeemer0, 0 ether);

        // Try to partially redeem half of the NFT (should work this time)
        uint256 eth_before = redeemer0.balance;
        (, uint256 _initialUnclaimedFees, ) = redemptionQueue.redemptionQueueAccounting();
        redemptionQueue.partialRedeemNft(0, redeemer0, 50 ether);
        (, uint256 _finalUnclaimedFees, ) = redemptionQueue.redemptionQueueAccounting();

        // Checks
        assertEq(
            redeemer0.balance - eth_before,
            49 ether,
            "Redeemer0 should have gained ETH after redeeming the NFT (1st half)"
        );
        assertEq(
            _finalUnclaimedFees - _initialUnclaimedFees,
            1e18,
            "1 frxETH should have been burned as the redemption fee"
        );

        // Wait 2 weeks again
        mineBlocksBySecond(2 weeks);

        console.log("=== PRC Part 6 ===");
    }

    function testPartialRedeemRoute1RedemptionTicketNFT() public {
        // Do the shared core logic
        _partialRedeemCore();

        // ROUTE 1: CLOSE OFF WITH ANOTHER PARTIAL REDEEM
        // ====================================================================

        // Try to partially redeem the other half of the NFT (should work this time)
        uint256 eth_before = redeemer0.balance;
        (, uint256 _initialUnclaimedFees, ) = redemptionQueue.redemptionQueueAccounting();
        redemptionQueue.partialRedeemNft(0, redeemer0, 50 ether);
        (, uint256 _finalUnclaimedFees, ) = redemptionQueue.redemptionQueueAccounting();

        // Checks
        assertEq(
            redeemer0.balance - eth_before,
            49 ether,
            "Redeemer0 should have gained ETH after redeeming the NFT (2nd half)"
        );
        assertEq(
            _finalUnclaimedFees - _initialUnclaimedFees,
            1e18,
            "1 frxETH should have been burned as the redemption fee"
        );

        // Try to redeem an already-redeemed NFT (should fail)
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        redemptionQueue.partialRedeemNft(0, redeemer0, 1 ether);

        vm.stopPrank();

        // Operator triggers redemption fee collection (specified amount)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        redemptionQueue.collectRedemptionFees(1 ether);

        // Operator triggers redemption fee collection (remaining fees)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        redemptionQueue.collectAllRedemptionFees();
    }

    function testPartialRedeemRoute2RedemptionTicketNFT() public {
        // Do the shared core logic
        _partialRedeemCore();

        // ROUTE 2: CLOSE OFF WITH A SMALLER PARTIAL REDEEM, THEN A FULL REDEEM
        // ====================================================================

        // Try to partially redeem most of the other half of the NFT (should work this time)
        uint256 eth_before = redeemer0.balance;
        (, uint256 _initialUnclaimedFees, ) = redemptionQueue.redemptionQueueAccounting();
        redemptionQueue.partialRedeemNft(0, redeemer0, 40 ether);
        assertEq(
            redeemer0.balance - eth_before,
            39.2 ether,
            "Redeemer0 should have gained ETH after redeeming the NFT (most of 2nd half)"
        );

        // Redeem the rest using fullRedeemNft
        eth_before = redeemer0.balance;
        redemptionQueue.fullRedeemNft(0, redeemer0);
        (, uint256 _finalUnclaimedFees, ) = redemptionQueue.redemptionQueueAccounting();

        // Checks
        assertEq(
            redeemer0.balance - eth_before,
            9.8 ether,
            "Redeemer0 should have gained ETH after redeeming the NFT (remainder of 2nd half)"
        );
        assertEq(
            _finalUnclaimedFees - _initialUnclaimedFees,
            1e18,
            "1 frxETH should have been burned as the redemption fee for the two redemptions"
        );

        // Try to redeem an already-redeemed NFT (should fail)
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        redemptionQueue.partialRedeemNft(0, redeemer0, 1 ether);

        vm.stopPrank();

        // Operator triggers redemption fee collection (specified amount)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        redemptionQueue.collectRedemptionFees(1 ether);

        // Operator triggers redemption fee collection (remaining fees)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        redemptionQueue.collectAllRedemptionFees();
    }

    function testcollectRedemptionFees() public {
        defaultSetup();

        // Set the redemption fee to 2% first
        hoax(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);
        redemptionQueue.setRedemptionFee(20_000);

        // Switch to redeemer0
        vm.startPrank(redeemer0);

        // Approve the 100 frxETH
        frxETH.approve(redemptionQueueAddress, 100e18);

        // Enter the queue using the approve
        redemptionQueue.enterRedemptionQueue(redeemer0, 100e18);
        assertEq(frxETH.balanceOf(redeemer0), 0, "Redeemer0 should have 0 frxETH after entering the queue");

        // Give the redemptionQueue some ETH
        vm.deal(redemptionQueueAddress, 100 ether);

        // Wait until after the maturity
        mineBlocksBySecond(2 weeks);

        // Redeem the NFT
        uint256 eth_before = redeemer0.balance;
        redemptionQueue.fullRedeemNft(0, redeemer0);
        assertEq(redeemer0.balance - eth_before, 98 ether, "Redeemer0 should have gained ETH after redeeming the NFT");

        vm.stopPrank();

        // Random person tries to collect the fee (should fail)
        hoax(redeemer0);
        vm.expectRevert(abi.encodeWithSignature("NotTimelockOperatorOrFeeRecipient()"));
        redemptionQueue.collectRedemptionFees(1 ether);

        // Operator triggers part of the fee to be collected
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        redemptionQueue.collectRedemptionFees(1 ether);

        // Operator tries trigger over-collection of fees (should fail)
        hoax(Constants.Mainnet.RQ_OPERATOR_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("ExceedsCollectedFees(uint128,uint128)", 50 ether, 1 ether));
        redemptionQueue.collectRedemptionFees(50 ether);
    }
}
