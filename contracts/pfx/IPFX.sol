// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface IPFX {
    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    function permit(
        address owner,
        address spender,
        uint256 rawAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function delegate(address delegatee) external;

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function getCurrentVotes(address account) external view returns (uint96);

    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint96);

    function includeSrc(address account) external;

    function includeDst(address account) external;

    function excludeSrc(address account) external;

    function excludeDst(address account) external;

    function setReflectionFee(uint96 _reflectionFee) external;

    function setDevFee(uint96 _devFee) external;

    function setReflectionAddress(address _reflectionAddress) external;

    function setDevAddress(address _devAddress) external;

    function startReflecting() external;

    function stopReflecting() external;

    function startDevFees() external;

    function stopDevFees() external;
}
