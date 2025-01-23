// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

// Minimum function set that a frxETH_V2 AMO needs to have
interface IfrxEthV2AMO {
    struct ShowAmoBalancedAllocsPacked {
        uint96 amoEthFree;
        uint96 amoEthInLpBalanced;
        uint96 amoEthTotalBalanced;
        uint96 amoFrxEthFree;
        uint96 amoFrxEthInLpBalanced;
    }

    function amoHelper() external view returns (address);

    function depositEther() external payable;

    function requestEtherByRouter(uint256 _ethRequested) external returns (uint256 _ethOut, uint256 _remainingEth);
}
