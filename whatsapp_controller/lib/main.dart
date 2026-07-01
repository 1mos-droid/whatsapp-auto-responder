import 'package:flutter/material.dart';
import 'api_service.dart';

void main() {
  runApp(const StealthApp());
}

class StealthApp extends StatelessWidget {
  const StealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stealth Responder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const CyberDashboard(),
    );
  }
}

// ponytail: replaced over-engineered CyberBackground animation and GlassCard with a simple, standard dashboard UI
class CyberDashboard extends StatefulWidget {
  const CyberDashboard({super.key});

  @override
  State<CyberDashboard> createState() => _CyberDashboardState();
}

class _CyberDashboardState extends State<CyberDashboard> {
  final ApiService _apiService = ApiService();
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _jidController = TextEditingController();
  
  bool _isLoading = true;
  bool _isActive = false;
  List<String> _allowedChats = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _jidController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    try {
      final status = await _apiService.fetchStatus();
      setState(() {
        _isActive = status.isActive;
        _promptController.text = status.systemPrompt;
        _allowedChats = status.allowedChats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleBot() async {
    setState(() => _isActive = !_isActive);
    try {
      final newState = await _apiService.toggleBot();
      setState(() => _isActive = newState);
      _showToast(_isActive ? 'Bot Enabled' : 'Bot Disabled');
    } catch (e) {
      setState(() => _isActive = !_isActive);
      _showToast('Network error');
    }
  }

  Future<void> _updatePrompt() async {
    final newPrompt = _promptController.text.trim();
    if (newPrompt.isEmpty) return;
    try {
      final success = await _apiService.updatePrompt(newPrompt);
      if (success) _showToast('Prompt updated');
    } catch (e) {
      _showToast('Failed to update prompt');
    }
  }

  Future<void> _addChat() async {
    final jid = _jidController.text.trim();
    if (jid.isEmpty) return;
    try {
      final newList = await _apiService.addChat(jid);
      setState(() {
        _allowedChats = newList;
        _jidController.clear();
      });
      _showToast('Chat added');
    } catch (e) {
      _showToast('Failed to add chat');
    }
  }

  Future<void> _removeChat(String jid) async {
    try {
      final newList = await _apiService.removeChat(jid);
      setState(() => _allowedChats = newList);
      _showToast('Chat removed');
    } catch (e) {
      _showToast('Failed to remove chat');
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stealth Responder Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _loadStatus,
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _errorMessage.isNotEmpty 
          ? _buildErrorState() 
          : _buildMainDashboard(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadStatus,
              child: const Text('Retry'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMainDashboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status Card
        // ponytail: replaced over-engineered pulse with standard SwitchListTile
        Card(
          child: SwitchListTile(
            title: const Text('Responder Active'),
            subtitle: Text(_isActive ? 'Monitoring chats' : 'Disabled'),
            value: _isActive,
            onChanged: (val) => _toggleBot(),
          ),
        ),
        const SizedBox(height: 16),

        // Whitelist Manager
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Allowed Chats Whitelist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _jidController,
                        decoration: const InputDecoration(
                          hintText: 'Enter JID (e.g. 1234@s.whatsapp.net)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _addChat,
                      child: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_allowedChats.isEmpty)
                  const Text('No chats whitelisted. Bot will not reply to anyone.')
                else
                  Wrap(
                    spacing: 8,
                    children: _allowedChats.map((jid) {
                      return Chip(
                        label: Text(jid),
                        onDeleted: () => _removeChat(jid),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Prompt Editor
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('System Prompt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: _promptController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'System directives...',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _updatePrompt,
                  child: const Text('Update Prompt'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
