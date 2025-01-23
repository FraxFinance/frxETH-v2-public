// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { BeaconOracle } from "src/contracts/BeaconOracle.sol";
import { CurveLsdAmo, CurveLsdAmoConstructorParams } from "src/contracts/curve-amo/CurveLsdAmo.sol";
import { CurveLsdAmoHelper } from "src/contracts/curve-amo/CurveLsdAmoHelper.sol";
import { EtherRouter } from "src/contracts/ether-router/EtherRouter.sol";
import { FraxEtherMinter, FraxEtherMinterParams } from "src/contracts/frax-ether-minter/FraxEtherMinter.sol";
import {
    FraxEtherRedemptionQueueV2,
    FraxEtherRedemptionQueueCoreParams
} from "src/contracts/frxeth-redemption-queue-v2/FraxEtherRedemptionQueueV2.sol";
import { console } from "frax-std/FraxTest.sol";
import { IFrxEth } from "src/contracts/interfaces/IFrxEth.sol";
import { LendingPool, LendingPoolParams } from "src/contracts/lending-pool/LendingPool.sol";
import { ValidatorPool } from "src/contracts/ValidatorPool.sol";
import { VariableInterestRate, VariableInterestRateParams } from "src/contracts/lending-pool/VariableInterestRate.sol";
import "src/Constants.sol" as ConstantsDep;

