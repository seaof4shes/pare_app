"""Re-export the existing v4 weights with an unrolled, single-step LSTM.

Writes a candidate only after numerical agreement checks; no retraining.
Run using the voice_model_v4 TensorFlow environment from the workspace.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
import tensorflow as tf

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'voice_model_v4/models/voice_model_v4.h5'
OUTPUT = Path(__file__).resolve().parents[1] / 'build/voice_builtin_candidate.tflite'
model = tf.keras.models.load_model(SOURCE, compile=False)

def clone(layer):
    config = layer.get_config()
    if isinstance(layer, tf.keras.layers.LSTM):
        config['unroll'] = True
    return layer.__class__.from_config(config)

candidate = tf.keras.models.clone_model(model, clone_function=clone)
candidate.set_weights(model.get_weights())
@tf.function(input_signature=[tf.TensorSpec([1, 40, 157, 2], tf.float32)])
def serve(x):
    return candidate(x, training=False)

converter = tf.lite.TFLiteConverter.from_concrete_functions([serve.get_concrete_function()], candidate)
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
data = converter.convert()
runtime = tf.lite.Interpreter(model_content=data)
runtime.allocate_tensors()
inputs = runtime.get_input_details()[0]
outputs = runtime.get_output_details()[0]
samples = np.load(ROOT / 'voice_model_v4/X_test (1).npy', mmap_mode='r')
max_error = 0.0
disagreements = 0
for start in range(0, len(samples), 32):
    batch = np.asarray(samples[start:start + 32], dtype=np.float32)
    expected = model(batch, training=False).numpy().reshape(-1)
    cloned = candidate(batch, training=False).numpy().reshape(-1)
    np.testing.assert_allclose(cloned, expected, atol=1e-5, rtol=1e-5)
    for sample, reference in zip(batch, expected):
        runtime.set_tensor(inputs['index'], sample[None])
        runtime.invoke()
        actual = float(runtime.get_tensor(outputs['index']).reshape(-1)[0])
        if not np.isfinite(actual) or not 0 <= actual <= 1:
            raise RuntimeError('Invalid candidate model score')
        max_error = max(max_error, abs(actual - float(reference)))
        severity = lambda x: 0 if x <= 0.45 else (2 if x >= 0.65 else 1)
        disagreements += severity(actual) != severity(reference)
if max_error > 1e-4 or disagreements:
    raise RuntimeError(f'Parity failed: {max_error=}, {disagreements=}')
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
OUTPUT.write_bytes(data)
report = dict(samples=len(samples), max_abs_error=max_error,
              severity_disagreements=disagreements, bytes=len(data),
              source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
              candidate_sha256=hashlib.sha256(data).hexdigest(),
              tensorflow=tf.__version__)
OUTPUT.with_suffix('.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
