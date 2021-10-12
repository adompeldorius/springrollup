# A new kind of zk-rollup with less on-chain data (e.g. 8 bytes for a batch of up to 65536 transfers from the same sender)

We introduce a Layer 2 solution which could be classified as a kind of zk-rollup, but needs less on-chain data than existing zk-rollups. For instance, this solution makes it possible for a sender to batch 65536 transfers to other users with only 8 bytes of calldata. These calldata savings are made possible by borrowing some ideas from Plasma, where each user stores some small piece of data that is needed for withdrawing in the case where the operator misbehaves. Unlike Plasma, however, users won't have to watch the chain for malicious behavior, and the security assumptions are the same as for existing zk-rollups.

See also:

https://ethresear.ch/t/minimal-fully-generalized-s-ark-based-plasma/5580
https://ethresear.ch/t/plasma-snapp-fully-verified-plasma-chain/3391
https://ethresear.ch/t/plasma-snapp-1-bit/4802
https://ethresear.ch/t/mvr-minimally-viable-rollback/7538

## On-chain contract

The rollup state is divided in two parts:

- On-chain state
- Off-chain state

The L1 contract stores a commitment (i.e. merkle root) to the on-chain state, and a commitment to the off-chain state. All changes to the on-chain state must be included as calldata. The on-chain state can always be reconstructed from the calldata as in a rollup, while the off-chain state must be provided off-chain by the operator.

In the worst case scenario, a malicious operator can make the off-chain state unavailable, but not the on-chain state.

In addition to the state commitments, the L1 contract also stores a list of operations called the *inbox*. Anyone can add an operation to the inbox on L1. When posting a batch of updates, the operator must include all operations in the inbox before processing any other operations. This prevents the operator from censoring users.

## Rollup batches

We allow a designated operator to make changes to the state by posting a rollup batch to the L1 contract, which provides the following information in the tx calldata.

1. A diff between the old on-chain state and the new on-chain state.
2. A commitment (i.e. a merkle root) to the new on-chain state
3. A commitment (i.e. a merkle root) to the new off-chain state
4. A zk-proof that there exist a list of valid operations (see below) that when applied to the old state (after applying all operations in the inbox) gives a new on-chain and off-chain state whose commitments are as provided above.

If the above data is valid, the commitments in the contract storage are updated, and the inbox is cleared.

## Rollup state

Here we define the on-chain and off-chain rollup state.

On-chain state:

- `nonce : Address -> Integer`

Off-chain state:

- `balance : Address -> Value`
- `pendingTransfers : Set(Transfer)`

where `Transfer` is a tuple

```
( nonce : Integer
, fromAddress : Address
, toAddress : Address
, amount : Value
)
```

## Operations

### L1 operations

The following operations can be added to the inbox in the L1 contract.

```
Deposit(
    toAddress : Address
)
```

Sends the included ETH to the specified L2 address.

```
ForceWithdrawal(
    fromAddress : Address
  , toAddress : L1 Address
  , signature : Signature of the withdrawal by fromAddress
  )
```

Decreases the balance of `fromAddress` by `amount` and sends `amount` ETH to`toAddress` on L1. This is the same as the `Withdraw` L2 operation below, but on L1, in case the operator is censoring users.

### L2 operations

The operator is allowed to include the following operations in a batch:

```
AddTransfer(
    transfer : Transfer
  , signature : Signature of transfer by the transfer's fromAddress)
```

Given a signed transfer `(nonce, fromAddress, toAddress, amount)` add the transfer to the set `pendingTransfers`. It is required that `nonce = pendingNonce(address) + 1`, where  `pendingNonce(address)` is the maximum nonce among the pending transfers sent from the given address, or `nonce(address)` if there is no pending transfers from the address.

```
UpdateNonce(
    address : Address
  , newNonce : Integer
  , signature : Message "Update nonce to newNonce" signed by the owner of address.
)
```

Sets `nonce(address) = newNonce` and executes the transfers in `pendingTransfers` whose sender is `address` and nonce is less than or equal to `newNonce`. When a pending transfer is executed, it is removed from `pendingTransfers`, the amount is subtracted from the balance of `fromAddress` and added to the balance of `toAddress`.

```
Withdraw(
    fromAddress : Address
    toAddress : L1 Address
    amount : Value
    )
```

Decreases the balance of `fromAddress` by `amount` and sends `amount` ETH to`toAddress` on L1.

## Frozen mode

