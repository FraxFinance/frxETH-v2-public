// SPDX-License-Identifier: ISC
pragma solidity >=0.8.0;

import { TestBase } from "forge-std/Test.sol";

library Mainnet {
    address internal constant BEEHARVESTER_ADDRESS = 0x733371d7C15ACECF9e120dd037D6BcDb6E069148;
    address internal constant FRXETH_WHALE = 0x505603e2440b44C1602b44D0Eb8385399b3F7bab;
    address internal constant FRXETH_ADDRESS = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address internal constant SFRXETH_ADDRESS = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address internal constant RQ_OPERATOR_ADDRESS = 0x5180db0237291A6449DdA9ed33aD90a38787621c;
    address internal constant TIMELOCK_ADDRESS = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;
    address internal constant TIMELOCK_ADDRESS_REAL = 0x8412ebf45bAC1B340BbE8F318b928C466c4E39CA;
}

abstract contract Helper is TestBase {
    constructor() {
        labelConstants();
    }

    function labelConstants() public {
        vm.label(0x733371d7C15ACECF9e120dd037D6BcDb6E069148, "Constants.BEEHARVESTER_ADDRESS");
        vm.label(0x505603e2440b44C1602b44D0Eb8385399b3F7bab, "Constants.FRXETH_WHALE");
        vm.label(0x5E8422345238F34275888049021821E8E08CAa1f, "Constants.FRXETH_ADDRESS");
        vm.label(0xac3E018457B222d93114458476f3E3416Abbe38F, "Constants.SFRXETH_ADDRESS");
        vm.label(0x5180db0237291A6449DdA9ed33aD90a38787621c, "Constants.RQ_OPERATOR_ADDRESS");
        vm.label(0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27, "Constants.TIMELOCK_ADDRESS");
        vm.label(0x8412ebf45bAC1B340BbE8F318b928C466c4E39CA, "Constants.TIMELOCK_ADDRESS_REAL");
    }
}
