// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "./02_TestCMDeposit.t.sol";
import { FakeAmo } from "src/contracts/curve-amo/FakeAmo.sol";
import { FakeAmoHelper } from "src/contracts/curve-amo/FakeAmoHelper.sol";

contract TestFakeAMORecovery is CombinedMegaBaseTest {
    FakeAmo public fakeAMO;
    FakeAmoHelper public fakeAMOHelper;

    function setUp() public {
        _defaultSetup();
        /// BACKGROUND: a validator pool has been properly deployed

        // // Change to the operator so you can trigger the sweep
        // vm.startPrank(ConstantsSBTS.Mainnet.CURVEAMO_OPERATOR_ADDRESS);

        // // First set the Ether Router balance to 20 ether.
        // // Sweep 10 ETH to the Redemption Queue and/or Curve AMO(s), leave 10 ETH in the EtherRouter, drop 5 ETH into the Curve AMO
        // // This is to simulate mixed ETH in various places and force LP unwinding at the Curve AMO
        // vm.deal(etherRouterAddress, 20 ether);
        // etherRouter.sweepEther(10 ether, true); // Put in LP
        // vm.deal(curveLsdAmoAddress, 5 ether);
        // vm.stopPrank();

        // // Make sure stored utilization matches live utilization
        // checkStoredVsLiveUtilization();
    }

    function test_FakeAmoPlan() public {
        // Deploy the FakeAMO and FakeAMOHelper
        fakeAMOHelper = new FakeAmoHelper(Constants.Mainnet.TIMELOCK_ADDRESS);
        fakeAMO = new FakeAmo(Constants.Mainnet.TIMELOCK_ADDRESS, address(fakeAMOHelper));

        // Print ETH balances at step 1
        console.log("EtherRouter ETH (step 1): ", etherRouterAddress.balance);
        console.log("FakeAMO ETH (step 1): ", address(fakeAMO).balance);

        // Impersonate the EtherRouter
        vm.startPrank(Constants.Mainnet.TIMELOCK_ADDRESS);

        // Add the FakeAMO
        etherRouter.addAmo(address(fakeAMO));

        // Set the Fake AMO as the default one
        etherRouter.setPreferredDepositAndWithdrawalAMOs(address(fakeAMO), address(fakeAMO));

        // Sweep ETH into the Fake AMO
        etherRouter.sweepEther(0, false);

        // Print ETH balances at step 2
        console.log("EtherRouter ETH (step 2): ", etherRouterAddress.balance);
        console.log("FakeAMO ETH (step 2): ", address(fakeAMO).balance);
        console.log("TIMELOCK_ADDRESS ETH (step 2): ", address(Constants.Mainnet.TIMELOCK_ADDRESS).balance);

        // Remove the bytecode from the timelock to make it an EOA
        bytes memory code;
        vm.etch(Constants.Mainnet.TIMELOCK_ADDRESS, code);

        // Recover the ETH
        fakeAMO.recoverEther(10 ether);

        // Print ETH balances at step 3
        console.log("EtherRouter ETH (step 3): ", etherRouterAddress.balance);
        console.log("FakeAMO ETH (step 3): ", address(fakeAMO).balance);
        console.log("TIMELOCK_ADDRESS ETH (step 3): ", address(Constants.Mainnet.TIMELOCK_ADDRESS).balance);
    }
}
