// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { IFrxEth } from "src/contracts/frxeth-redemption-queue-v2/interfaces/IFrxEth.sol";
import { EtherRouter } from "src/contracts/ether-router/EtherRouter.sol";
import {
    FraxEtherRedemptionQueueV2,
    FraxEtherRedemptionQueueCore,
    FraxEtherRedemptionQueueCoreParams
} from "src/contracts/frxeth-redemption-queue-v2/FraxEtherRedemptionQueueV2.sol";
import "src/test/frax-ether-redemption-queue-v2/Constants.sol" as ConstantsDep;

struct DeployFraxEtherRedemptionQueueV2Return {
    address _address;
    bytes constructorParams;
    string contractName;
}

function deployFraxEtherRedemptionQueueV2() returns (DeployFraxEtherRedemptionQueueV2Return memory _return) {
    // Deploy the Ether Router
    EtherRouter etherRouter = new EtherRouter({
        _timelockAddress: ConstantsDep.Mainnet.TIMELOCK_ADDRESS,
        _operatorAddress: ConstantsDep.Mainnet.RQ_OPERATOR_ADDRESS,
        _frxEthAddress: ConstantsDep.Mainnet.FRXETH_ADDRESS
    });

    // Mainnet
    FraxEtherRedemptionQueueCoreParams memory _params = FraxEtherRedemptionQueueCoreParams({
        timelockAddress: ConstantsDep.Mainnet.TIMELOCK_ADDRESS,
        operatorAddress: ConstantsDep.Mainnet.RQ_OPERATOR_ADDRESS,
        frxEthAddress: ConstantsDep.Mainnet.FRXETH_ADDRESS,
        sfrxEthAddress: ConstantsDep.Mainnet.SFRXETH_ADDRESS,
        initialQueueLengthSeconds: 604_800 // One week
    });

    // Holesky
    // FraxEtherRedemptionQueueCoreParams memory _params = FraxEtherRedemptionQueueCoreParams({
    //     timelockAddress: 0x0efB35a6D6b14e7F5eEEbAD10A2145A68C99772D,
    //     operatorAddress: 0x0efB35a6D6b14e7F5eEEbAD10A2145A68C99772D,
    //     frxEthAddress: 0x17845EA6a9BfD2caF1b9E558948BB4999dF2656e,
    //     sfrxEthAddress: 0xa63f56985F9C7F3bc9fFc5685535649e0C1a55f3,
    //     initialQueueLengthSeconds: 300 // 5 minutes
    // });

    _return.constructorParams = abi.encode(_params);
    _return.contractName = "FraxEtherRedemptionQueueV2";
    _return._address = address(new FraxEtherRedemptionQueueV2(_params, payable(etherRouter)));
}

contract DeployFraxEtherRedemptionQueueV2 is BaseScript {
    function run()
        external
        broadcaster
        returns (address _address, bytes memory _constructorParams, string memory _contractName)
    {
        DeployFraxEtherRedemptionQueueV2Return memory _return = deployFraxEtherRedemptionQueueV2();
        console.log("_constructorParams:", string(abi.encode(_constructorParams)));
        console.logBytes(_return.constructorParams);
        console.log("_address:", _return._address);
        _updateEnv(_return._address, _return.constructorParams, _return.contractName);
    }
}
