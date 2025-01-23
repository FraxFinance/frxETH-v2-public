// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

// interface ILendingPool {
//     event AddInterest(uint256 interestEarned, uint256 rate, uint256 feesAmount, uint256 feesShare);
//     event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
//     event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
//     event Erc20Recovered(address token, uint256 amount);
//     event EtherRecovered(uint256 amount);
//     event FeesCollected(address _recipient, uint96 _collectAmt);
//     event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
//     event RedemptionQueueEntered(
//         address redeemer,
//         uint256 nftId,
//         uint256 amount,
//         uint32 maturityTimestamp,
//         uint96 redemptionFeeAmount
//     );
//     event RedemptionTicketNftRedeemed(address sender, address recipient, uint256 nftId, uint96 amountOut);
//     event SetBeaconOracle(address indexed oldBeaconOracle, address indexed newBeaconOracle);
//     event SetEtherRouter(address indexed oldEtherRouter, address indexed newEtherRouter);
//     event SetMaxOperatorQueueLength(uint32 _newMaxQueueLength);
//     event SetQueueLength(uint32 _newLength);
//     event SetRedemptionFee(uint32 _newFee);
//     event TimelockTransferStarted(address indexed previousTimelock, address indexed newTimelock);
//     event TimelockTransferred(address indexed previousTimelock, address indexed newTimelock);
//     event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
//     event UpdateRate(
//         uint256 oldRatePerSec,
//         uint256 oldFullUtilizationRate,
//         uint256 newRatePerSec,
//         uint256 newFullUtilizationRate
//     );

//     struct CurrentRateInfo {
//         uint64 lastTimestamp;
//         uint64 ratePerSec;
//         uint64 fullUtilizationRate;
//     }

//     struct VaultAccount {
//         uint256 amount;
//         uint256 shares;
//     }

//     function DEFAULT_CREDIT_PER_VALIDATOR_I48_E12() external view returns (uint256);

//     function ETH2_DEPOSIT_CONTRACT() external view returns (address);

//     function FEE_PRECISION() external view returns (uint32);

//     function INTEREST_RATE_PRECISION() external view returns (uint256);

//     function UTILIZATION_PRECISION() external view returns (uint256);

//     function acceptTransferTimelock() external;

//     function addInterest(
//         bool _returnAccounting
//     )
//         external
//         returns (
//             uint256 _interestEarned,
//             uint256 _feesAmount,
//             uint256 _feesShare,
//             CurrentRateInfo memory _currentRateInfo,
//             VaultAccount memory _totalBorrow
//         );

//     function approve(address to, uint256 tokenId) external;

//     function approveValidator(bytes memory _validatorPublicKey) external;

//     function balanceOf(address owner) external view returns (uint256);

//     function beaconOracle() external view returns (address);

//     function borrow(address _recipient, uint256 _borrowAmount) external;

//     function collectRedemptionFees(address _recipient, uint96 _collectAmt) external;

//     function currentRateInfo()
//         external
//         view
//         returns (uint64 lastTimestamp, uint64 ratePerSec, uint64 fullUtilizationRate);

//     function deployValidatorPool(address _validatorPoolOwnerAddress) external returns (address _pairAddress);

//     function enterRedemptionQueue(address _recipient, uint96 _amountToRedeem) external;

//     function enterRedemptionQueueWithPermit(
//         uint96 _amountToRedeem,
//         address _recipient,
//         uint256 _deadline,
//         uint8 _v,
//         bytes32 _r,
//         bytes32 _s
//     ) external;

//     function etherRouter() external view returns (address);

//     function finalDepositValidator(
//         bytes memory _validatorPublicKey,
//         bytes memory _withdrawalCredentials,
//         bytes memory _validatorSignature,
//         bytes32 _depositDataRoot
//     ) external;

//     function frxEth() external view returns (address);

//     function getApproved(uint256 tokenId) external view returns (address);

//     function getUtilization() external view returns (uint256 _utilization);

//     function initialDepositValidator(bytes memory _validatorPublicKey, uint256 _depositAmount) external;

//     function interestAccrued() external view returns (uint256);

//     function interestAvailableForWithdrawal() external view returns (uint256);

//     function rateCalculator() external view returns (address);

//     function isApprovedForAll(address owner, address operator) external view returns (bool);

//     function isSolvent(address _validatorPool) external view returns (bool _isSolvent);

//     function liquidate(address _validatorPoolAddress, uint256 _amountToLiquidate) external;

//     function maxOperatorQueueLength() external view returns (uint32);

//     function name() external view returns (string memory);

//     function nftInformation(uint256 nftId) external view returns (bool hasBeenRedeemed, uint32 maturity, uint96 amount);

//     function operatorAddress() external view returns (address);

//     function ownerOf(uint256 tokenId) external view returns (address);

