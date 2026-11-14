import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class BotStatus {
  final bool isActive;
  final String systemPrompt;
  final List<String> allowedChats;
  final String connection;
  final int sent;
  final int failed;
  final int pending;

  const BotStatus({
    required this.isActive,
    required this.systemPrompt,
    required this.allowedChats,
    this.connection = 'unknown',
    this.sent = 0,
    this.failed = 0,
    this.pending = 0,
  });

  factory BotStatus.fromJson(Map<String, dynamic> json) {
    final runtime = json['runtime'] as Map<String, dynamic>? ?? {};
    return BotStatus(
      isActive: json['isActive'] as bool,
      systemPrompt: json['systemPrompt'] as String,
      allowedChats: List<String>.from(json['allowedChats'] as List),
      connection: runtime['connection'] as String? ?? 'unknown',
      sent: runtime['sent'] as int? ?? 0,
      failed: runtime['failed'] as int? ?? 0,
      pending: runtime['pending'] as int? ?? 0,
    );
  }
}

class ApiService {
  final String baseUrl;
  final String apiKey;
  final http.Client _client;
  final Duration timeout;

  ApiService({
    String baseUrl = const String.fromEnvironment(
      'CONTROL_API_URL',
      defaultValue: 'http://127.0.0.1:3000',
    ),
    this.apiKey = const String.fromEnvironment('CONTROL_API_KEY'),
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  Future<Map<String, dynamic>> _request(
    String endpoint, [
    Map<String, dynamic>? body,
  ]) async {
    if (apiKey.trim().isEmpty) {
      throw const ApiException(
        'Set your server address and control API key to connect.',
      );
    }
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const ApiException('Enter a valid HTTP or HTTPS server address.');
    }
    try {
      final headers = {'Content-Type': 'application/json', 'x-api-key': apiKey};
      final target = Uri.parse('$baseUrl$endpoint');
      final response =
          await (body == null
                  ? _client.get(target, headers: headers)
                  : _client.post(
                      target,
                      headers: headers,
                      body: jsonEncode(body),
                    ))
              .timeout(timeout);
      if (response.statusCode == 401) {
        throw const ApiException('Access denied. Check your control API key.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected JSON object');
      }
      if (response.statusCode != 200) {
        throw ApiException(
          decoded['error'] is String
              ? decoded['error'] as String
              : 'Server request failed (${response.statusCode}).',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to respond. Refresh to check whether your change was saved.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the server. Check its address, network, and whether it is running.',
      );
    } on FormatException {
      throw const ApiException(
        'The server returned an invalid response. Check the server address.',
      );
    }
  }

  Future<BotStatus> fetchStatus() async {
    try {
      return BotStatus.fromJson(await _request('/status'));
    } on TypeError {
      throw const ApiException(
        'The server returned an incompatible status response.',
      );
    }
  }

  Future<bool> setActive(bool isActive) async {
    final data = await _request('/toggle', {'isActive': isActive});
    return data['isActive'] as bool;
  }

  Future<String> updatePrompt(String newPrompt) async {
    final data = await _request('/prompt', {'newPrompt': newPrompt});
    return data['systemPrompt'] as String;
  }

  Future<List<String>> addChat(String jid) async {
    final data = await _request('/chats/add', {'jid': jid});
    return List<String>.from(data['allowedChats'] as List);
  }

  Future<List<String>> removeChat(String jid) async {
    final data = await _request('/chats/remove', {'jid': jid});
    return List<String>.from(data['allowedChats'] as List);
  }

  void close() => _client.close();
}
