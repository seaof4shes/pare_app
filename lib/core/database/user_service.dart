import 'package:cloud_firestore/cloud_firestore.dart';

import 'local_database.dart';
import '../utils/hash_helper.dart';

class UserService {
  Future<int> createUser({
    required String username,
    required String phoneNumber,
    required String mpin,
  }) async {
    final db = await LocalDatabase.instance.database;

    return await db.insert('users', {
      'username': username,
      'phone_number': phoneNumber,
      'mpin_hash': HashHelper.hashMpin(mpin),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> restoreUserFromFirestore({
    required String phoneNumber,
    required String mpin,
  }) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(phoneNumber)
        .get();

    if (!doc.exists) return false;

    final data = doc.data();
    if (data == null) return false;

    final firestoreHash = data['mpin_hash'];
    final inputHash = HashHelper.hashMpin(mpin);

    if (firestoreHash != inputHash) return false;

    await createUser(
      username: data['username'] ?? 'User',
      phoneNumber: phoneNumber,
      mpin: mpin,
    );

    return true;
  }

  Future<void> updateMpinLocal({
    required String phoneNumber,
    required String newMpin,
  }) async {
    final db = await LocalDatabase.instance.database;

    await db.update(
      'users',
      {'mpin_hash': HashHelper.hashMpin(newMpin)},
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
    );
  }

  Future<void> updateMpinFirestore({
    required String phoneNumber,
    required String newMpin,
  }) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(phoneNumber)
        .update({
          'mpin_hash': HashHelper.hashMpin(newMpin),
          'updated_at': DateTime.now().toIso8601String(),
        });
  }

  Future<void> syncUserToFirestore({
    required String username,
    required String phoneNumber,
    required String mpin,
  }) async {
    await FirebaseFirestore.instance.collection('users').doc(phoneNumber).set({
      'username': username,
      'phone_number': phoneNumber,
      'mpin_hash': HashHelper.hashMpin(mpin),
      'created_at': DateTime.now().toIso8601String(),
      'synced_from': 'sqlite',
    });
  }

  Future<bool> loginUser({
    required String usernameOrPhone,
    required String mpin,
  }) async {
    final db = await LocalDatabase.instance.database;

    final result = await db.query(
      'users',
      where: '(username = ? OR phone_number = ?) AND mpin_hash = ?',
      whereArgs: [usernameOrPhone, usernameOrPhone, HashHelper.hashMpin(mpin)],
    );

    return result.isNotEmpty;
  }

  Future<Map<String, dynamic>?> getUserByPhone(String phoneNumber) async {
    final db = await LocalDatabase.instance.database;

    final result = await db.query(
      'users',
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
      limit: 1,
    );

    if (result.isEmpty) return null;

    return result.first;
  }

  Future<bool> phoneExists(String phoneNumber) async {
    final db = await LocalDatabase.instance.database;

    final result = await db.query(
      'users',
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
    );

    return result.isNotEmpty;
  }
}
