pragma circom 2.0.0;

include "circomlib/circuits/smt/smtprocessor.circom";
include "circomlib/circuits/eddsaposeidon.circom";
include "lib/hash-state.circom";
include "lib/utils-bjj.circom";

template AddPendingTransaction (nLevels, pLevels) {
  signal input oldRoot;
  signal output newRoot;

  signal input senderIdx;
  signal input senderSign;
  signal input senderAy;
  signal input senderNonce;
  signal input senderBalance;
  signal input senderNumPendingTransactions;
  signal input senderPendingTransactionsRoot;
  signal input senderSiblings[nLevels];

  // Signature by sender
  signal input s;
  signal input r8x;
  signal input r8y;

  signal input receiverIdx;
  signal input receiverSiblings[pLevels];
  
  signal input amount;

  // Check signature
  ////////

  // computes transaction hash
  component msg = Poseidon(4);
  msg.inputs[0] <== senderNonce;
  msg.inputs[1] <== senderNumPendingTransactions;
  msg.inputs[2] <== receiverIdx;
  msg.inputs[3] <== amount;
  
  log(msg.out);

  // computes babyjubjub X coordinate
  component getAx = AySign2Ax();
  getAx.ay <== senderAy;
  getAx.sign <== senderSign;

  // verifies signature
  component sigVerifier = EdDSAPoseidonVerifier();
  sigVerifier.enabled <== 1;

  sigVerifier.Ax <== getAx.ax;
  sigVerifier.Ay <== senderAy;
  
  sigVerifier.S <== s;
  sigVerifier.R8x <== r8x;
  sigVerifier.R8y <== r8y;

  sigVerifier.M <== msg.out;
  
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
  senderStateOld.nonce <== senderNonce;
  senderStateOld.numPendingTransactions <== senderNumPendingTransactions;
  senderStateOld.pendingTransactionsRoot <== senderPendingTransactionsRoot;

  log(senderStateOld.out);
  
  // Compute hash of new sender state
  component senderStateNew = HashState();
  senderStateNew.sign <== senderSign;
  senderStateNew.ay <== senderAy;
  senderStateNew.balance <== senderBalance;
  senderStateNew.nonce <== senderNonce;
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
