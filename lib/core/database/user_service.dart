import 'dart:async';
import '../security/local_crypto_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'local_database.dart';
import '../utils/hash_helper.dart';

class UserService {
  UserService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;
  final _crypto = LocalCryptoService.instance;
  Future<String> _phoneKey(String phone) => _crypto.lookupKey('phone:$phone');
  Future<Map<String, dynamic>> _decode(Map<String, dynamic> row) async {
    final result = Map<String, dynamic>.from(row);
    for (final field in [
      'username',
      'phone_number',
      'firebase_uid',
      'mpin_hash',
    ]) {
      if (result[field] != null) {
        result[field] = await _crypto.decryptText(result[field].toString());
      }
    }
    return result;
  }

  void _requirePhone(String phone) {
    if (_auth.currentUser?.phoneNumber != phone) {
      throw StateError('Verify this phone number first');
    }
  }

  Future<void> _requireRecentPhone(String phone) async {
    _requirePhone(phone);
    final token = await _auth.currentUser!.getIdTokenResult();
    final authenticatedAt = token.authTime;
    if (authenticatedAt == null ||
        DateTime.now().difference(authenticatedAt) >
            const Duration(minutes: 5)) {
      throw StateError(
        'Please verify your phone again before changing the MPIN',
      );
    }
  }

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

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
    await _requireRecentPhone(phoneNumber);
    final db = await LocalDatabase.instance.database;
    final existing = await getUserByPhone(phoneNumber);
    final values = <String, dynamic>{
      'firebase_uid': await _crypto.encryptText(_auth.currentUser!.uid),
      'username': await _crypto.encryptText(username),
      'phone_number': await _crypto.encryptText(phoneNumber),
      'username_lookup': await _crypto.lookupKey('username:$username'),
      'phone_lookup': await _phoneKey(phoneNumber),
      'mpin_hash': await _crypto.encryptText(await HashHelper.hashMpin(mpin)),
      'failed_mpin_attempts': 0,
      'locked_until': null,
    };
    if (existing != null) {
      await db.update(
        'users',
        values,
        where: 'id = ?',
        whereArgs: [existing['id']],
      );
      return existing['id'] as int;
    }
    values['created_at'] = DateTime.now().toIso8601String();
    return db.insert('users', values);
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

    _requirePhone(phoneNumber);
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

    if (uid != currentUserId) throw StateError('Account access denied');
    final doc = await _users.doc(uid).get();

    if (!doc.exists) return null;

