pragma circom 2.0.0;

include "circomlib/circuits/smt/smtprocessor.circom";
include "circomlib/circuits/eddsaposeidon.circom";
include "circomlib/circuits/mux1.circom";
include "lib/hash-state.circom";
include "lib/utils-bjj.circom";
include "processTransaction.circom";
include "merkleRoot.circom";

// Circuit to add a batch of pending transactions
template ProcessBatch (bLevels, nLevels) {
  var nTx = 2**bLevels;

  // State roots
  signal input oldStateRoot;
  signal output newStateRoot;
  
  // Account state
  signal input accountIdx[nTx];
  signal input accountSign[nTx];
  signal input accountAy[nTx];
  signal input accountBalance[nTx];
  signal input accountSiblings[nTx][nLevels];

  // Signature by sender
  signal input s[nTx];
  signal input r8x[nTx];
  signal input r8y[nTx];

  // Transaction data
  signal input amount[nTx];
  
  var i;
  var j;

  // Compute transaction tree hash
  component transactionTree = MerkleRoot(bLevels);
  component h[nTx];
  
  for (i = 0; i < nTx; i++) {
    h[i] = Poseidon(2);
    h[i].inputs[0] <== accountIdx[i];
    h[i].inputs[1] <== amount[i];
    transactionTree.leaves[i] <== h[i].out;
  }

  component processTransaction[nTx];

  // Process transactions
  for (i = 0; i < nTx; i++) {
    processTransaction[i] = ProcessTransaction(nLevels);

    processTransaction[i].accountIdx <== accountIdx[i];
    processTransaction[i].batchRoot <== transactionTree.root;
    processTransaction[i].accountSign <== accountSign[i];
    processTransaction[i].accountAy <== accountAy[i];
    processTransaction[i].accountBalance <== accountBalance[i];
    
    for (j = 0; j < nLevels; j++) {
      processTransaction[i].accountSiblings[j] <== accountSiblings[i][j];
    }

    processTransaction[i].s <== s[i];
    processTransaction[i].r8x <== r8x[i];
    processTransaction[i].r8y <== r8y[i];
    
    processTransaction[i].amount <== amount[i];
  }

  // Connect signals between transactions
  0 ==> processTransaction[0].oldBalance;
  0 ==> processTransaction[0].oldAccountIdx;
  oldStateRoot ==> processTransaction[0].oldStateRoot;
  for (i = 0; i < nTx-1; i++) {
    processTransaction[i].newBalance ==> processTransaction[i+1].oldBalance;
    processTransaction[i].newAccountIdx ==> processTransaction[i+1].oldAccountIdx;
    processTransaction[i].newStateRoot ==> processTransaction[i+1].oldStateRoot;
  }
  
  processTransaction[nTx-1].newBalance === 0;
  processTransaction[nTx-1].newStateRoot ==> newStateRoot;
}
