/// History describes recorded actions, never guesses them from confidence.
String historyActionLabel(String? stored) {
  final action = stored?.trim() ?? '';
  switch (action) {
    case '':
      return 'Not recorded';
    case 'Allowed':
      return 'Logged Only';
    case 'Blocked':
    case 'Call Blocked':
    case 'Sender Blocked':
      return 'Block not verified';
    case 'Block/Report Spam Opened':
    case 'Message Opened for Blocking':
      return 'Messages opened';
    default:
      return action;
  }
}

String historyRiskLabel(String? stored) {
  final risk = stored?.trim().toUpperCase();
  return ['LOW', 'MEDIUM', 'HIGH'].contains(risk) ? risk! : 'UNKNOWN';
}
