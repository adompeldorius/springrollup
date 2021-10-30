pragma circom 2.0.0;

include "../circomlib/circuits/poseidon.circom";

/**
 * Computes the hash of an account state
 * State Hash = Poseidon(e0, e1, e2, e3, e4)
 * e0: sign
 * e1: ay
 * e2: balance
 * e3: numPendingTransactions
 * e4: pendingTransactionsRoot
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
    signal input balance;
    signal input numPendingTransactions;
    signal input pendingTransactionsRoot;
    
    signal output out;

    component hash = Poseidon(5);

    hash.inputs[0] <== sign;
    hash.inputs[1] <== ay;
    hash.inputs[2] <== balance;
    hash.inputs[3] <== numPendingTransactions;
    hash.inputs[4] <== pendingTransactionsRoot;

    hash.out ==> out;
}
