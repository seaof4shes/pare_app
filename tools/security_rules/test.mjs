import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

const env = await initializeTestEnvironment({
  projectId: 'demo-pare-security',
  firestore: { host: '127.0.0.1', port: 8180, rules: readFileSync('firestore.rules', 'utf8') },
  storage: { host: '127.0.0.1', port: 9299, rules: readFileSync('storage.rules', 'utf8') },
});
try {
  const alice = env.authenticatedContext('alice', { phone_number: '+630000000001' });
  const bob = env.authenticatedContext('bob', { phone_number: '+630000000002' });
  const guest = env.unauthenticatedContext();
  await assertSucceeds(setDoc(doc(alice.firestore(), 'users/alice'), {
    username: 'Alice', phoneNumber: '+630000000001', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(doc(alice.firestore(), 'users/alice')));
  await assertFails(getDoc(doc(bob.firestore(), 'users/alice')));
  await assertFails(getDoc(doc(guest.firestore(), 'users/alice')));
  await assertFails(getDocs(collection(alice.firestore(), 'users')));
  await assertSucceeds(updateDoc(doc(alice.firestore(), 'users/alice'), { username: 'Alice Updated', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(alice.firestore(), 'users/alice'), { phoneNumber: '+630000000002', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(alice.firestore(), 'users/alice'), { mpin_hash: 'must-not-be-uploaded', updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(alice.firestore(), 'app_updates/latest'), { smsModelVersion: 999 }));
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'app_updates/latest'), { smsModelVersion: 4 });
    await uploadBytes(ref(context.storage(), 'updates/models/test.tflite'), new Uint8Array([1, 2, 3]));
  });
  await assertSucceeds(getDoc(doc(alice.firestore(), 'app_updates/latest')));
  await assertFails(getDoc(doc(guest.firestore(), 'app_updates/latest')));
  await assertSucceeds(getBytes(ref(alice.storage(), 'updates/models/test.tflite')));
  await assertFails(getBytes(ref(guest.storage(), 'updates/models/test.tflite')));
  await assertFails(uploadBytes(ref(alice.storage(), 'updates/models/test.tflite'), new Uint8Array([9])));
  await assertFails(uploadBytes(ref(alice.storage(), 'private-audio.wav'), new Uint8Array([9])));
  console.log('PASS: 14 Firestore/Storage ownership, privacy and update-publication checks.');
} finally {
  await env.cleanup();
}