If the operator doesn't publish a new batch in 3 days, anyone can call a freeze command in the contract, making the contract enter a *frozen mode*.

When the contract is frozen, the following happens:

1. Deposits are no longer possible.
2. A map `withdrawnAmount : Address -> Value` is added to the contract storage, which maintains the total amounts that each user have withdrawn.

In order to withdraw, a user with address `address` must provide to the L1 contract the witnesses to

1. their balance `balance` and nonce `n` in some rollup block `b`.
2. all pending transfers *from* them with nonces `n, n+1, ... current_nonce`, where `current_nonce` is their nonce in the latest rollup state. We denote the total amount as `sentAmount`.
3. a set of pending transfers sent to them, in blocks that are all at least as new as *b* above. We denote the total amount as `recievedAmount`. All transfers must have been applied, meaning that the nonce of the sender is at least as large as the nonce of the transfer.

When the L1 contract is given the above data, it sends the user the amount given by

`balance + recievedAmount - sentAmount - withdrawnAmount(address)`

and adds the withdrawn amount to `withdrawnAmount(addressf)`.

## Example 1: Single tranfer from Alice to Bob

Alice wants to send 5 ETH to Bob. Her current nonce is 7. The procedure is as follows:

1. Alice signs a transfer
    ```
    transfer =
        ( nonce = 8
        , fromAddress = aliceAddress
        , toAddress = bobAddress
        , amount = 5 ETH
        )
    ```
    and sends it to the operator.
2. The operator includes the operation `AddTransfer(transfer, signature)` in the next rollup batch, which adds the transfer to the set of pending transfers in the off-chain state.
3. The operator sends a witness of the pending transfer to Alice.
4. Once Alice have the witness, she signes the message "Update nonce to 8" and sends this signed message to the operator.
5. The operator includes the operation
   ```
   UpdateNonce(
     address = aliceAddress
   , newNonce = 8
   , signature = signature
   )
   ```
   in the next rollup batch, which updates Alice's nonce in the on-chain state and applies the transfer to Bob in the off-chain state.
6. The operator publishes the new off-chain state, where Bob's balance is increased by 5 ETH, and Alice's balance is decrease by 5 ETH.

### Proof of safety in case the operator misbehaves

The operator may misbehave in several stages in the example above. If this happens, users can exit by sending a `ForceWithdrawal` operation to the L1 inbox. If the operator then doesn't add a new batch in 3 days, anyone can call the freeze command on L1, and the rollup is frozen. For Alice and Bob, there are three scenarios:

* The transfer from Alice to Bob was not applied (it is either pending or wasn't included at all). Then Alice will use a witness of her latest balance to exit.
* The transfer was applied, but the operator didn't provide the witnesses to the new balances of Alice and Bob. In this case, Alice have a witness of the pending transfer to Bob (otherwise she wouldn't update her nonce). Alice can then withdraw using the witness of her previous balance (without the transfer to Bob), plus a witness to the pending transfer to Bob. Bob may withdraw with his previous balance, plus a witness of the pending transfer from Alice, which he could obtain from Alice.

In all three cases, both Alice's and Bob's (and all other user's) funds are safe.

# Example 2: Batch of transfers from Alice to 1000 recipients

Suppose Alice is a big employer and want to send salaries to 1000 people. She may then batch them all together to save calldata. The procedure for this is the same as in Example 1 above, but instead of updating her nonce after each transfer, Alice will only update her nonce after the operator has added all 1000 transfers to the set of pending transfers, and she has recieved the witnesses to all off them from the operator.

# Calldata usage

For a batch of transfer from the same sender, the only data that needs to be provided as calldata is the data needed to update the sender's nonce, which is 6 bytes for the sender address (supporting up to 2^48 ~ 300 trillion accounts) and 2 bytes to specify how much the nonce is increased. In total **8 bytes for a batch of up to (2^16 = 65536) transfers from the same sender**. This is already less calldata than regular rollups if the batch has only one transfer, and is much less per transfer for larger batches.

# Open question: How to generalize this proposal to support smart contracts?

# TODO

- [x] Describe deposits and withdrawals in the normal case
- [x] Add examples of how to use the rollup, and what data must be stored by each user
- [x] Add example of how to withdraw in the case of a contract freeze
- [x] Estimate amortized gas costs per transfer
- [ ] After the above is done, publish the document to ethresear.ch to get some more feedback
- [ ] Do more research to see if the concept can be generalized to contracts, and not just transfers