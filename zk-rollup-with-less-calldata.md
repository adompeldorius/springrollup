# Springrollup: A zk-rollup that allows a sender to batch an unlimited number of transfers with only 6 bytes of calldata

We introduce a Layer 2 solution which could be classified as a kind of zk-rollup, but uses much less on-chain data than existing zk-rollups. In this design a sender can batch an arbitrary number of transfers to other accounts while only having to post their address as calldata, which is 6 bytes if we want to support up to 2^48 ~ 300 trillion accounts. These calldata savings are made possible by borrowing some ideas from Plasma, where each user stores some small piece of data that is needed for withdrawing in the case where the operator misbehaves. Unlike Plasma, however, users won't have to watch the chain for malicious behavior, and the security assumptions are the same as for existing zk-rollups.

## L1 contract

The rollup state is divided in two parts:

- **On-chain available state**: State *with* on-chain data availability. All changes to this state must be provided as calldata.
- **Off-chain available state**: State *without* on-chain data availability. Changes to this state will be provided by any other means off-chain.

The L1 contract stores a common merkle root to both parts of the state. The on-chain available state can always be reconstructed from the calldata, while the off-chain available state may be withheld by the operater in the worst case scenario.

In addition to the state merkle root, the L1 contract also stores a list of operations called the *inbox*. Anyone can add an L1 operation (see below) to the inbox on L1. When posting a rollup block, the operator must process all operations in this list before processing the L2 operations included in the block.

## Rollup blocks

The rollup operator is allowed to make changes to the rollup state by posting a rollup block to the L1 contract, which provides the following information in the tx calldata.

1. The new common merkle state root.
2. A diff between the old and the new on-chain available state.
3. A zk-proof that there exist a state with the old state root and a list of valid operations (see below) that when applied to the old state (after processing all operations in the inbox) gives a new state with the new state root, and that the diff provided above is correct.

If the above data is valid, the state root is updated and the inbox is emptied.

**Remark:** What we have described so far is a general description of several L2 solutions. For instance:

- If the whole rollup state is in the on-chain available part, and the off-chain available state is empty, we get existing zk-rollups.
- If the whole rollup state is in the off-chain available part and the on-chain available state is empty, we get validiums.
- If both parts of the state contain account state, we get volitions (e.g. zk-porter).

Our proposal is neither of the above, and is described below.

## Rollup state

Here we define the structure of the rollup state.

### On-chain available state

```
OnChainAvailableState =
  { lastSeenBlockNum : Map(L2 Address -> Integer) # A block number of a block in which the owner of the address possess a witness to their balance and pending transactions.
  , onChainBalanceOf : Map(L2 Address -> Value) # On-chain part of the balance of an account.
  , blockNum : Integer # The current block number.
  }
```

### Off-chain available state

```
OffChainAvailableState =
  { offChainBalanceOf : Map(L2 Address -> Value) # Off-chain part of the balance of an account.
  , nonceOf : Map(L2 Address -> Integer) # The current nonce of an account.
  , pendingTransactions : Set(Transaction) # A set of transactions that have been added, but not processed yet.
  }
```

where `Transaction` is the type

```
Transaction =
  { sender : L2 Address
  , recipient : L2 address or L1 address
  , amount : Value
  , nonce : Integer
  }
```

The current balance of an account is given by `onChainBalanceOf(address) + offChainBalanceOf(address)`. The on-chain part of the balance is modified by the L1 operations `Deposit` and `ForceWithdrawal`, and in the case where the rollup is frozen (see below), while the off-chain part is modified by regular L2 operations. 

Note that either of these balances may be negative, but their sum is always non-negative.

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

Adds the transaction to the set `pendingTransactions` and increases `nonceOf(sender)` by one. It is required that the transaction's nonce is one greater than the current `nonceOf(sender)`.

#### ProcessTransactions

```
ProcessTransactions(
    address : Address
  , blockNum : Integer
  , signature : Signature of message "Process transactions in block blockNum" by the owner of address.
  )
```

We require that blockNum is the block number of the last published rollup block (i.e. not this in-process block). This operation processes all transactions in the set `pendingTransactions` at the end of the previous rollup block (whose block number is `blockNum`), whose sender is `address`, and sets `lastSeenBlockNum(address)` to `blockNum`.

When a transaction is processed, it is removed from `pendingTransactions`, the amount is subtracted from the balance of `fromAddress` and added to the balance of `toAddress`. If the sender has insufficient funds for the transfer, meaning that `amount > onChainBalanceOf(sender) + offChainBalanceOf(sender)`, the transaction fails and is just removed from `pendingTransactions`.

A user should make sure they possess the witnesses for their balance and all their `pendingTransactions` in block `blockNum` before sending this operation to the operator.

### L1 operations

The following operations can be added to the inbox in the L1 contract.

#### Deposit

```
Deposit(
    toAddress : L2 Address
)
```

Adds the amount of included ETH to `onChainBalanceOf(toAddress)`.

#### ForceWithdrawal

```
ForceWithdrawal(
    fromAddress : L2 Address
  , toAddress : L1 Address
  , signature : Signature of the message "Withdraw to toAddress" by fromAddress
  )
```

Withdraws `onChainBalanceOf(fromAddress) + offChainBalanceOf(fromAddress)` ETH to `toAddress` on L1 and decreases `onChainBalanceOf(fromAddress)` by the withdrawn amount (i.e. sets `onChainBalanceOf(fromAddress)` to `-offChainBalanceOf(fromAddress)`).

