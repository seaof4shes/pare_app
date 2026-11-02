# Voice v6 packaging validation

V6 reuses the trained V4 H5 weights, preprocessing and decision thresholds. It changes the export: the existing LSTM consumes a single time step after `Reshape((1, 128))`, so unrolling it eliminates TensorList/Flex operations. It is not a newly trained detector or an accuracy improvement claim.

`convert_voice_builtin.py` creates a candidate with built-in LiteRT operators only. It checks original Keras versus unrolled Keras and then the exported LiteRT runtime on all 1,640 existing test samples. The measured maximum absolute score difference was 0.00000153482, with zero Low/Medium/High category disagreements. This is numerical regression evidence, not independent real-world accuracy validation. Exact hashes and environment are recorded in `voice_builtin_candidate.json`.

The source V4 `.tflite` in the training folder matches the former bundled asset SHA-256 `8149a85ba7b2f109b0b35508c4c032895e1ba0d18815683f502bd32f651e7474`. Windows cannot run its Flex operators, so the numerical reference is the original H5 model, not execution of the old flatbuffer. The deployed candidate SHA-256 is `9374ba6ae0edb6c10a9014d9eb9b2464c17ed927ede964542938e6fffbd847fa`.

The Android model integration test passed on the connected Samsung with the Flex dependency removed: bundled model load/inference, silence handling, a generated voiced waveform, SMS Low/High checks, and existing encrypted storage checks. The other integration check verified native MPIN compatibility. These are smoke tests, not validation on every supported device.

Bundled model version is now 6 so older downloaded V4/V5 packages do not override it. Future downloaded models must execute using built-in operators; validation rejects incompatible packages and the bundled model is the fallback. The user-facing update page no longer installs models separately; future detection updates should be delivered in app releases.

Sources: https://keras.io/api/layers/recurrent_layers/lstm/ and https://github.com/tensorflow/tensorflow/blob/master/tensorflow/lite/g3doc/guide/reduce_binary_size.md
