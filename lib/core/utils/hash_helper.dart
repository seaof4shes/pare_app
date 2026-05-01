import 'dart:convert';
import 'package:crypto/crypto.dart';

class HashHelper {
  static String hashMpin(String mpin) {
    return sha256.convert(utf8.encode(mpin)).toString();
  }
}
