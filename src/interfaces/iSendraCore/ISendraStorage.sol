// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { SendraLib } from "../../libs/Sendra.lib.sol";

/**
 * @title ISendraStorage
 * @notice External surface of protocol `SendraStorage` (see `protocol/src/core/SendraStorage.sol`).
 */
interface ISendraStorage {
    error InvalidProtocol();
    error InvalidGlobalAccumulatorField();
    error InvalidSpecificAccumulatorField();
    error AccumulatorBatchLengthMismatch();
    error InvalidSpecificMetricIndex();
    error InvalidSpecificMetricEncoding();

    function roles() external view returns (address);

    function usersById(uint256 id) external view returns (address);

    function getUser(address user) external view returns (SendraLib.UserInfoRead memory);

    function updateUserTransactionCount(address user, uint256 transactionCount) external;

    function finalizePosition(uint256 positionId, address user) external;

    function addPositionToUser(address user, SendraLib.Position memory position) external;

    function updateUserFullPosition(address user, uint256 positionId, SendraLib.Position memory position) external;

    function updateUserPositionData(address user, uint256 positionId, uint256 positionField, bytes memory value) external;

    function updateUserPositionPnl(address user, uint256 positionId, int256 pnlChange) external;

    function updateUserPositionIsActive(address user, uint256 positionId, bool isActive) external;

    function updateUserGlobalPnl(address user, int256 pnlChange) external;

    function updateUserData(address user, uint256 dataIndex, bytes memory data) external;

    function decreaseGlobalPositionActivePositions(address user) external;

    function applyGlobalPulseDeltas(address user, uint8[] calldata fieldIds, int256[] calldata deltas) external;

    function applySpecificPulseDeltas(
        address user,
        uint64 specificKey,
        uint8[] calldata fieldIds,
        int256[] calldata deltas
    ) external;

    function updateSpecificPulseMetric(address user, uint64 specificKey, uint256 metricIndex, bytes memory value)
        external;

    function applyMetricDelta(address user, uint64 specificKey, uint256 metricIndex, int256 delta) external;

    function applyMetricDeltaSigned(address user, uint64 specificKey, uint256 metricIndex, int256 delta) external;

    function getUserGlobalAccumulators(address user) external view returns (SendraLib.GlobalAccumulators memory);

    function getUniqueGlobalAccumulator(uint8 fieldId, address user) external view returns (int256);

    function getUserSpecificAccumulators(address user, uint64 specificKey)
        external
        view
        returns (SendraLib.SpecificAccumulators memory);

    function getUserSpecificMetric(address user, uint64 specificKey, uint256 metricIndex)
        external
        view
        returns (bytes memory);

    function getUserSpecificMetricsLength(address user, uint64 specificKey) external view returns (uint256);

    function getUserPositionById(address user, uint256 positionId) external view returns (SendraLib.Position memory);

    function isUser(address user) external view returns (bool);

    function getUsersCount() external view returns (uint256);

    function getProtocolStats() external view returns (SendraLib.ProtocolStats memory);

    function getUserAddressById(uint256 id) external view returns (address);

    function getUserIdByAddress(address user) external view returns (uint256);

    function getUserDataById(uint256 id) external view returns (SendraLib.UserInfoRead memory, address);

    function updateTotalVolume(uint256 amount) external;

    function updateTotalPnl(int256 pnl) external;

    function updateTotalTransactions() external;

    function updateTotalPositions() external;

    function updateTotalActivePositions(int256 change) external;

    function updateTotalValueLocked(int256 change) external;
}
