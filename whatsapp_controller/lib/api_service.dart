import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// --- DATA MODEL ---

class BotStatus {
  final bool isActive;
  final String systemPrompt;
  final List<String> allowedChats;

  BotStatus({
    required this.isActive,
    required this.systemPrompt,
    required this.allowedChats,
  });

  /// Factory to create a BotStatus from JSON map
  factory BotStatus.fromJson(Map<String, dynamic> json) {
    return BotStatus(
      isActive: json['isActive'] ?? false,
      systemPrompt: json['systemPrompt'] ?? '',
      allowedChats: List<String>.from(json['allowedChats'] ?? []),
    );
  }
}

/// --- API SERVICE ---

class ApiService {
  /// NETWORK CONFIGURATION
  /// Your current machine's local IP is: 192.168.100.9
  final String baseUrl = "http://192.168.100.9:3000";

  /// API KEY for authentication.
  /// Make sure this matches the CONTROL_API_KEY in the server's .env file.
  static const String apiKey = "whatsapp_control_secret_token_abc123";

  /// Standard headers for POST/PUT requests
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'x-api-key': apiKey,
  };

  /// Headers for GET or requests without JSON body
  Map<String, String> get _getHeaders => {
    'x-api-key': apiKey,
  };

  /// GET /status: Fetches the current state of the WhatsApp bot
  Future<BotStatus> fetchStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/status'),
        headers: _getHeaders,
      );

      if (response.statusCode == 200) {
        return BotStatus.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Server returned status code: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Cannot connect to the local server. Is it running?');
    } catch (e) {
      throw Exception('Failed to fetch bot status: $e');
    }
  }

  /// POST /toggle: Flips the bot's active status
  /// Returns the new 'isActive' state
  Future<bool> toggleBot() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/toggle'),
        headers: _getHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['isActive'] ?? false;
      } else {
        throw Exception('Toggle failed with status: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Cannot connect to the local server.');
    } catch (e) {
      throw Exception('Failed to toggle bot: $e');
    }
  }

  /// POST /prompt: Updates the bot's system instructions
  /// Returns true if the update was successful
  Future<bool> updatePrompt(String newPrompt) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/prompt'),
        headers: _headers,
        body: jsonEncode({'newPrompt': newPrompt}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      } else {
        throw Exception('Prompt update failed: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Cannot connect to the local server.');
    } catch (e) {
      throw Exception('Failed to update prompt: $e');
    }
  }

  /// POST /chats/add: Adds a JID to the whitelist
  Future<List<String>> addChat(String jid) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chats/add'),
        headers: _headers,
        body: jsonEncode({'jid': jid}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<String>.from(data['allowedChats'] ?? []);
      } else {
        throw Exception('Failed to add chat: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Cannot connect to the local server.');
    } catch (e) {
      throw Exception('Failed to add chat: $e');
    }
  }

  /// POST /chats/remove: Removes a JID from the whitelist
  Future<List<String>> removeChat(String jid) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chats/remove'),
        headers: _headers,
        body: jsonEncode({'jid': jid}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<String>.from(data['allowedChats'] ?? []);
      } else {
        throw Exception('Failed to remove chat: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Cannot connect to the local server.');
    } catch (e) {
      throw Exception('Failed to remove chat: $e');
    }
  }
}
