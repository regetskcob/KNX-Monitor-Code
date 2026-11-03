import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Via the add-on server to Home Assistant (without effect outside the add-on).
Future<void> sendNotification({
  required String id,
  required String title,
  required String body,
  bool silent = false,
}) async {
  try {
    await http.post(
      Uri.parse(web.document.baseURI).removeFragment().resolve('api/notify'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'id': id, 'title': title, 'message': body}),
    );
  } on Object {
    // No add-on server – the notification is dropped.
  }
}

Future<void> requestNotificationPermission() async {}
