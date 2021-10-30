pragma circom 2.0.0;

include "../circomlib/circuits/poseidon.circom";

/**
 * Computes the hash of an account state
 * State Hash = Poseidon(e0, e1, e2, e3, e4)
 * e0: sign
 * e1: ay
 * e2: nonce
 * e3: balance
 * e4: numPendingTransactions
 * e5: pendingTransactionsRoot
 * @input sign - {Bool} - babyjubjub sign
 * @input ay - {Field} - babyjubjub Y coordinate
 * @input balance - {Uint192} - account balance
 * @input numPendingTransactions - {Field} - number of pending transactions for the account
 * @input pendingTransactionsRoot - {Field} - merkle root for the account's pending transactions
 * @output out - {Field} - resulting poseidon hash
 */

template HashState() {
    signal input sign;
    signal input ay;
    signal input nonce;
    signal input balance;
    signal input numPendingTransactions;
    signal input pendingTransactionsRoot;
    
    signal output out;

    component hash = Poseidon(6);

    hash.inputs[0] <== sign;
    hash.inputs[1] <== ay;
    hash.inputs[2] <== nonce;
    hash.inputs[3] <== balance;
    hash.inputs[4] <== numPendingTransactions;
    hash.inputs[5] <== pendingTransactionsRoot;

    hash.out ==> out;
}
