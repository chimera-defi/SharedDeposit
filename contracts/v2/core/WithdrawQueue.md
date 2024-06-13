# WithdrawQueue Smart Contract

## Overview

The `WithdrawQueue` contract is designed to manage withdrawal requests in a queue system. It supports withdrawals in both native Ether and specific ERC20 tokens (`sgEth` and `wsgEth`). The contract ensures that withdrawals are processed in a first-in, first-out (FIFO) manner and allows for efficient management of large withdrawal requests by chunking them into manageable sizes.

### Key Features

- **Queue System**: Manages withdrawal requests in a FIFO order.
- **Chunk Processing**: Handles withdrawals in chunks of 32 Ether to ensure efficient processing.
- **Supports Multiple Tokens**: Allows withdrawals in native Ether, `sgEth`, and `wsgEth` tokens.
- **Security**: Implements access control, pausable functionality, and reentrancy guards for enhanced security.

## Contract Details

### State Variables

- `sgEth`: Address of the `sgEth` token.
- `wsgEth`: Address of the `wsgEth` token.
- `minter`: Instance of the `SharedDepositMinterV2` contract.
- `CHUNK_SIZE`: Constant value set to 32 Ether.
- `front`, `end`: Track the indices for the queue's front and end.
- `lockedFront`, `lockedAmount`: Track the locked front index and amount for chunk processing.
- `queue`: Mapping to store withdrawal requests.

### Structs

- `Queue`: Represents a withdrawal request with the following fields:
  - `to`: Address to which the withdrawal will be sent.
  - `amount`: Amount to be withdrawn.
  - `token`: Token address (or zero address for Ether).
  - `tokenAmount`: Amount of tokens to be withdrawn.

### Errors

- `NoAvailableQueue`: Error thrown when there are no available items in the queue to process.

### Constructor

Initializes the contract with the addresses of `sgEth`, `wsgEth`, and the `SharedDepositMinterV2` contract. Grants the deployer the default admin role.

### Functions

- `push(address to) external payable`: Adds a withdrawal request for native Ether.
- `pushSgEth(address to, uint256 amount) external`: Adds a withdrawal request for `sgEth` tokens.
- `pushWsgEth(address to, uint256 amount) external`: Adds a withdrawal request for `wsgEth` tokens.
- `_push(address to, uint256 amount, address token, uint256 tokenAmount) internal`: Internal function to handle the addition of withdrawal requests to the queue.
- `processWithdraw() external`: Processes the withdrawal requests up to the locked front index.

## Usage

### Adding a Withdrawal Request

To add a withdrawal request for Ether:

```solidity
withdrawQueue.push{value: amount}(recipientAddress);
```

To add a withdrawal request for sgEth tokens:

```solidity
withdrawQueue.pushSgEth(recipientAddress, amount);
```

To add a withdrawal request for wsgEth tokens:

```solidity
withdrawQueue.pushWsgEth(recipientAddress, amount);
```

### Processing Withdrawals

To process the queued withdrawals:

```solidity
withdrawQueue.processWithdraw();
```