//     function pendingTimelockAddress() external view returns (address);

//     function previewAddInterest()
//         external
//         view
//         returns (
//             uint256 _interestEarned,
//             uint256 _feesAmount,
//             uint256 _feesShare,
//             CurrentRateInfo memory _newCurrentRateInfo,
//             VaultAccount memory _totalBorrow
//         );

//     function recoverErc20(address _tokenAddress, uint256 _tokenAmount) external;

//     function recoverEther(uint256 amount) external;

//     function redeemRedemptionTicketNft(uint256 _nftId, address _recipient) external;

//     function redemptionQueueState() external view returns (uint32 nextNftId, uint32 queueLength, uint32 redemptionFee);

//     function renounceTimelock() external;

//     function repay(address _targetPool) external payable;

//     function safeTransferFrom(address from, address to, uint256 tokenId) external;

//     function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) external;

//     function setApprovalForAll(address operator, bool approved) external;

//     function setCreationCode(bytes memory _creationCode) external;

//     function setMaxOperatorQueueLength(uint32 _newMaxQueueLength) external;

//     function setOperator() external;

//     function setOperator(address _newOperator) external;

//     function setQueueLength(uint32 _newLength) external;

//     function setRedemptionFee(uint32 _newFee) external;

//     function setVPoolBorrowAllowance(address _validatorPoolAddress, uint128 _newBorrowAllowance) external;

//     function setVPoolCreditPerValidatorI48_E12(
//         address _validatorPoolAddress,
//         uint48 _newCreditPerValidatorI48_E12
//     ) external;

//     function setVPoolValidatorCount(address _validatorPoolAddress, uint32 _newValidatorCount) external;

//     function supportsInterface(bytes4 interfaceId) external view returns (bool);

//     function symbol() external view returns (string memory);

//     function timelockAddress() external view returns (address);

//     function toBorrowAmount(address _validatorPool, uint256 _shares) external view returns (uint256 _borrowAmount);

//     function tokenURI(uint256 tokenId) external view returns (string memory);

//     function totalBorrow() external view returns (uint256 amount, uint256 shares);

//     function transferFrom(address from, address to, uint256 tokenId) external;

//     function transferTimelock(address _newTimelock) external;

//     function validatorDepositInfo(
//         bytes memory _validatorPublicKey
//     ) external view returns (uint32 whenValidatorApproved, uint96 userDepositedEther, uint96 lendingPoolDepositedEther);

//     function validatorPoolAccounts(
//         address _validatorPool
//     )
//         external
//         view
//         returns (
//             bool isInitialized,
//             bool wasLiquidated,
//             uint32 lastWithdrawal,
//             uint32 validatorCount,
//             uint48 creditPerValidatorI48_E12,
//             uint128 borrowAllowance,
//             uint256 borrowShares
//         );

//     function validatorPoolCreationCodeAddress() external view returns (address);
// }
interface ILendingPool {
    struct CurrentRateInfo {
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint64 fullUtilizationRate;
    }

    struct VaultAccount {
        uint256 amount;
        uint256 shares;
    }

