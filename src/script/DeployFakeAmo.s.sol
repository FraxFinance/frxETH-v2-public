// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { FakeAmo } from "src/contracts/curve-amo/FakeAmo.sol";
import { FakeAmoHelper } from "src/contracts/curve-amo/FakeAmoHelper.sol";
import { console } from "frax-std/FraxTest.sol";
import "src/Constants.sol" as ConstantsDep;

contract DeployFakeAmo is BaseScript {
    // AMO-related addresses
    FakeAmoHelper public fakeAmoHelper;
    FakeAmo public fakeAmo;

    // Timelock
    address timelockAddress;

    string internal constant ENVIRONMENT = "prod";
    // string internal constant ENVIRONMENT = "test";
    // string internal constant ENVIRONMENT = "holesky";

    constructor() {}

    function run() public {
        vm.startBroadcast();

        // Set addresses
        if (keccak256(bytes(ENVIRONMENT)) == keccak256(bytes("prod"))) {
            timelockAddress = ConstantsDep.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS;
        } else if (keccak256(bytes(ENVIRONMENT)) == keccak256(bytes("test"))) {
            // Test
            timelockAddress = ConstantsDep.Mainnet.TIMELOCK_ADDRESS;
        } else if (keccak256(bytes(ENVIRONMENT)) == keccak256(bytes("holesky"))) {
            // Holesky
            timelockAddress = ConstantsDep.Holesky.TIMELOCK_ADDRESS;
        }

        // Deploy the FakeAMO and FakeAMOHelper
        fakeAmoHelper = new FakeAmoHelper(timelockAddress);
        fakeAmo = new FakeAmo(timelockAddress, address(fakeAmoHelper));

        console.log("FakeAmoHelper: ", address(fakeAmoHelper));
        console.log("FakeAmo: ", address(fakeAmo));

        console.log("===================== VERIFICATION INFO =====================");
        console.log("MAY NEED TO REMOVE THE INITIAL 0x FROM BELOW WHEN VERIFYING");

        console.log("------ FakeAmoHelper params (abi.encode)------");
        console.logBytes(abi.encode(timelockAddress));
        console.log("%s src/contracts/curve-amo/FakeAmoHelper.sol:FakeAmoHelper", address(fakeAmoHelper));

        console.log("------ FakeAmo (abi.encode)------");
        console.logBytes(abi.encode(timelockAddress, address(fakeAmoHelper)));
        console.log("%s src/contracts/curve-amo/FakeAmo.sol:FakeAmo", address(fakeAmo));
        vm.stopBroadcast();
    }
}
