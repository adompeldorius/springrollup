# A zk-rollup that allows a sender to batch an unlimited number of transfers with only 5 bytes of calldata

We introduce a Layer 2 solution which could be classified as a kind of zk-rollup, but needs much less on-chain data than existing zk-rollups. This proposal makes it possible for a sender to batch an arbitrary number of transfers to other accounts while only having to post 5 bytes of calldata on-chain. These calldata savings are made possible by borrowing some ideas from Plasma, where each user stores some small piece of data that is needed for withdrawing in the case where the operator misbehaves. Unlike Plasma, however, users won't have to watch the chain for malicious behavior, and the security assumptions are the same as for existing zk-rollups.

## L1 contract

The rollup state is divided in two parts:

- **On-chain available state**: State *with* on-chain data availability
- **Off-chain available state**: State *without* on-chain data availability

The L1 contract stores a common merkle root to both parts of the state. Any changes made to the on-chain available state must be provided in the calldata, which means that this state can always be reconstructed from the calldata. On the other hand, changes to the off-chain available state will be provided by any other means off-chain.

In addition to the state merkle root, the L1 contract also stores a list of operations called the *inbox*. Anyone can add an L1 operation (see below) to the inbox on L1. When posting a rollup block, the operator must process all operations in this list before processing the L2 operations included in the block.

## Rollup blocks

The rollup operator is allowed to make changes to the rollup state by posting a rollup block to the L1 contract, which provides the following information in the tx calldata.

1. The new common merkle root.
2. A diff between the old and the new on-chain available state.
3. A zk-proof that there exist a state with the old state root and a list of valid operations (see below) that when applied to the old state (after applying all operations in the inbox) gives a new state with the new state root, and that the diff provided above is correct.

If the above data is valid, the state root is updated and the inbox is emptied.

Note that what we have described so far is a general framework for describing many L2 solutions. For instance:

- If all rollup state is in the on-chain available part, and the off-chain available state is the empty set, we get existing zk-rollups.
- If all rollup state is in the off-chain available part and the on-chain available state is the empty set, we get validiums.
- If both parts of the state contains account state, we get volitions (e.g. zk-porter).

Our proposal is neither of the above, and is described below.

## Rollup state

Here we define the schema of the rollup state.

### On-chain available state

```
OnChainAvailableState =
  { finalizedBlockNum : Map(Address -> Integer)
  }
```

### Off-chain available state

```
OffChainAvailableState =
  { balanceOf : Map(Address -> Value)
  , nonceOf : Map(Address -> Integer)
  , pendingTransactions : Set(Transaction)
  }
```

where `Transaction` is the type

```
Transaction =
  { sender : Address
  , recipient : Address
  , amount : Value
  , nonce : Integer
  }
```

## Operations

There are two kinds of operations available, L1 operations and L2 operations. L1 operations are added to the inbox on L1, while L2 operations are added by the operator in a rollup block.

### L2 operations

The operator is allowed to include the following operations in a rollup block.

#### AddTransaction

```
AddTransaction(
    transaction : Transaction
  , signature : Signature of the transaction by the transaction's sender
  )
```

Given a signed transaction, add the transaction to the set `pendingTransactions`, and increases `nonceOf(sender)` by one. It is required that the nonce of the transaction is one greater than the current value of `nonceOf(sender)`.

#### FinalizeBlock

```
FinalizeBlock(
    address : Address
  , signature : Message "Finalize block blockNum" signed by the owner of address.
  )
```

Executes the transactions in `pendingTransactions` whose sender is `address`, and sets `finalizedBlockNum(address)` to the current rollup block number. When a transaction is executed, it is removed from `pendingTransactions`, the amount is subtracted from the balance of `fromAddress` and added to the balance of `toAddress`.

#### Withdraw

```
Withdraw(
    fromAddress : Address
  , toAddress : L1 Address
  , amount : Value
  )
```

Decreases the balance of `fromAddress` by `amount` and sends `amount` ETH to`toAddress` on L1.

### L1 operations

The following operations can be added to the inbox in the L1 contract.

#### Deposit

```
Deposit(
    toAddress : Address
)
```

Adds the included ETH to the balance of `toAddress`.

#### ForceWithdrawal

```
ForceWithdrawal(
    fromAddress : Address
  , toAddress : L1 Address
  , amount : Value
  , signature : Signature of the withdrawal request by fromAddress
  )
```

Decreases the balance of `fromAddress` by `amount` and sends `amount` ETH from the L1 contracts balance to `toAddress` on L1.

