import 'package:flutter/services.dart';

class PhilippinePhoneFormatter extends TextInputFormatter {
  /// Removes non-digits and formats the number as 9XX XXX XXXX.
  static String formatDigits(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 10 ? digits.substring(0, 10) : digits;

    final buffer = StringBuffer();

    for (int i = 0; i < limited.length; i++) {
      if (i == 3 || i == 6) {
        buffer.write(' ');
      }
      buffer.write(limited[i]);
    }

    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }

    final original = newValue.text;
    final digitsBeforeCursor = original
        .substring(0, newValue.selection.extentOffset.clamp(0, original.length))
        .replaceAll(RegExp(r'\D'), '')
        .length;

    final formatted = formatDigits(original);

    int cursorPosition = 0;
    int countedDigits = 0;

    while (cursorPosition < formatted.length &&
        countedDigits < digitsBeforeCursor) {
      if (formatted[cursorPosition] != ' ') {
        countedDigits++;
      }
      cursorPosition++;
    }

    // Keep the cursor after the grouping space.
    if (cursorPosition < formatted.length && formatted[cursorPosition] == ' ') {
      cursorPosition++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorPosition),
    );
  }
}
