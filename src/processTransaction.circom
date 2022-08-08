pragma circom 2.0.0;

include "circomlib/circuits/smt/smtprocessor.circom";
include "circomlib/circuits/smt/smtverifier.circom";
include "circomlib/circuits/eddsaposeidon.circom";
include "lib/hash-state.circom";
include "lib/utils-bjj.circom";

// Circuit to process a transaction
template ProcessTransaction (nLevels) {
  signal input oldAccountIdx;
  signal input oldBalance;

  // Root of the batch
  signal input batchRoot;

  // Old state root
  signal input oldStateRoot;

  // Account state
  signal input accountIdx;
  signal input accountSign;
  signal input accountAy;
  signal input accountBalance;
  signal input accountSiblings[nLevels];

  // Sender's signature
  signal input s;
  signal input r8x;
  signal input r8y;
  
  // Transaction data
  signal input amount;

  // Outputs
  signal output newStateRoot;
  signal output newAccountIdx;
  signal output newBalance;

  // Checks if account is sender
  signal isSender;

  component isEqual = IsEqual();
  isEqual.in[0] <== oldAccountIdx;
  isEqual.in[1] <== accountIdx;

  isSender <== 1 - isEqual.out;

  // Checks that previous balance is zero if account is sender

  component forceEqual = ForceEqualIfEnabled();
  forceEqual.enabled <== isSender;
  forceEqual.in[0] <== oldBalance;
  forceEqual.in[1] <== 0;

  // Check signature if account is sender

  // computes babyjubjub X coordinate
  component getAx = AySign2Ax();
  getAx.ay <== accountAy;
  getAx.sign <== accountSign;

  // verifies signature
  component sigVerifier = EdDSAPoseidonVerifier();
  sigVerifier.enabled <== isSender;

  sigVerifier.Ax <== getAx.ax;
  sigVerifier.Ay <== accountAy;

  sigVerifier.S <== s;
  sigVerifier.R8x <== r8x;
  sigVerifier.R8y <== r8y;

  sigVerifier.M <== batchRoot;

  // Compute hash of old account state
  component accountStateOld = HashState();
  accountStateOld.sign <== accountSign;
  accountStateOld.ay <== accountAy;
  accountStateOld.balance <== accountBalance;

  // Compute hash of new account state
  component accountStateNew = HashState();
  accountStateNew.sign <== accountSign;
  accountStateNew.ay <== accountAy;
  accountStateNew.balance <== accountBalance + amount;

  // Update state
  component state = SMTProcessor(nLevels);

  state.oldRoot <== oldStateRoot;
  for(var i = 0; i < nLevels; i++){
    state.siblings[i] <== accountSiblings[i];
  }
  state.oldKey <== accountIdx;
  state.oldValue <== accountStateOld.out;
  state.isOld0 <== 1;
  state.newKey <== accountIdx;
  state.newValue <== accountStateNew.out;
  state.fnc[0] <== 0;
  state.fnc[1] <== 1;
  
  newStateRoot <== state.newRoot;
  newAccountIdx <== accountIdx;
  newBalance <== oldBalance + amount;
}