## Frozen mode

If the operator doesn't publish a new block in 3 days, anyone can call a freeze command in the contract, making the contract enter a *frozen mode*.

When the contract is frozen, the following happens:

1. Deposits are no longer possible.
2. A map `withdrawnAmount : Address -> Value` is added to the contract storage, which maintains the total amount that each user have withdrawn.

In order to withdraw, a user Alice must provide to the L1 contract the witnesses to the following.

1. `balance = balanceOf(aliceAddress)` in a rollup block `b` with `blockNum >= finalizedBlockNum(aliceAddress)`.
2. If `blockNum == finalizedBlockNum(aliceAddress)`, we require witnesses to the set of pending transactions by Alice in block `b`. We denote the total sent amount as `sentAmount`.
3. A set of pending transfers *to* Alice, where each pending transfer must be in a block that is at least as new as *b* above (otherwise the recieved amount would already be included in the `balance`), and strictly older than the sender's finalizedBlockNum. We denote the total amount as `recievedAmount`.

When the L1 contract is given the above data, it sends the user the amount given by

`balance + recievedAmount - sentAmount - withdrawnAmount(aliceAddress)`

and adds the withdrawn amount to `withdrawnAmount(aliceAddress)`.

## Calldata usage

For a batch of transfer from the same sender, the only data that needs to be provided as calldata is the data needed to update the sender's nonce, which is 5 bytes for the sender address (supporting up to 2^48 ~ 300 trillion accounts). This is already less calldata than regular rollups if the batch has only one transfer, and is much less per transfer for larger batches.

## Example 1: Single tranfer from Alice to Bob

Alice wants to send 5 ETH to Bob. Her current nonce is 7, and her current finalizedBlockNum is 2. The procedure is as follows:

1. Alice signs the transaction
    ```
    transaction =
        ( sender = aliceAddress
        , nonce = 8
        , toAddress = bobAddress
        , amount = 5 ETH
        )
    ```
    and sends the transaction and the signature to the operator.
2. The operator includes the operation `AddTransaction(transaction, signature)` in the next rollup block, which adds the transactions to the set of pending transactions in the rollup state.
3. The operator sends a witness of the pending transactions to Alice.
4. Once Alice have the witnesses, she signes the message "Finalize block 123" (123 is the blockNum of the block containing the pending transaction) and sends this signed message to the operator.
5. The operator includes the operation
   ```
   IncrementBatchNum(
     address = aliceAddress
     signature = signature
   )
   ```
   in the next rollup block, which has block number 124. Alice's finalizedBlockNum is set to 123, and the transfer to Bob is executed.
6. The operator gives Alice and Bob the witnesses to their updated balances.

### Proof of safety in case the operator misbehaves

The operator may misbehave in several stages in the example above. If this happens, users can exit by sending a `ForceWithdrawal` operation to the L1 inbox. Then, either the operator will process the withdrawal requests in the next rollup block, or it will stop publishing new blocks. If the operator doesn't add a new block in 3 days, anyone can call the freeze command on L1, and the rollup is frozen. For Alice and Bob, there are three scenarios:

* The transfer from Alice to Bob was not applied (it is either pending or wasn't included at all). Then Alice will use a witness of her latest balance to exit.
* The transfer was applied, but the operator didn't provide the witnesses to the new balances of Alice and Bob. In this case, Alice have a witness of the pending transfer to Bob (otherwise she wouldn't finalize the block). Alice can then withdraw using the witness of her previous balance (before the transfer to Bob), plus a witness to the pending transfer to Bob. Bob may withdraw with his previous balance, plus a witness of the pending transfer from Alice, which he could ask to get from Alice.

In all three cases, both Alice's and Bob's (and all other user's) funds are safe.

## Example 2: Batch of transfers from Alice to 1000 recipients

Suppose Alice is a big employer and want to send salaries to 1000 people. She may then batch them all together to save calldata. The procedure for this is the same as in Example 1 above, but she will finalize a block only after all 1000 transfers, and she has recieved the witnesses to all of the pending transfers from the operator.

## Open question: How to generalize this proposal to support smart contracts?

## Similar ideas

https://ethresear.ch/t/minimal-fully-generalized-s-ark-based-plasma/5580
https://ethresear.ch/t/plasma-snapp-fully-verified-plasma-chain/3391
https://ethresear.ch/t/plasma-snapp-1-bit/4802
https://ethresear.ch/t/mvr-minimally-viable-rollback/7538
