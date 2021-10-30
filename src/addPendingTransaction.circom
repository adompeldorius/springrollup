pragma circom 2.0.0;

include "circomlib/circuits/smt/smtprocessor.circom";
include "lib/hash-state.circom";

template AddPendingTransaction (nLevels, pLevels) {
  signal input oldRoot;
  signal output newRoot;

  signal input senderIdx;
  signal input senderSign;
  signal input senderAy;
  signal input senderBalance;
  signal input senderNumPendingTransactions;
  signal input senderPendingTransactionsRoot;
  signal input senderSiblings[nLevels];

  signal input receiverIdx;
  signal input receiverSiblings[pLevels];
  
  signal input amount;
  
  // Compute new merkle root for the sender's pending transactions
  component pendingTransactions = SMTProcessor(pLevels);
  component hash = Poseidon(2);
  hash.inputs[0] <== receiverIdx;
  hash.inputs[1] <== amount;

  pendingTransactions.oldRoot <== senderPendingTransactionsRoot;
  for(var i = 0; i < pLevels; i++){
    pendingTransactions.siblings[i] <== receiverSiblings[i];
  }
  pendingTransactions.oldKey <== 0;
  pendingTransactions.oldValue <== 0;
  pendingTransactions.isOld0 <== 1;
  pendingTransactions.newKey <== senderNumPendingTransactions;
  pendingTransactions.newValue <== hash.out;
  pendingTransactions.fnc[0] <== 1;
  pendingTransactions.fnc[1] <== 0;

  // Compute hash of old sender state
  component senderStateOld = HashState();
  senderStateOld.sign <== senderSign;
  senderStateOld.ay <== senderAy;
  senderStateOld.balance <== senderBalance;
  senderStateOld.numPendingTransactions <== senderNumPendingTransactions;
  senderStateOld.pendingTransactionsRoot <== senderPendingTransactionsRoot;

  log(senderStateOld.out);
  
  // Compute hash of new sender state
  component senderStateNew = HashState();
  senderStateNew.sign <== senderSign;
  senderStateNew.ay <== senderAy;
  senderStateNew.balance <== senderBalance;
  senderStateNew.numPendingTransactions <== senderNumPendingTransactions + 1;
  senderStateNew.pendingTransactionsRoot <== pendingTransactions.newRoot;

  // Update state
  component state = SMTProcessor(nLevels);

  state.oldRoot <== oldRoot;
  for(var i = 0; i < nLevels; i++){
    state.siblings[i] <== senderSiblings[i];
  }
  state.oldKey <== senderIdx;
  state.oldValue <== senderStateOld.out;
  state.isOld0 <== 1;
  state.newKey <== senderIdx;
  state.newValue <== senderStateNew.out;
  state.fnc[0] <== 0;
  state.fnc[1] <== 1;
  
  newRoot <== state.newRoot;
  //newRoot <== 123;
}
