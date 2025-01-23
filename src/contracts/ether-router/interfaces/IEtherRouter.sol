// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

interface IEtherRouter {
    struct CachedConsEFxBalances {
        bool isStale;
        address amoAddress;
        uint96 ethFree;
        uint96 ethInLpBalanced;
        uint96 ethTotalBalanced;
        uint96 frxEthFree;
        uint96 frxEthInLpBalanced;
    }

    function acceptTransferTimelock() external;

    function addAmo(address _amoAddress) external;

    function amos(address) external view returns (bool);

    function amosArray(uint256) external view returns (address);

    function cachedConsEFxEBals(
        address
    )
        external
        view
        returns (
            bool isStale,
            address amoAddress,
            uint96 ethFree,
            uint96 ethInLpBalanced,
            uint96 ethTotalBalanced,
            uint96 frxEthFree,
            uint96 frxEthInLpBalanced
        );

    function depositEther() external;

    function depositToAmoAddr() external view returns (address);

    function getConsolidatedEthFrxEthBalance(
        bool _forceLive,
        bool _updateCache
    ) external returns (CachedConsEFxBalances memory _rtnBalances);

    function getConsolidatedEthFrxEthBalanceView(
        bool _forceLive
    ) external view returns (CachedConsEFxBalances memory _rtnBalances);

    function lendingPool() external view returns (address);

    function operatorAddress() external view returns (address);

    function pendingTimelockAddress() external view returns (address);

    function previewRequestEther(
        uint256 _ethRequested
    ) external view returns (uint256 _currEthInRouter, uint256 _rqShortage, uint256 _pullFromAmosAmount);

    function redemptionQueue() external view returns (address);

    function removeAmo(address _amoAddress) external;

    function renounceTimelock() external;

    function requestEther(address _recipient, uint256 _ethRequested, bool _bypassFullRqShortage) external;

    function setPreferredDepositAndWithdrawalAMOs(address _depositToAddress, address _withdrawFromAddress) external;

    function setLendingPool(address _newAddress) external;

    function setRedemptionQueue(address _newAddress) external;

    function sweepEther(uint256 _amount, bool _depositAndVault) external;

    function timelockAddress() external view returns (address);

    function transferTimelock(address _newTimelock) external;
}