    function DEFAULT_CREDIT_PER_VALIDATOR_I48_E12() external view returns (uint48);
    function ETH2_DEPOSIT_CONTRACT() external view returns (address);
    function INTEREST_RATE_PRECISION() external view returns (uint256);
    function MAXIMUM_CREDIT_PER_VALIDATOR_I48_E12() external view returns (uint48);
    function MAX_WITHDRAWAL_FEE() external view returns (uint256);
    function MINIMUM_BORROW_AMOUNT() external view returns (uint256);
    function MISSING_CREDPERVAL_MULT() external view returns (uint256);
    function UTILIZATION_PRECISION() external view returns (uint256);
    function acceptTransferTimelock() external;
    function addInterest(
        bool _returnAccounting
    )
        external
        returns (
            uint256 _interestEarned,
            uint256 _feesAmount,
            uint256 _feesShare,
            CurrentRateInfo memory _currentRateInfo,
            VaultAccount memory _totalBorrow
        );
    function beaconOracle() external view returns (address);
    function borrow(address _recipient, uint256 _borrowAmount) external;
    function currentRateInfo()
        external
        view
        returns (uint64 lastTimestamp, uint64 ratePerSec, uint64 fullUtilizationRate);
    function deployValidatorPool(
        address _validatorPoolOwnerAddress,
        bytes32 _extraSalt
    ) external returns (address _poolAddress);
    function entrancyStatus() external view returns (bool _isEntered);
    function etherRouter() external view returns (address);
    function finalDepositValidator(
        bytes memory _validatorPublicKey,
        bytes memory _withdrawalCredentials,
        bytes memory _validatorSignature,
        bytes32 _depositDataRoot
    ) external;
    function frxETH() external view returns (address);
    function getLastWithdrawalTimestamp(
        address _validatorPoolAddress
    ) external returns (uint32 _lastWithdrawalTimestamp);
    function getLastWithdrawalTimestamps(
        address[] memory _validatorPoolAddresses
    ) external returns (uint32[] memory _lastWithdrawalTimestamps);
    function getMaxBorrow() external view returns (uint256 _maxBorrow);
    function getUtilization(bool _forceLive, bool _updateCache) external returns (uint256 _utilization);
    function getUtilizationView() external view returns (uint256 _utilization);
    function initialDepositValidator(bytes memory _validatorPublicKey, uint256 _depositAmount) external;
    function interestAccrued() external view returns (uint256);
    function isLiquidator(address _addr) external view returns (bool _canLiquidate);
    function isSolvent(address _validatorPoolAddress) external view returns (bool _isSolvent);
    function isValidatorApproved(bytes memory _publicKey) external view returns (bool _isApproved);
    function liquidate(address _validatorPoolAddress, uint256 _amountToLiquidate) external;
    function pendingTimelockAddress() external view returns (address);
    function previewAddInterest()
        external
        view
        returns (
            uint256 _interestEarned,
            uint256 _feesAmount,
            uint256 _feesShare,
            CurrentRateInfo memory _newCurrentRateInfo,
            VaultAccount memory _totalBorrow
        );
    function previewValidatorAccounts(address _validatorPoolAddress) external view returns (VaultAccount memory);
    function rateCalculator() external view returns (address);
    function recoverStrandedEth() external returns (uint256 _amountRecovered);
    function redemptionQueue() external view returns (address);
    function registerWithdrawal(address _endRecipient, uint256 _sentBackAmount, uint256 _feeAmount) external;
    function renounceTimelock() external;
    function repay(address _targetPool) external payable;
    function setBeaconOracleAddress(address _newBeaconOracleAddress) external;
    function setCreationCode(bytes memory _creationCode) external;
    function setEtherRouterAddress(address _newEtherRouterAddress) external;
    function setInterestRateCalculator(address _calculatorAddress) external;
    function setLiquidator(address _liquidatorAddress, bool _canLiquidate) external;
    function setRedemptionQueueAddress(address _newRedemptionQueue) external;
    function setVPoolCreditsPerValidator(
        address[] memory _validatorPoolAddresses,
        uint48[] memory _newCreditsPerValidator
    ) external;
    function setVPoolValidatorCountsAndBorrowAllowances(
        address[] memory _validatorPoolAddresses,
        bool _setValidatorCounts,
        bool _setBorrowAllowances,
        uint32[] memory _newValidatorCounts,
        uint128[] memory _newBorrowAllowances,
        uint32[] memory _lastWithdrawalTimestamps
    ) external;
    function setVPoolWithdrawalFee(uint256 _newFee) external;
    function setValidatorApprovals(
        bytes[] memory _validatorPublicKeys,
        address[] memory _validatorPoolAddresses,
        uint32[] memory _whenApprovedArr,
        uint32[] memory _lastWithdrawalTimestamps
    ) external;
    function timelockAddress() external view returns (address);
    function toBorrowAmount(uint256 _shares) external view returns (uint256 _borrowAmount);
    function toBorrowAmountOptionalRoundUp(
        uint256 _shares,
        bool _roundUp
    ) external view returns (uint256 _borrowAmount);
    function totalBorrow() external view returns (uint256 amount, uint256 shares);
    function transferTimelock(address _newTimelock) external;
    function updateUtilization() external;
    function utilizationStored() external view returns (uint256);
    function vPoolWithdrawalFee() external view returns (uint256);
    function validatorDepositInfo(
        bytes memory _validatorPublicKey
    )
        external
        view
        returns (
            uint32 whenValidatorApproved,
            bool wasFullDepositOrFinalized,
            address validatorPoolAddress,
            uint96 userDepositedEther,
            uint96 lendingPoolDepositedEther
        );
    function validatorPoolAccounts(
        address _validatorPool
    )
        external
        view
        returns (
            bool isInitialized,
            bool wasLiquidated,
            uint32 lastWithdrawal,
            uint32 validatorCount,
            uint48 creditPerValidatorI48_E12,
            uint128 borrowAllowance,
            uint256 borrowShares
        );
    function validatorPoolCreationCodeAddress() external view returns (address);
    function wasLiquidated(address _validatorPoolAddress) external view returns (bool _wasLiquidated);
    function wouldBeSolvent(
        address _validatorPoolAddress,
        bool _accrueInterest,
        uint256 _addlValidators,
        uint256 _addlBorrowAmount
    ) external view returns (bool _wouldBeSolvent, uint256 _borrowAmount, uint256 _creditAmount);
}
