pragma circom 2.0.0;

include "circomlib/circuits/smt/smtprocessor.circom";
include "circomlib/circuits/eddsaposeidon.circom";
include "circomlib/circuits/mux1.circom";
include "lib/hash-state.circom";
include "lib/utils-bjj.circom";
include "addPendingTransaction.circom";

// Circuit to add a batch of pending transactions
template BatchPendingTransactions (nTx, nLevels, pLevels) {
  // State roots
  signal input oldRoot;
  signal output newRoot;

  // Is transaction enabled? This is 0 if transaction is no-op (used to pad a rollup block)
  signal input enabled[nTx];

  // Sender state
  signal input senderIdx[nTx];
  signal input senderSign[nTx];
  signal input senderAy[nTx];
  signal input senderNonce[nTx];
  signal input senderBalance[nTx];
  signal input senderNumPendingTransactions[nTx];
  signal input senderPendingTransactionsRoot[nTx];
  signal input senderSiblings[nTx][nLevels];

  // Signature by sender
  signal input s[nTx];
  signal input r8x[nTx];
  signal input r8y[nTx];

  // Transaction data
  signal input receiverIdx[nTx];
  signal input receiverSiblings[nTx][pLevels];
  signal input amount[nTx];

  var i;
  var j;

  component addPendingTransaction[nTx];

  // Add pending transactions
  for (i = 0; i < nTx; i++) {
    addPendingTransaction[i] = AddPendingTransaction(nLevels, pLevels);
    addPendingTransaction[i].enabled <== enabled[i];

    addPendingTransaction[i].senderIdx <== senderIdx[i];
    addPendingTransaction[i].senderSign <== senderSign[i];
    addPendingTransaction[i].senderAy <== senderAy[i];
    addPendingTransaction[i].senderNonce <== senderNonce[i];
    addPendingTransaction[i].senderBalance <== senderBalance[i];
    addPendingTransaction[i].senderNumPendingTransactions <== senderNumPendingTransactions[i];
    addPendingTransaction[i].senderPendingTransactionsRoot <== senderPendingTransactionsRoot[i];

    for (j = 0; j < nLevels; j++) {
      addPendingTransaction[i].senderSiblings[j] <== senderSiblings[i][j];
    }

    addPendingTransaction[i].s <== s[i];
    addPendingTransaction[i].r8x <== r8x[i];
    addPendingTransaction[i].r8y <== r8y[i];
    
    addPendingTransaction[i].receiverIdx <== receiverIdx[i];
    
    for (j = 0; j < pLevels; j++) {
      addPendingTransaction[i].receiverSiblings[j] <== receiverSiblings[i][j];
    }

    addPendingTransaction[i].amount <== amount[i];
  }

//  // Connect state roots
  addPendingTransaction[0].oldRoot <== oldRoot;
  for (i = 0; i < nTx-1; i++) {
    addPendingTransaction[i].newRoot ==> addPendingTransaction[i+1].oldRoot;
  }

  newRoot <== addPendingTransaction[nTx-1].newRoot;
}