contract DeployAll is BaseScript {
    // AMO-related addresses
    CurveLsdAmoHelper public amoHelper;
    CurveLsdAmo public curveLsdAmo;
    EtherRouter public etherRouter;

    // Lending-related
    BeaconOracle public beaconOracle;
    LendingPool public lendingPool;
    VariableInterestRate public variableInterestRate;

    // frxETHMinter-related
    FraxEtherMinter public fraxEtherMinter;

    // FraxEtherRedemptionQueue-related
    FraxEtherRedemptionQueueV2 public redemptionQueue;

    // Constructor related
    address internal beaconOperatorAddress;
    address internal comptrollerAddress;
    address internal curveAmoOperator;
    address internal timelockAddress;
    address internal rqOperatorAddress;
    address internal frxEthAddress;
    address internal sfrxEthAddress;
    address payable internal eth2DepositAddress;

    // Example
    // (31556736 secs per year (365.24 days))
    // 1 BP = 0.0001 = 0.01%
    // (0.0001 / 31556736) * (1e18) = 3_168_895
    // 1 BP [E18] = 3_168_895
    uint64 internal constant FIFTY_BPS = 158_247_046;
    uint64 internal constant ONE_PERCENT = FIFTY_BPS * 2;
    uint64 internal constant ONE_BPS = FIFTY_BPS / 50;

    // string internal constant ENVIRONMENT = "prod";
    string internal constant ENVIRONMENT = "test";
    // string internal constant ENVIRONMENT = "holesky";

    constructor() {}

    function run() public {
        vm.startBroadcast();

        // Set addresses
        if (keccak256(bytes(ENVIRONMENT)) == keccak256(bytes("prod"))) {
            beaconOperatorAddress = ConstantsDep.Mainnet.BEACON_OPERATOR_ADDRESS;
            comptrollerAddress = ConstantsDep.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS;
            curveAmoOperator = ConstantsDep.Mainnet.CURVEAMO_OPERATOR_ADDRESS;
            timelockAddress = ConstantsDep.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS;
            rqOperatorAddress = ConstantsDep.Mainnet.RQ_OPERATOR_ADDRESS;
            frxEthAddress = ConstantsDep.Mainnet.FRX_ETH_ERC20_ADDRESS;
            sfrxEthAddress = ConstantsDep.Mainnet.SFRX_ETH_ERC20_ADDRESS;
            eth2DepositAddress = payable(ConstantsDep.Mainnet.ETH2_DEPOSIT_ADDRESS);
        } else if (keccak256(bytes(ENVIRONMENT)) == keccak256(bytes("test"))) {
            // Test
            beaconOperatorAddress = ConstantsDep.Mainnet.TIMELOCK_ADDRESS;
            comptrollerAddress = ConstantsDep.Mainnet.FRX_ETH_COMPTROLLER_ADDRESS;
            curveAmoOperator = ConstantsDep.Mainnet.CURVEAMO_OPERATOR_ADDRESS;
            timelockAddress = ConstantsDep.Mainnet.TIMELOCK_ADDRESS;
            rqOperatorAddress = ConstantsDep.Mainnet.RQ_OPERATOR_ADDRESS;
            frxEthAddress = ConstantsDep.Mainnet.FRX_ETH_ERC20_ADDRESS;
            sfrxEthAddress = ConstantsDep.Mainnet.SFRX_ETH_ERC20_ADDRESS;
            eth2DepositAddress = payable(ConstantsDep.Mainnet.ETH2_DEPOSIT_ADDRESS);
        } else if (keccak256(bytes(ENVIRONMENT)) == keccak256(bytes("holesky"))) {
            // Holesky
            beaconOperatorAddress = ConstantsDep.Holesky.BEACON_OPERATOR_ADDRESS;
            comptrollerAddress = ConstantsDep.Holesky.FRX_ETH_COMPTROLLER_ADDRESS;
            curveAmoOperator = ConstantsDep.Holesky.CURVEAMO_OPERATOR_ADDRESS;
            timelockAddress = ConstantsDep.Holesky.TIMELOCK_ADDRESS;
            rqOperatorAddress = ConstantsDep.Holesky.RQ_OPERATOR_ADDRESS;
            frxEthAddress = ConstantsDep.Holesky.FRX_ETH_ERC20_ADDRESS;
            sfrxEthAddress = ConstantsDep.Holesky.SFRX_ETH_ERC20_ADDRESS;
            eth2DepositAddress = payable(ConstantsDep.Holesky.ETH2_DEPOSIT_ADDRESS);
        }

        // Deploy the Ether Router
        etherRouter = new EtherRouter({
            _timelockAddress: timelockAddress,
            _operatorAddress: curveAmoOperator,
            _frxEthAddress: frxEthAddress
        });

        // Deploy the Frax Ether Redemption Queue
        FraxEtherRedemptionQueueCoreParams
            memory fraxEtherRedemptionQueueCoreParams = FraxEtherRedemptionQueueCoreParams({
                timelockAddress: timelockAddress,
                operatorAddress: rqOperatorAddress,
                frxEthAddress: frxEthAddress,
                sfrxEthAddress: sfrxEthAddress,
                initialQueueLengthSeconds: 2 weeks
            });
        redemptionQueue = new FraxEtherRedemptionQueueV2(fraxEtherRedemptionQueueCoreParams, payable(etherRouter));

        // Deploy the frxETH Minter
        FraxEtherMinterParams memory fraxEtherMinterParams = FraxEtherMinterParams({
            frxEthErc20Address: frxEthAddress,
            sfrxEthErc20Address: sfrxEthAddress,
            timelockAddress: payable(timelockAddress),
            etherRouterAddress: payable(etherRouter),
            operatorRoleAddress: comptrollerAddress
        });
        fraxEtherMinter = new FraxEtherMinter(fraxEtherMinterParams);

        // Only prod has the Curve AMO. Disable for HOLESKY
        CurveLsdAmoConstructorParams memory curveLsdAmoConstructorParams;
        if (keccak256(bytes(ENVIRONMENT)) != keccak256(bytes("holesky"))) {
            // Deploy the Curve LSD AMO
            // Get the pool config data
            bytes memory _poolConfigDataFrxETHWETH = abi.encode(
                1, // frxEthIndex
                0, // ethIndex
                ConstantsDep.Mainnet.FRX_ETH_WETH_POOL, // pool address
                ConstantsDep.Mainnet.FRX_ETH_WETH_LP, // lpTokenAddress
                CurveLsdAmo.LpAbiType.LSDWETH,
                CurveLsdAmo.FrxSfrxType.FRXETH, // FrxSfrxType
                CurveLsdAmo.EthType.WETH
            );

            // Get the cvxLP and stkcvxLP config data
            bytes memory _configDataFrxETHWETH = abi.encode(
                ConstantsDep.Mainnet.CVXFRX_ETH_WETH_BASEREWARDPOOL, // BaseRewardPool address
                63 // Convex pool id (pid)
            );

            // Deploy the Curve LSD AMO helper
            amoHelper = new CurveLsdAmoHelper(curveAmoOperator);

            // Deploy the Curve AMO
            curveLsdAmoConstructorParams = CurveLsdAmoConstructorParams({
                timelockAddress: timelockAddress,
                operatorAddress: curveAmoOperator,
                amoHelperAddress: address(amoHelper),
                frxEthMinterAddress: payable(fraxEtherMinter),
                etherRouterAddress: payable(etherRouter),
                poolConfigData: _poolConfigDataFrxETHWETH,
                cvxAndStkcvxData: _configDataFrxETHWETH
            });
            curveLsdAmo = new CurveLsdAmo(curveLsdAmoConstructorParams);
        }

        // Deploy the BeaconOracle
        beaconOracle = new BeaconOracle({ _timelockAddress: timelockAddress, _operatorAddress: beaconOperatorAddress });

        // Deploy the Deploy the Interest Rate Contract
        // ======================================
        // @param _suffix The suffix of the contract name
        // @param _vertexUtilization The utilization at which the slope increases
        // @param _vertexRatePercentOfDelta The percent of the delta between max and min, defines vertex rate
        // @param _minUtil The minimum utilization wherein no adjustment to full utilization and vertex rates occurs
        // @param _maxUtil The maximum utilization wherein no adjustment to full utilization and vertex rates occurs
        // @param _zeroUtilizationRate The interest rate (per second) when utilization is 0%
        // @param _minFullUtilizationRate The minimum interest rate at 100% utilization
        // @param _maxFullUtilizationRate The maximum interest rate at 100% utilization
        // @param _rateHalfLife The half life parameter for interest rate adjustments
        // https://docs.frax.finance/fraxlend/advanced-concepts/interest-rates#variable-rate-v2-interest-rate
        // variableInterestRate = new VariableInterestRate({
        //     _suffix: "Frax Ether Variable Rate Contract",
        //     // _vertexUtilization: 1e5,
        //     _vertexUtilization: 85e3, // 85%
        //     _vertexRatePercentOfDelta: 1e18,
        //     _minUtil: 0,
        //     _maxUtil: 1e5,
        //     _zeroUtilizationRate: 10 * ONE_PERCENT,
        //     _minFullUtilizationRate: 10 * ONE_PERCENT,
        //     _maxFullUtilizationRate: 10_000 * ONE_PERCENT,
        //     _rateHalfLife: 8 days
        // });
        VariableInterestRateParams memory variableInterestRateParams = VariableInterestRateParams({
            suffix: "Frax Ether Variable Rate Contract",
            vertexUtilization: 87_500, // 87.5%
            vertexRatePercentOfDelta: 0.2e18, // 0.2%
            minUtil: 75_000, // MAX_TARGET_UTIL
            maxUtil: 85_000,
            zeroUtilizationRate: ONE_PERCENT, // 1%
            minFullUtilizationRate: 10 * ONE_PERCENT, // 10%
            maxFullUtilizationRate: 10_000 * ONE_PERCENT, // 10000%
            rateHalfLife: 2 days
        });
        variableInterestRate = new VariableInterestRate(variableInterestRateParams);

        // Deploy the Lending Pool
        LendingPoolParams memory lendingPoolParams = LendingPoolParams({
            frxEthAddress: frxEthAddress,
            timelockAddress: timelockAddress,
            etherRouterAddress: payable(etherRouter),
            beaconOracleAddress: address(beaconOracle),
            redemptionQueueAddress: payable(redemptionQueue),
            interestRateCalculatorAddress: address(variableInterestRate),
            eth2DepositAddress: eth2DepositAddress,
            fullUtilizationRate: 100 * ONE_PERCENT
        });
        lendingPool = new LendingPool(lendingPoolParams);

        console.log("EtherRouter: ", address(etherRouter));
        console.log("FraxEtherRedemptionQueueV2: ", address(redemptionQueue));
        console.log("FraxEtherMinter: ", address(fraxEtherMinter));
        console.log("CurveLsdAmoHelper: ", address(amoHelper));
        console.log("CurveLsdAmo: ", address(curveLsdAmo));
        console.log("BeaconOracle: ", address(beaconOracle));
        console.log("VariableInterestRate: ", address(variableInterestRate));
        console.log("LendingPool: ", address(lendingPool));

        console.log("===================== VERIFICATION INFO =====================");
        console.log("MAY NEED TO REMOVE THE INITIAL 0x FROM BELOW WHEN VERIFYING");

        console.log("------ EtherRouter params (abi.encode)------");
        console.logBytes(abi.encode(timelockAddress, curveAmoOperator, frxEthAddress));
        console.log("%s src/contracts/ether-router/EtherRouter.sol:EtherRouter", address(etherRouter));

        console.log("------ FraxEtherRedemptionQueueCoreParams + payable(etherRouter) (abi.encode)------");
        console.logBytes(abi.encode(fraxEtherRedemptionQueueCoreParams, payable(etherRouter)));
        console.log(
            "%s src/contracts/frxeth-redemption-queue-v2/FraxEtherRedemptionQueueV2.sol:FraxEtherRedemptionQueueV2",
            address(redemptionQueue)
        );

        console.log("------ FraxEtherMinterParams (abi.encode)------");
        console.logBytes(abi.encode(fraxEtherMinterParams));
        console.log("%s src/contracts/frax-ether-minter/FraxEtherMinter.sol:FraxEtherMinter", address(fraxEtherMinter));

        console.log("------ CurveLsdAmoHelper params (abi.encode)------");
        console.logBytes(abi.encode(curveAmoOperator));
        console.log("%s src/contracts/curve-amo/CurveLsdAmoHelper.sol:CurveLsdAmoHelper", address(amoHelper));

        console.log("------ CurveLsdAmoConstructorParams params (abi.encode)------");
        console.logBytes(abi.encode(curveLsdAmoConstructorParams));
        console.log("%s src/contracts/curve-amo/CurveLsdAmo.sol:CurveLsdAmo", address(curveLsdAmo));

        console.log("------ BeaconOracle params (abi.encode)------");
        console.logBytes(abi.encode(timelockAddress, beaconOperatorAddress));
        console.log("%s src/contracts/BeaconOracle.sol:BeaconOracle", address(beaconOracle));

        console.log("------ VariableInterestRateParams (abi.encode)------");
        console.logBytes(abi.encode(variableInterestRateParams));
        console.log(
            "%s src/contracts/lending-pool/VariableInterestRate.sol:VariableInterestRate",
            address(variableInterestRate)
        );

        console.log("------ LendingPoolParams (abi.encode)------");
        console.logBytes(abi.encode(lendingPoolParams));
        console.log("%s src/contracts/lending-pool/LendingPool.sol:LendingPool", address(lendingPool));

        // !!! DO THESE MANUALLY AFTER DEPLOYMENT !!!
        // !!! DO THESE MANUALLY AFTER DEPLOYMENT !!!
        // !!! DO THESE MANUALLY AFTER DEPLOYMENT !!!
        console.log("!!! DO THESE MANUALLY AFTER DEPLOYMENT (SEE DEPLOYALL SCRIPT) !!!");
        console.log("!!! DO THESE MANUALLY AFTER DEPLOYMENT (SEE DEPLOYALL SCRIPT) !!!");
        console.log("!!! DO THESE MANUALLY AFTER DEPLOYMENT (SEE DEPLOYALL SCRIPT) !!!");

        if (keccak256(bytes(ENVIRONMENT)) != keccak256(bytes("prod"))) {
            // As FRXETH_COMPTROLLER
            // IFrxEth(frxEthAddress).addMinter(payable(fraxEtherMinter));
            // As TIMELOCK_ADDRESS
            // beaconOracle.setLendingPool(payable(lendingPool));
            // etherRouter.addAmo(payable(curveLsdAmo));
            // etherRouter.setPreferredDepositAndWithdrawalAMOs(payable(curveLsdAmo), payable(curveLsdAmo));
            // etherRouter.setLendingPool(payable(lendingPool));
            // etherRouter.setRedemptionQueue(payable(redemptionQueue));
        }
        vm.stopBroadcast();
        if (keccak256(bytes(ENVIRONMENT)) != keccak256(bytes("test"))) {
            console.log("====== SLEEPING FOR 15 SECS ======");
            vm.sleep(15_000);
            console.log("<<< Sleeping done >>>");

            console.log("====== STARTING TO VERIFY ======");
        }
    }
}
