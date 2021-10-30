# Compile

```
circom --r1cs --wasm circuit.circom
```

# Setup prover

```
npx snarkjs groth16 setup circuit.r1cs powersOfTau28_hez_final_17.ptau circuit_final.zkey
```

# Generate witness

```
node circuit_js/generate_witness.js circuit_js/circuit.wasm input.json witness.wtns
```


# Create proof

```
npx snarkjs groth16 prove circuit_final.zkey witness.wtns proof.json public.json
```

# Export verification key (needed for verifying a proof)

```
npx snarkjs zkey export verificationkey circuit_final.zkey verification_key.json
```

# Verify proof

```
npx snarkjs groth16 verify verification_key.json public.json proof.json
```
