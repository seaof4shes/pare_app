// Test-only SDK doubles; no sealed SDK implementation is used in the app.
// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pare_app/core/database/user_service.dart';

class TestUser implements User {
  @override
  String get uid => 'verified-uid';
  @override
  String get phoneNumber => '+639000000042';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAuth implements FirebaseAuth {
  @override
  User get currentUser => TestUser();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  TestSnapshot(this.phone);
  final String phone;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => {'username': 'Test', 'phoneNumber': phone};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestDoc implements DocumentReference<Map<String, dynamic>> {
  TestDoc(this.phone);
  final String phone;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => TestSnapshot(phone);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestCollection implements CollectionReference<Map<String, dynamic>> {
  TestCollection(this.phone);
  final String phone;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    expect(path, 'verified-uid');
    return TestDoc(phone);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestStore implements FirebaseFirestore {
  TestStore(this.phone);
  final String phone;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      TestCollection(phone);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RestoreService extends UserService {
  RestoreService(String profilePhone)
    : super(auth: TestAuth(), firestore: TestStore(profilePhone));
  String? restoredPhone;
  @override
  Future<int> createUser({
    required String username,
    required String phoneNumber,
    required String mpin,
    String? userId,
  }) async {
    restoredPhone = phoneNumber;
    return 1;
  }
}

void main() {
  test(
    'Restoration trusts the verified UID phone, never an old profile phone',
    () async {
      for (final profilePhone in ['09000000042', '+639000000099', '']) {
        final service = RestoreService(profilePhone);
        expect(
          await service.restoreCurrentUserFromFirestore(mpin: '123456'),
          isTrue,
        );
        expect(service.restoredPhone, '+639000000042');
      }
    },
  );
}
