pragma circom 2.0.0;

include "batchPendingTransactions.circom";
//include "test.circom";
//include "circomlib/circuits/smt/smtprocessor.circom";
//include "lib/utils-bjj.circom";

component main = BatchPendingTransactions(1, 3, 2);
//component main = AySign2Ax();