## Frozen mode

If the operator doesn't publish a new block in 3 days, anyone can call a freeze command in the contract, making the rollup enter a *frozen mode*.

When the rollup is frozen, the users that have an unprocessed deposit in the inbox can send a call to the contract to claim the deposited ETH and remove the deposit operation from the inbox.

In order to withdraw from an L2 account, a user Alice must provide to the L1 contract the witnesses to the following.

1. `offChainBalanceOf(aliceAddress)` in some rollup block `b` with `blockNum >= lastSeenBlockNum(aliceAddress)`.
2. If `blockNum == lastSeenBlockNum(aliceAddress)`, we also require witnesses to the set of pending transactions *from* Alice in block `b`. We denote the total sent amount as `sentAmount`.
3. A set of pending transfers *to* Alice. Each pending transfer's block must be at least as new as *b* above (to be sure it is not already included in `offChainBalanceOf(aliceAddress)`). Also, each pending transfer must have been processed, meaning that it's block cannot be newer than the sender's `lastSeenBlockNum`. We denote the total recieved amount as `recievedAmount`.

When the L1 contract is given the above data, it sends the user the amount (if non-negative) given by

```
  offChainBalanceOf(aliceAddress)
+ onChainBalanceOf(aliceAddress)
+ recievedAmount
- sentAmount
```

and decreases `onChainBalanceOf(aliceAddress)` by the withdrawn amount. If the above amount is negative, nothing happens.

## Calldata usage

The only data that needs to be provided as calldata in each rollup block is the set of accounts that have updated their `lastSeenBlockNum` to the block number of the previous rollup block, which is 6 bytes per address (supporting up to 2^48 ~ 300 trillion accounts). This is already less calldata than regular rollups if each user only added one pending transfer before calling `processTransactions`, and is much less per transfer when users add many pending transactions before processing them.

## Example 1: Single tranfer from Alice to Bob

Alice wants to send 5 ETH to Bob. Her current nonce is 7, and her current `lastSeenBlockNum` is 67. The procedure is as follows:

1. Alice signs the transaction
    ```
    transaction =
        ( sender = aliceAddress
        , nonce = 8
        , toAddress = bobAddress
        , amount = 5 ETH
        )
    ```
    and sends the transaction and a signature of it to the operator.
2. The operator includes the operation `AddTransaction(transaction, signature)` in the next rollup block (number 123), which adds the transaction to the set of pending transactions in the rollup state.
3. After rollup block 123 is published on-chain, the operator sends a witness of the newly added pending transaction to Alice.
4. Once Alice have the witness of her pending transaction in block 123, she signes the message "Process transactions in block 123" and sends this signed message to the operator.
5. The operator includes the operation
   ```
   ProcessTransactions(
     address = aliceAddress
   , blockNum = 123
   , signature = signature
   )
   ```
   in the next rollup block, which has block number 124. Alice's `lastSeenBlockNum` is set to 123, and the transfer to Bob is processed.
6. The operator gives Alice and Bob the witnesses to their updated balances in block 124.

### Proof of safety in case the operator misbehaves

The operator may misbehave in several stages in the example above. If this happens, users can exit by sending a `ForceWithdrawal` operation to the L1 inbox. Then, either the operator will process the withdrawal requests in the next rollup block, or it will stop publishing new blocks. If the operator doesn't add a new block in 3 days, anyone can call the freeze command on L1, and the rollup is frozen. For Alice and Bob, there are three scenarios:

* The transfer from Alice to Bob was not applied (it is either pending or wasn't included at all). Then Alice will use a witness of her balance in some block at least as new as 67 (which is her `lastSeenBlockNum`) to exit.
* The transfer was applied, but the operator didn't provide the witnesses to the new balances of Alice and Bob. In this case, Alice have a witness of her balance in block 123, plus the pending transfer to Bob (otherwise she wouldn't send the `ProcessTransactions` operation). Alice can then withdraw using the witness of her balance in block 123, plus a witness to the pending transfer to Bob. Bob may withdraw with a witness to his balance in some block at least as new as his `lastSeenBlockNum`, plus a witness of the pending transfer from Alice, which he could get from Alice.

In all three cases, both Alice's and Bob's (and all other user's) funds are safe.

## Example 2: Batch of transfers from Alice to 1000 recipients

Suppose Alice is a big employer and want to send salaries to 1000 people. She may then batch them all together to save calldata. The procedure for this is the same as in Example 1 above, but she will add all 1000 transactions to `pendingTransactions` before sending the `ProcessTransactions` operation.

## Discussion

### Privacy

This design has increased privacy compared to existing rollups, since if the operator is honest, they will not make users balances or transactions public, but only give each user witnesses to their updated balances.

### Smart contracts

Further research should be done to figure out how to support smart contracts in this design.

## Related ideas

- https://ethresear.ch/t/minimal-fully-generalized-s-ark-based-plasma/5580
- https://ethresear.ch/t/plasma-snapp-fully-verified-plasma-chain/3391
- https://ethresear.ch/t/plasma-snapp-1-bit/4802
- https://ethresear.ch/t/mvr-minimally-viable-rollback/7538
- https://ethresear.ch/t/adamantium-power-users/9600
- https://ethresear.ch/t/a-zkrollup-with-no-transaction-history-data-to-enable-secret-smart-contract-execution-with-calldata-efficiency/10961/19
