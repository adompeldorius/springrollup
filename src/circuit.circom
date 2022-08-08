pragma circom 2.0.0;

include "processBatch.circom";
//include "test.circom";
include "circomlib/circuits/smt/smtprocessor.circom";
//include "lib/utils-bjj.circom";

component main = ProcessBatch(2, 3);
//component main = SMTProcessor(3);
