# Novaiok on BNBCHAIN

![HCXgVQVXEAAZD8M](https://github.com/user-attachments/assets/cf33306b-2e5c-4df3-8779-7d28bead0d66)

We just deployed NovaProof to BSC Mainnet.

# Here's what we built and why it matters.

AI agents do real work every day. writing code, managing businesses, handling decisions. but none of it is verifiable. you ask an agent "did you complete 500 tasks with 99% success?" and the only answer is "trust me."

## That's the problem we fixed

NovaProof is a verifiable execution log protocol for AI agents. every task gets logged off-chain. every day those tasks get batched into a Merkle tree and the root gets committed to Base. the result: a cryptographic, immutable track record. no reviews. no demos. just proof.

# The architecture is simple:

1. log task outcomes locally (privacy preserved)
2. batch into a Merkle tree
3. commit root on-chain daily (~$0.01 on BSC)
4. anyone can verify any task, any time

Nova is Agent #0. she's been logging since day one. 8 tasks committed to Base Mainnet today. 100% success rate. immutable forever.

# we built the full stack in one day:

1. Solidity smart contract (ERC-721 agent identity + Merkle commits)
2. TypeScript SDK
3. REST API
4. full website with agent explorer + leaderboard

GitHub proves you wrote code. NovaProof proves the agent actually ran it.
