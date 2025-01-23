// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

import "src/contracts/frxeth-redemption-queue-v2/FraxEtherRedemptionQueueV2.sol";
import "src/contracts/frxeth-redemption-queue-v2/interfaces/IFraxEtherRedemptionQueueV2.sol";

library RedemptionQueueStructHelper {
    struct NftInformationReturn {
        bool hasBeenRedeemed;
        uint64 maturity;
        uint120 amount;
        uint64 redemptionFee;
        uint120 ttlEthRequestedSnapshot;
    }

    function __nftInformation(
        FraxEtherRedemptionQueueV2 _redemptionQueue,
        uint256 nftId
    ) internal view returns (NftInformationReturn memory _return) {
        (
            _return.hasBeenRedeemed,
            _return.maturity,
            _return.amount,
            _return.redemptionFee,
            _return.ttlEthRequestedSnapshot
        ) = _redemptionQueue.nftInformation(nftId);
    }

    function __nftInformation(
        IFraxEtherRedemptionQueueV2 _redemptionQueue,
        uint256 nftId
    ) internal view returns (NftInformationReturn memory _return) {
        FraxEtherRedemptionQueueV2 _redemptionQueue = FraxEtherRedemptionQueueV2(payable(address(_redemptionQueue)));
        return __nftInformation(_redemptionQueue, nftId);
    }

    struct RedemptionQueueAccountingReturn {
        uint120 etherLiabilities;
        uint120 unclaimedFees;
        uint120 pendingFees;
    }

    function __redemptionQueueAccounting(
        FraxEtherRedemptionQueueV2 _redemptionQueue
    ) internal view returns (RedemptionQueueAccountingReturn memory _return) {
        (_return.etherLiabilities, _return.unclaimedFees, _return.pendingFees) = _redemptionQueue
            .redemptionQueueAccounting();
    }

    function __redemptionQueueAccounting(
        IFraxEtherRedemptionQueueV2 _redemptionQueue
    ) internal view returns (RedemptionQueueAccountingReturn memory _return) {
        FraxEtherRedemptionQueueV2 _redemptionQueue = FraxEtherRedemptionQueueV2(payable(address(_redemptionQueue)));
        return __redemptionQueueAccounting(_redemptionQueue);
    }

    struct RedemptionQueueStateReturn {
        uint64 nextNftId;
        uint64 queueLengthSecs;
        uint64 redemptionFee;
        uint120 ttlEthRequested;
        uint120 ttlEthServed;
    }

    function __redemptionQueueState(
        FraxEtherRedemptionQueueV2 _redemptionQueue
    ) internal view returns (RedemptionQueueStateReturn memory _return) {
        (
            _return.nextNftId,
            _return.queueLengthSecs,
            _return.redemptionFee,
            _return.ttlEthRequested,
            _return.ttlEthServed
        ) = _redemptionQueue.redemptionQueueState();
    }

    function __redemptionQueueState(
        IFraxEtherRedemptionQueueV2 _redemptionQueue
    ) internal view returns (RedemptionQueueStateReturn memory _return) {
        FraxEtherRedemptionQueueV2 _redemptionQueue = FraxEtherRedemptionQueueV2(payable(address(_redemptionQueue)));
        return __redemptionQueueState(_redemptionQueue);
    }
}