    return doc.data();
  }

  Future<Map<String, dynamic>?> getUserFromFirestore(String uid) async {
    if (uid != currentUserId) throw StateError('Account access denied');
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
      where: 'username_lookup = ?',
      whereArgs: [await _crypto.lookupKey('username:$username')],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<bool> phoneExists(String phoneNumber) async {
    final db = await LocalDatabase.instance.database;

    final result = await db.query(
      'users',
      where: 'phone_lookup = ?',
      whereArgs: [await _phoneKey(phoneNumber)],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  // ============================================================
  // CHECK FIRESTORE USER BY PHONE
  // ============================================================

  Future<bool> phoneExistsInFirebase(String phoneNumber) async {
    _requirePhone(phoneNumber);
    return (await _users.doc(_auth.currentUser!.uid).get()).exists;
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

    if (uid != currentUserId) throw StateError('Account access denied');
    final doc = await _users.doc(uid).get();

    if (!doc.exists) return false;

    final data = doc.data();

    if (data == null) return false;

    final username = data['username']?.toString().trim().isNotEmpty == true
        ? data['username'].toString()
        : 'User';

    // The verified Firebase identity owns this UID. An older profile may have
    // a local-format or stale phone string; never use that as auth identity.
    final phoneNumber = firebaseUser.phoneNumber ?? '';

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
    await _requireRecentPhone(phoneNumber);
    final db = await LocalDatabase.instance.database;

    final values = {
      'mpin_hash': await _crypto.encryptText(
        await HashHelper.hashMpin(newMpin),
      ),
      'failed_mpin_attempts': 0,
      'locked_until': null,
    };

    await db.update(
      'users',
      values,
      where: 'phone_lookup = ?',
      whereArgs: [await _phoneKey(phoneNumber)],
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
    await _requireRecentPhone(phoneNumber);
    await _users.doc(_auth.currentUser!.uid).update({
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
      _requirePhone(phoneNumber);
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
      where: 'phone_lookup = ?',
      whereArgs: [await _phoneKey(phoneNumber)],
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
      where: 'phone_lookup = ?',
      whereArgs: [await _phoneKey(phoneNumber)],
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
      where: 'phone_lookup = ?',
      whereArgs: [await _phoneKey(phoneNumber)],
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
      where: 'phone_lookup = ?',
      whereArgs: [await _phoneKey(phoneNumber)],
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
        where: 'phone_lookup = ?',
        whereArgs: [await _phoneKey(phoneNumber)],
      );
    } else {
      await db.update(
        'users',
        {'failed_mpin_attempts': newAttempts},
        where: 'phone_lookup = ?',
        whereArgs: [await _phoneKey(phoneNumber)],
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
      where: 'phone_lookup = ?',
      whereArgs: [await _phoneKey(phoneNumber)],
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
      where: 'phone_lookup = ?',
      whereArgs: [await _phoneKey(phoneNumber)],
    );
  }

  // ============================================================
  // LOCAL MPIN CHECK
  // ============================================================

  Future<bool> verifyLocalMpin({
    required String usernameOrPhone,
    required String mpin,
  }) => loginUser(usernameOrPhone: usernameOrPhone, mpin: mpin);

  // ============================================================
  // LOCAL LOGIN / MPIN CHECK WITH SECURITY
  // ============================================================

  static Future<void> _loginQueue = Future.value();
  Future<bool> loginUser({
    required String usernameOrPhone,
    required String mpin,
  }) {
    final complete = Completer<bool>();
    _loginQueue = _loginQueue.then((_) async {
      try {
        complete.complete(
          await _loginSerial(usernameOrPhone: usernameOrPhone, mpin: mpin),
        );
      } catch (error, stack) {
        complete.completeError(error, stack);
      }
    });
    return complete.future;
  }

  Future<bool> _loginSerial({
    required String usernameOrPhone,
    required String mpin,
  }) async {
    final db = await LocalDatabase.instance.database;

    final userResult = await db.query(
      'users',
      where: 'username_lookup = ? OR phone_lookup = ?',
      whereArgs: [
        await _crypto.lookupKey('username:$usernameOrPhone'),
        await _phoneKey(usernameOrPhone),
      ],
      limit: 1,
    );

    if (userResult.isEmpty) {
      return false;
    }

    final user = await _decode(userResult.first);
    final phoneNumber = user['phone_number'].toString();

    // Check whether account is currently locked.
    final lockedUntil = DateTime.tryParse(
      user['locked_until']?.toString() ?? '',
    );
    if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
      return false;
    }

    final storedHash = user['mpin_hash']?.toString();

    if (storedHash != null && await HashHelper.verify(mpin, storedHash)) {
      if (!storedHash.startsWith('pbkdf2-sha256:')) {
        await db.update(
          'users',
          {
            'mpin_hash': await _crypto.encryptText(
              await HashHelper.hashMpin(mpin),
            ),
          },
          where: 'id = ?',
          whereArgs: [user['id']],
        );
      }
      await db.update(
        'users',
        {
          'failed_mpin_attempts': 0,
          'locked_until': null,
          'last_login_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [user['id']],
      );

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
      where: 'phone_lookup = ?',
      whereArgs: [await _phoneKey(phoneNumber)],
      limit: 1,
    );

    if (result.isEmpty) return null;

    return _decode(result.first);
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
