// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { FraxEtherMinter, FraxEtherMinterParams } from "src/contracts/frax-ether-minter/FraxEtherMinter.sol";
import "src/Constants.sol" as Constants;

struct DeployFrxEtherMinterReturn {
    address _address;
    bytes constructorParams;
    string contractName;
}

function deployFraxEtherMinter() returns (DeployFrxEtherMinterReturn memory _return) {
    // string memory ENVIRONMENT = "prod";
    // string memory ENVIRONMENT = "test";
    string memory ENVIRONMENT = "holesky";

    // Route depends on user
    FraxEtherMinter fraxEtherMinter;
    if (keccak256(bytes(ENVIRONMENT)) == keccak256(bytes("prod"))) {
        // Deploy the frxETH Minter
        fraxEtherMinter = new FraxEtherMinter(
            FraxEtherMinterParams({
                frxEthErc20Address: 0x5E8422345238F34275888049021821E8E08CAa1f,
                sfrxEthErc20Address: 0xac3E018457B222d93114458476f3E3416Abbe38F,
                timelockAddress: payable(0x8306300ffd616049FD7e4b0354a64Da835c1A81C),
                etherRouterAddress: payable(0xA955c1803bF1513588CB6b25901c39cb7218f71a),
                operatorRoleAddress: 0x8306300ffd616049FD7e4b0354a64Da835c1A81C
            })
        );

        // Calculate the constructor params
        _return.constructorParams = abi.encode(
            0x5E8422345238F34275888049021821E8E08CAa1f,
            0xac3E018457B222d93114458476f3E3416Abbe38F,
            0x8306300ffd616049FD7e4b0354a64Da835c1A81C,
            0xA955c1803bF1513588CB6b25901c39cb7218f71a,
            0x8306300ffd616049FD7e4b0354a64Da835c1A81C
        );
    } else if (keccak256(bytes(ENVIRONMENT)) == keccak256(bytes("test"))) {} else if (
        keccak256(bytes(ENVIRONMENT)) == keccak256(bytes("holesky"))
    ) {
        // Deploy the frxETH Minter
        fraxEtherMinter = new FraxEtherMinter(
            FraxEtherMinterParams({
                frxEthErc20Address: 0x17845EA6a9BfD2caF1b9E558948BB4999dF2656e,
                sfrxEthErc20Address: 0xa63f56985F9C7F3bc9fFc5685535649e0C1a55f3,
                timelockAddress: payable(0x625e700125FF054f75e5348497cBFab1ee4b7A40),
                etherRouterAddress: payable(0x80DA290789b16F2A785468aE7D27D910bc883C35),
                operatorRoleAddress: 0x625e700125FF054f75e5348497cBFab1ee4b7A40
            })
        );

        // Calculate the constructor params
        _return.constructorParams = abi.encode(
            0x17845EA6a9BfD2caF1b9E558948BB4999dF2656e,
            0xa63f56985F9C7F3bc9fFc5685535649e0C1a55f3,
            0x625e700125FF054f75e5348497cBFab1ee4b7A40,
            0x80DA290789b16F2A785468aE7D27D910bc883C35,
            0x625e700125FF054f75e5348497cBFab1ee4b7A40
        );
    }

    // Get return info
    _return.contractName = "FraxEtherMinter";
    _return._address = address(fraxEtherMinter);
}

contract DeployFraxEtherMinter is BaseScript {
    function run()
        external
        broadcaster
        returns (address _address, bytes memory _constructorParams, string memory _contractName)
    {
        DeployFrxEtherMinterReturn memory _return = deployFraxEtherMinter();
        console.log("_constructorParams:", string(_constructorParams));
        console.logBytes(_return.constructorParams);
        console.log("_address:", _return._address);
        _updateEnv(_return._address, _return.constructorParams, _return.contractName);
    }
}
