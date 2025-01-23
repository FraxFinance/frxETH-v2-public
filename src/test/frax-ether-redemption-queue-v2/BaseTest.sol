// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import { IFrxEth } from "src/contracts/frxeth-redemption-queue-v2/interfaces/IFrxEth.sol";
import { ISfrxEth } from "src/contracts/frxeth-redemption-queue-v2/interfaces/ISfrxEth.sol";
import { IWETH } from "src/contracts/interfaces/IWETH.sol";
import { IEtherRouter } from "src/contracts/ether-router/interfaces/IEtherRouter.sol";
import { deployFraxEtherRedemptionQueueV2 } from "src/script/DeployFraxEtherRedemptionQueueV2.s.sol";
import { console } from "frax-std/FraxTest.sol";
import {
    FraxEtherRedemptionQueueV2,
    FraxEtherRedemptionQueueCoreParams,
    FraxEtherRedemptionQueueCore
} from "../../contracts/frxeth-redemption-queue-v2/FraxEtherRedemptionQueueV2.sol";
import { CurveLsdAmo } from "src/contracts/curve-amo/CurveLsdAmo.sol";
import { CurveLsdAmoHelper } from "src/contracts/curve-amo/CurveLsdAmoHelper.sol";
import { BeaconOracle } from "src/contracts/BeaconOracle.sol";
import { EtherRouter } from "src/contracts/ether-router/EtherRouter.sol";
import { LendingPool, LendingPoolParams } from "src/contracts/lending-pool/LendingPool.sol";
import { VariableInterestRate } from "src/contracts/lending-pool/VariableInterestRate.sol";
import { IDepositContract, DepositContract } from "src/contracts/interfaces/IDepositContract.sol";
import { ValidatorPool } from "src/contracts/ValidatorPool.sol";
import { FraxEtherMinter, FraxEtherMinterParams } from "src/contracts/frax-ether-minter/FraxEtherMinter.sol";
import { FraxTest } from "frax-std/FraxTest.sol";
import { SigUtils } from "./utils/SigUtils.sol";
import { DeployAll } from "src/script/DeployAll.s.sol";
import "./Constants.sol" as Constants;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseTest is FraxTest, Constants.Helper {
    uint256 internal redeemer0PrivateKey;
    uint256 internal redeemer1PrivateKey;
    uint256 internal redeemer2PrivateKey;
    address payable internal redeemer0;
    address payable internal redeemer1;
    address payable internal redeemer2;
    address payable internal alice; // redeemer0
    address payable internal bob; // redeemer1
    address payable internal charlie; // redeemer2

    IFrxEth public frxETH = IFrxEth(0x5E8422345238F34275888049021821E8E08CAa1f);
    ISfrxEth public sfrxETH = ISfrxEth(0xac3E018457B222d93114458476f3E3416Abbe38F);
    IWETH public WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    SigUtils public sigUtils_frxETH;
    SigUtils public sigUtils_sfrxETH;

    // Used in tests
    DeployAll public deployContract;

    // AMO-related addresses
    CurveLsdAmoHelper public amoHelper;
    CurveLsdAmo public curveLsdAmo;
    address payable public curveLsdAmoAddress;
    EtherRouter public etherRouter;
    address payable public etherRouterAddress;

    // Validator pool
    ValidatorPool public validatorPool;
    address payable public validatorPoolAddress;
    address payable public validatorPoolOwner;

    // Redemption Queue
    FraxEtherRedemptionQueueV2 public redemptionQueue;
    address payable public redemptionQueueAddress;

    // Other contracts
    BeaconOracle public beaconOracle;
    address public beaconOracleAddress;
    LendingPool public lendingPool;
    address payable public lendingPoolAddress;
    VariableInterestRate public variableInterestRate;
    address public variableInterestRateAddress;

    // frxETHMinter-related
    FraxEtherMinter public fraxEtherMinter;
    address payable public fraxEtherMinterAddress;

    uint256 public initialSfrxETHFromRedeemer0;

    function defaultSetup() internal {
        // vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_105_462);
        // vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_000_000); // Should be 19000000
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 20_000_000); // Should be 20000000

        // Deploy the contracts
        // ======================

        // Used for the permit test
        sigUtils_frxETH = new SigUtils(frxETH.DOMAIN_SEPARATOR());
        sigUtils_sfrxETH = new SigUtils(sfrxETH.DOMAIN_SEPARATOR());

        // Deploy core contracts
        console.log("<<<Deploy core contracts>>>");
        deployContract = DeployAll(new DeployAll());
        deployContract.run();

        // Instantiate the new contracts
        fraxEtherMinter = deployContract.fraxEtherMinter();
        beaconOracle = deployContract.beaconOracle();
        amoHelper = deployContract.amoHelper();
        curveLsdAmo = deployContract.curveLsdAmo();
        etherRouter = deployContract.etherRouter();
        redemptionQueue = deployContract.redemptionQueue();
        variableInterestRate = deployContract.variableInterestRate();
        lendingPool = deployContract.lendingPool();

        // Set convenience addresses
        beaconOracleAddress = address(beaconOracle);
        curveLsdAmoAddress = payable(curveLsdAmo);
        etherRouterAddress = payable(etherRouter);
        redemptionQueueAddress = payable(redemptionQueue);
        variableInterestRateAddress = address(variableInterestRate);
        lendingPoolAddress = payable(lendingPool);
        fraxEtherMinterAddress = payable(fraxEtherMinter);

        // Set up redeemers
        redeemer0PrivateKey = 0xA11CE;
        redeemer1PrivateKey = 0xB0B;
        redeemer2PrivateKey = 0xC6af11E;
        redeemer0 = payable(vm.addr(redeemer0PrivateKey));
        redeemer1 = payable(vm.addr(redeemer1PrivateKey));
        redeemer2 = payable(vm.addr(redeemer2PrivateKey));
        alice = payable(vm.addr(redeemer0PrivateKey));
        bob = payable(vm.addr(redeemer1PrivateKey));
        charlie = payable(vm.addr(redeemer2PrivateKey));

        // Give redeemer0 200 frxETH
        hoax(Constants.Mainnet.FRXETH_WHALE);
        frxETH.transfer(redeemer0, 200e18);

        // Give redeemer1 200 frxETH
        hoax(Constants.Mainnet.FRXETH_WHALE);
        frxETH.transfer(redeemer1, 200e18);

        // Give redeemer2 200 frxETH
        hoax(Constants.Mainnet.FRXETH_WHALE);
        frxETH.transfer(redeemer2, 200e18);

        // Label redeemers
        vm.label(redeemer0, "redeemer0<ALICE>");
        vm.label(redeemer1, "redeemer1<BOB>");
        vm.label(redeemer2, "redeemer2<CHARLIE>");

        // Finish configurations after deployment (frxETH Comptroller)
        // ===========================
        vm.startPrank(frxETH.owner());

        // Add the new frxETHMinter as a minter for frxETH
        frxETH.addMinter(address(fraxEtherMinter));

        vm.stopPrank();

        // Finish configurations after deployment (Timelock)
        console.log("<<<Finish configurations after deployment (Timelock)>>>");
        vm.startPrank(Constants.Mainnet.TIMELOCK_ADDRESS_REAL);

        // Set the lending pool for the beacon oracle
        beaconOracle.setLendingPool(lendingPoolAddress);

        // Set the lending pool for Ether Router
        etherRouter.setLendingPool(lendingPoolAddress);

        // Set the redemption queue address on the ether router
        etherRouter.setRedemptionQueue(redemptionQueueAddress);

        // Set the redemption fee to 0.05% because of Curve 0.03% + extra 0.02% margin of safety
        // If set, may be defeating the purpose of the 1:1 redemption queue.
        // lendingPool.setRedemptionFee(5000);

        // // Set the withdrawal fee to 0.03% because of Curve (0.03%)
        // lendingPool.setVPoolWithdrawalFee(3000);

        // Add the Curve AMO to the Ether Router and set it as the default deposit and withdrawal AMO
        etherRouter.addAmo(payable(curveLsdAmo));
        etherRouter.setPreferredDepositAndWithdrawalAMOs(payable(curveLsdAmo), payable(curveLsdAmo));

        // Fix the operator address
        redemptionQueue.setOperator(Constants.Mainnet.RQ_OPERATOR_ADDRESS);

        vm.stopPrank();

        // Deal out ETH
        // ===========================

        // // Transfer 1000 ETH into the Curve AMO
        // vm.deal(curveLsdAmoAddress, 1000 ether);

        // // Transfer 1000 ETH into the EtherRouter
        // vm.deal(etherRouterAddress, 1000 ether);

        // Redeemer0 conversions
        // ==============================

        // Redeemer0 converts 100 frxETH to sfrxETH
        hoax(redeemer0);
        frxETH.approve(address(sfrxETH), 100e18);
        hoax(redeemer0);
        initialSfrxETHFromRedeemer0 = sfrxETH.deposit(100e18, redeemer0);

        // Redeemer1 converts 100 frxETH to sfrxETH
        hoax(redeemer1);
        frxETH.approve(address(sfrxETH), 100e18);
        hoax(redeemer1);
        sfrxETH.deposit(100e18, redeemer1);

        // Redeemer2 converts 100 frxETH to sfrxETH
        hoax(redeemer2);
        frxETH.approve(address(sfrxETH), 100e18);
        hoax(redeemer2);
        sfrxETH.deposit(100e18, redeemer2);
    }
}
