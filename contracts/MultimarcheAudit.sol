// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Public testnet record of the virtual-credit ledger. This is not a token
/// or an on-chain betting engine. Each payload contains pseudonymous transfers.
contract MultimarcheAudit {
    address public immutable owner;
    uint256 public height;
    bytes32 public head;
    mapping(uint256 => bytes32) public hashAt;
    bytes32 public constant VERSION = keccak256("MULTIMARCHE_AUDIT_V1");
    event Record(uint256 indexed sequence, bytes32 indexed previousHash, bytes32 indexed recordHash, string payload);

    constructor() {
        require(block.chainid == 11155111 || block.chainid == 31337, "Test networks only");
        owner = msg.sender;
    }

    function appendBatch(uint256 first, bytes32 previous, bytes32[] calldata hashes, string[] calldata payloads) external {
        require(msg.sender == owner, "Owner only");
        require(first == height + 1 && previous == head, "Wrong chain position");
        require(hashes.length > 0 && hashes.length <= 10 && hashes.length == payloads.length, "Invalid batch");
        for (uint256 i; i < hashes.length; ++i) {
            require(bytes(payloads[i]).length <= 16384, "Payload too large");
            require(sha256(bytes(payloads[i])) == hashes[i], "Hash mismatch");
            uint256 sequence = ++height;
            emit Record(sequence, head, hashes[i], payloads[i]);
            head = hashes[i];
            hashAt[sequence] = hashes[i];
        }
    }
}
