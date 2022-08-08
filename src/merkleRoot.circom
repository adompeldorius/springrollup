pragma circom 2.0.0;

include "circomlib/circuits/poseidon.circom";

// Circuit to compute the root of a merkle tree
template MerkleRoot (nLevels) {
  signal input leaves[2**nLevels];
  signal output root;
  component leftTree;
  component rightTree;
  component h;

  if (nLevels > 0) {
    var i;

    leftTree = MerkleRoot(nLevels-1);
    for (i = 0; i < 2**(nLevels - 1); i++) {
      leftTree.leaves[i] <== leaves[i];
    }
    
    rightTree = MerkleRoot(nLevels-1);
    for (i = 0; i < 2**(nLevels - 1); i++) {
      rightTree.leaves[i] <== leaves[i + 2**(nLevels - 1)];
    }

    h = Poseidon(2);
    h.inputs[0] <== leftTree.root;
    h.inputs[1] <== rightTree.root;
    root <== h.out;
  } else {
    root <== leaves[0];
  }
}
