// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

interface IFraxEtherRedemptionQueueV2 {
    function FEE_PRECISION() external view returns (uint64);

    function FRX_ETH() external view returns (address);

    function SFRX_ETH() external view returns (address);

    function acceptTransferTimelock() external;

    function approve(address to, uint256 tokenId) external;

    function balanceOf(address owner) external view returns (uint256);

    function fullRedeemNft(uint256 _nftId, address _recipient) external;

    function partialRedeemNft(uint256 _nftId, address _recipient, uint256 _redeemAmt) external;

    function collectAllRedemptionFees() external returns (uint128);

    function collectRedemptionFees(uint128 _collectAmount) external returns (uint128);

    function enterRedemptionQueue(address _recipient, uint120 _amountToRedeem) external returns (uint256 _nftId);

    function enterRedemptionQueueViaSfrxEth(
        address _recipient,
        uint120 _sfrxEthAmount
    ) external returns (uint256 _nftId);

    function enterRedemptionQueueWithPermit(
        uint120 _amountToRedeem,
        address _recipient,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256 _nftId);

    function enterRedemptionQueueWithSfrxEthPermit(
        uint120 _sfrxEthAmount,
        address _recipient,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256 _nftId);

    function feeRecipient() external view returns (address);

    function getApproved(uint256 tokenId) external view returns (address);

    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function maxQueueLengthSeconds() external view returns (uint256);

    function name() external view returns (string memory);

    function nftInformation(
        uint256 nftId
    ) external view returns (bool hasBeenRedeemed, uint64 maturity, uint120 amount);

    function operatorAddress() external view returns (address);

    function ownerOf(uint256 tokenId) external view returns (address);

    function pendingTimelockAddress() external view returns (address);

    function recoverErc20(address _tokenAddress, uint256 _tokenAmount) external;

    function recoverEther(uint256 _amount) external;

    function redemptionQueueAccounting()
        external
        view
        returns (uint120 etherLiabilities, uint120 unclaimedFees, uint120 pendingFees);

    function redemptionQueueState()
        external
        view
        returns (uint64 nextNftId, uint64 queueLengthSecs, uint64 redemptionFee);

    function renounceTimelock() external;

    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) external;

    function setApprovalForAll(address operator, bool approved) external;

    function setFeeRecipient(address _newFeeRecipient) external;

    function setMaxQueueLengthSeconds(uint256 _newMaxQueueLengthSeconds) external;

    function setOperator(address _newOperator) external;

    function setQueueLengthSeconds(uint64 _newLength) external;

    function setRedemptionFee(uint64 _newFee) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function symbol() external view returns (string memory);

    function timelockAddress() external view returns (address);

    function tokenURI(uint256 tokenId) external view returns (string memory);

    function transferFrom(address from, address to, uint256 tokenId) external;

    function transferTimelock(address _newTimelock) external;
}
