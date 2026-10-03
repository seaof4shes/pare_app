import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'local_database.dart';
import '../utils/hash_helper.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  // ============================================================
  // SECURITY SETTINGS
  // ============================================================

  static const int maxMpinAttempts = 3;
  static const int lockoutMinutes = 5;

  // ============================================================
  // CURRENT FIREBASE USER
  // ============================================================

  User? get currentFirebaseUser => _auth.currentUser;

  String? get currentUserId => _auth.currentUser?.uid;

  // ============================================================
  // CREATE / CACHE USER LOCALLY
  // ============================================================

  Future<int> createUser({
    required String username,
    required String phoneNumber,
    required String mpin,
    String? userId,
  }) async {
    final db = await LocalDatabase.instance.database;

    final existing = await db.query(
      'users',
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
      limit: 1,
    );

    final now = DateTime.now().toIso8601String();

    if (existing.isNotEmpty) {
      await db.update(
        'users',
        {
          'firebase_uid': userId ?? existing.first['firebase_uid'],
          'username': username,
          'phone_number': phoneNumber,
          'mpin_hash': HashHelper.hashMpin(mpin),
        },
        where: 'phone_number = ?',
        whereArgs: [phoneNumber],
      );

      return existing.first['id'] as int;
    }

    return await db.insert('users', {
      'firebase_uid': userId,
      'username': username,
      'phone_number': phoneNumber,
      'mpin_hash': HashHelper.hashMpin(mpin),
      'created_at': now,
      'last_login_at': null,
      'failed_mpin_attempts': 0,
      'locked_until': null,
    });
  }

  // ============================================================
  // FIRESTORE USER
  // ============================================================

  Future<void> createOrUpdateFirestoreUser({
    required String username,
    required String phoneNumber,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw FirebaseAuthException(
        code: 'not-authenticated',
        message: 'No authenticated Firebase user.',
      );
    }

    final uid = user.uid;
    final userRef = _users.doc(uid);

    final existing = await userRef.get();

    if (!existing.exists) {
      await userRef.set({
        'username': username,
        'phoneNumber': phoneNumber,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await userRef.update({
        'username': username,
        'phoneNumber': phoneNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ============================================================
  // GET FIRESTORE USER
  // ============================================================

  Future<Map<String, dynamic>?> getCurrentUserFromFirestore() async {
    final uid = currentUserId;

    if (uid == null) return null;

    final doc = await _users.doc(uid).get();

    if (!doc.exists) return null;

    return doc.data();
  }

  Future<Map<String, dynamic>?> getUserFromFirestore(String uid) async {
    final doc = await _users.doc(uid).get();

    if (!doc.exists) return null;

    return doc.data();
  }

  // ============================================================
  // CHECK LOCAL USER
  // ============================================================

  Future<bool> usernameExists(String username) async {
    final db = await LocalDatabase.instance.database;

    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<bool> phoneExists(String phoneNumber) async {
    final db = await LocalDatabase.instance.database;

    final result = await db.query(
      'users',
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  // ============================================================
  // CHECK FIRESTORE USER BY PHONE
  // ============================================================

  Future<bool> phoneExistsInFirebase(String phoneNumber) async {
    final result = await _users
        .where('phoneNumber', isEqualTo: phoneNumber)
        .limit(1)
        .get();

    return result.docs.isNotEmpty;
  }

  // ============================================================
  // RESTORE CURRENT USER AFTER FIREBASE AUTH
  // ============================================================
  //
  // IMPORTANT:
  // This should only be used AFTER successful Firebase
  // phone verification / OTP.
  //
  // The MPIN is created locally on the device.
  // It is NEVER stored in Firestore.
  //
  // ============================================================

  Future<bool> restoreCurrentUserFromFirestore({required String mpin}) async {
    final firebaseUser = _auth.currentUser;

    if (firebaseUser == null) return false;

    final uid = firebaseUser.uid;

    final doc = await _users.doc(uid).get();

    if (!doc.exists) return false;

    final data = doc.data();

    if (data == null) return false;

    final username = data['username']?.toString().trim().isNotEmpty == true
        ? data['username'].toString()
        : 'User';

    final phoneNumber =
        data['phoneNumber']?.toString() ?? firebaseUser.phoneNumber ?? '';

    if (phoneNumber.isEmpty) return false;

    await createUser(
      username: username,
      phoneNumber: phoneNumber,
      mpin: mpin,
      userId: uid,
    );

    return true;
  }

  // ============================================================
  // OLD FIRESTORE RESTORE METHOD
  // ============================================================
  //
  // IMPORTANT:
  // This method is intentionally disabled.
  //
  // Normal login must NOT create a local MPIN simply because
  // the phone number exists in Firestore.
  //
  // Fresh-device restoration will be handled through:
  //
  // Phone Number → OTP → Establish Local MPIN
  //
  // ============================================================

  @Deprecated(
    'Do not use for authentication. Use OTP verification before local account restoration.',
  )
  Future<bool> restoreUserFromFirestore({
    required String phoneNumber,
    required String mpin,
  }) async {
    return false;
  }

  // ============================================================
  // UPDATE LOCAL MPIN
  // ============================================================

  Future<void> updateMpinLocal({
    required String phoneNumber,
    required String newMpin,
  }) async {
    final db = await LocalDatabase.instance.database;

    final values = {
      'mpin_hash': HashHelper.hashMpin(newMpin),
      'failed_mpin_attempts': 0,
      'locked_until': null,
    };

    await db.update(
      'users',
      values,
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
    );
  }

  // ============================================================
  // UPDATE FIRESTORE MPIN METADATA
  // ============================================================
  //
  // IMPORTANT:
  // The MPIN itself is NOT stored in Firestore.
  //
  // This only records that the local MPIN was changed after
  // successful phone verification.
  //
  // ============================================================

  Future<void> updateMpinFirestore({
    required String phoneNumber,
    required String newMpin,
  }) async {
    final result = await _users
        .where('phoneNumber', isEqualTo: phoneNumber)
        .limit(1)
        .get();

    if (result.docs.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'user-not-found',
        message: 'No Firestore user found for this phone number.',
      );
    }

    final userDoc = result.docs.first.reference;

    await userDoc.update({
      'updatedAt': FieldValue.serverTimestamp(),
      'mpinUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // UPDATE FIRESTORE USER PROFILE
  // ============================================================

  Future<void> updateFirestoreUser({
    String? username,
    String? phoneNumber,
  }) async {
    final uid = currentUserId;

    if (uid == null) {
      throw FirebaseAuthException(
        code: 'not-authenticated',
        message: 'No authenticated Firebase user.',
      );
    }

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (username != null) {
      updates['username'] = username;
    }

    if (phoneNumber != null) {
      updates['phoneNumber'] = phoneNumber;
    }

    await _users.doc(uid).update(updates);
  }

  // ============================================================
  // SYNC LOCAL USER → FIRESTORE
  // ============================================================

  Future<void> syncCurrentUserToFirestore() async {
    final firebaseUser = _auth.currentUser;

    if (firebaseUser == null) return;

    final phone = firebaseUser.phoneNumber ?? '';

    if (phone.isEmpty) return;

    final localUser = await getUserByPhone(phone);

    if (localUser == null) return;

    await createOrUpdateFirestoreUser(
      username: localUser['username']?.toString() ?? 'User',
      phoneNumber: localUser['phone_number']?.toString() ?? '',
    );
  }

  // ============================================================
  // SYNC USER TO FIRESTORE
  // ============================================================
  //
  // Used by the Signup / OTP flow.
  //
  // The MPIN is used ONLY to create the local hash.
  // It is NOT sent to Firestore.
  //
  // ============================================================

  Future<void> syncUserToFirestore({
    required String username,
    required String phoneNumber,
    required String mpin,
  }) async {
    await createOrUpdateFirestoreUser(
      username: username,
      phoneNumber: phoneNumber,
    );

    final firebaseUser = _auth.currentUser;

    if (firebaseUser != null) {
      await createUser(
        username: username,
        phoneNumber: phoneNumber,
        mpin: mpin,
        userId: firebaseUser.uid,
      );
    }
  }

  // ============================================================
  // CHECK IF LOCAL ACCOUNT IS LOCKED
  // ============================================================

  Future<bool> isMpinLocked(String phoneNumber) async {
    final db = await LocalDatabase.instance.database;

    final result = await db.query(
      'users',
      columns: ['locked_until'],
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
      limit: 1,
    );

    if (result.isEmpty) return false;

    final lockedUntil = result.first['locked_until']?.toString();

    if (lockedUntil == null || lockedUntil.isEmpty) {
      return false;
    }

    final lockTime = DateTime.tryParse(lockedUntil);

    if (lockTime == null) {
      return false;
    }

    if (DateTime.now().isBefore(lockTime)) {
      return true;
    }

    // Lockout has expired.
    await db.update(
      'users',
      {'failed_mpin_attempts': 0, 'locked_until': null},
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
    );

    return false;
  }

  // ============================================================
  // GET REMAINING LOCKOUT TIME
  // ============================================================

  Future<int> getRemainingLockoutSeconds(String phoneNumber) async {
    final db = await LocalDatabase.instance.database;

    final result = await db.query(
      'users',
      columns: ['locked_until'],
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
      limit: 1,
    );

    if (result.isEmpty) return 0;

    final lockedUntil = result.first['locked_until']?.toString();

    if (lockedUntil == null || lockedUntil.isEmpty) {
      return 0;
    }

    final lockTime = DateTime.tryParse(lockedUntil);

    if (lockTime == null) {
      return 0;
    }

    final remaining = lockTime.difference(DateTime.now()).inSeconds;

    return remaining > 0 ? remaining : 0;
  }

  // ============================================================
  // RECORD FAILED MPIN ATTEMPT
  // ============================================================

  Future<int> recordFailedMpinAttempt(String phoneNumber) async {
    final db = await LocalDatabase.instance.database;

    final result = await db.query(
      'users',
      columns: ['failed_mpin_attempts'],
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
      limit: 1,
    );

    if (result.isEmpty) return 0;

    final currentAttempts = (result.first['failed_mpin_attempts'] as int?) ?? 0;

    final newAttempts = currentAttempts + 1;

    if (newAttempts >= maxMpinAttempts) {
      final lockUntil = DateTime.now()
          .add(const Duration(minutes: lockoutMinutes))
          .toIso8601String();

      await db.update(
        'users',
        {'failed_mpin_attempts': newAttempts, 'locked_until': lockUntil},
        where: 'phone_number = ?',
        whereArgs: [phoneNumber],
      );
    } else {
      await db.update(
        'users',
        {'failed_mpin_attempts': newAttempts},
        where: 'phone_number = ?',
        whereArgs: [phoneNumber],
      );
    }

    return newAttempts;
  }

  // ============================================================
  // RESET FAILED MPIN ATTEMPTS
  // ============================================================

  Future<void> resetMpinAttempts(String phoneNumber) async {
    final db = await LocalDatabase.instance.database;

    await db.update(
      'users',
      {'failed_mpin_attempts': 0, 'locked_until': null},
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
    );
  }

  // ============================================================
  // UPDATE LAST LOGIN
  // ============================================================

  Future<void> updateLastLogin(String phoneNumber) async {
    final db = await LocalDatabase.instance.database;

    await db.update(
      'users',
      {'last_login_at': DateTime.now().toIso8601String()},
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
    );
  }

  // ============================================================
  // LOCAL MPIN CHECK
  // ============================================================

  Future<bool> verifyLocalMpin({
    required String usernameOrPhone,
    required String mpin,
  }) async {
    final db = await LocalDatabase.instance.database;

    final result = await db.query(
      'users',
      where: '''
        (username = ? OR phone_number = ?)
        AND mpin_hash = ?
      ''',
      whereArgs: [usernameOrPhone, usernameOrPhone, HashHelper.hashMpin(mpin)],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  // ============================================================
  // LOCAL LOGIN / MPIN CHECK WITH SECURITY
  // ============================================================

  Future<bool> loginUser({
    required String usernameOrPhone,
    required String mpin,
  }) async {
    final db = await LocalDatabase.instance.database;

    final userResult = await db.query(
      'users',
      where: 'username = ? OR phone_number = ?',
      whereArgs: [usernameOrPhone, usernameOrPhone],
      limit: 1,
    );

    if (userResult.isEmpty) {
      return false;
    }

    final user = userResult.first;
    final phoneNumber = user['phone_number'].toString();

    // Check whether account is currently locked.
    if (await isMpinLocked(phoneNumber)) {
      return false;
    }

    final storedHash = user['mpin_hash']?.toString();

    final enteredHash = HashHelper.hashMpin(mpin);

    if (storedHash == enteredHash) {
      await resetMpinAttempts(phoneNumber);
      await updateLastLogin(phoneNumber);

      return true;
    }

    await recordFailedMpinAttempt(phoneNumber);

    return false;
  }

  // ============================================================
  // GET LOCAL USER
  // ============================================================

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

  // ============================================================
  // GET CURRENT LOCAL USER
  // ============================================================

  Future<Map<String, dynamic>?> getCurrentLocalUser() async {
    final firebaseUser = _auth.currentUser;

    if (firebaseUser == null) return null;

    final phone = firebaseUser.phoneNumber;

    if (phone == null || phone.isEmpty) return null;

    return getUserByPhone(phone);
  }
}
