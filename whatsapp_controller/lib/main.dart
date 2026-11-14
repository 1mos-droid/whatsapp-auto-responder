import 'dart:async';
import 'package:flutter/material.dart';
import 'api_service.dart';

void main() => runApp(const StealthApp());

class StealthApp extends StatelessWidget {
  final ApiService? apiService;
  const StealthApp({super.key, this.apiService});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Responder Control',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF38D9A9),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0D151C),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      useMaterial3: true,
    ),
    home: CyberDashboard(apiService: apiService),
  );
}

class CyberDashboard extends StatefulWidget {
  final ApiService? apiService;
  const CyberDashboard({super.key, this.apiService});

  @override
  State<CyberDashboard> createState() => _CyberDashboardState();
}

class _CyberDashboardState extends State<CyberDashboard> {
  late ApiService _api;
  late bool _ownsApi;
  final _prompt = TextEditingController();
  final _jid = TextEditingController();
  BotStatus? _status;
  String _savedPrompt = '';
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _settingsOpen = false;
  Timer? _poll;

  bool get _locked => _loading || _busy || _settingsOpen;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService();
    _ownsApi = widget.apiService == null;
    _prompt.addListener(_promptChanged);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_locked) _load(background: true);
    });
  }

  void _promptChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _prompt.removeListener(_promptChanged);
    _prompt.dispose();
    _jid.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  Future<void> _load({bool background = false}) async {
    if (!mounted || _busy || _settingsOpen) return;
    setState(() {
      _loading = true;
      if (!background) _error = null;
    });
    try {
      final status = await _api.fetchStatus();
      if (!mounted) return;
      final dirty = _prompt.text != _savedPrompt;
      setState(() {
        _status = status;
        if (!dirty) _prompt.text = status.systemPrompt;
        _savedPrompt = status.systemPrompt;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _change(Future<void> Function() action, String success) async {
    if (_locked) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _toast(success);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
        _toast(error.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load(background: true);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _settings() async {
    if (_locked) return;
    setState(() => _settingsOpen = true);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) =>
          _ConnectionDialog(baseUrl: _api.baseUrl, apiKey: _api.apiKey),
    );
    if (!mounted) return;
    setState(() => _settingsOpen = false);
    if (result == null) return;
    if (_ownsApi) _api.close();
    _api = ApiService(baseUrl: result.$1, apiKey: result.$2);
    _ownsApi = true;
    setState(() {
      _status = null;
      _savedPrompt = '';
      _prompt.clear();
    });
    await _load();
  }

  Widget _card(String title, String subtitle, Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );

  String get _connectionLabel => switch (_status?.connection) {
    'open' => 'WhatsApp connected',
    'awaiting_qr' => 'Scan the QR code in the server terminal',
    'logged_out' => 'WhatsApp logged out · relink on the server',
    'action_required' => 'WhatsApp session needs attention on the server',
    'connecting' || 'reconnecting' => 'Connecting to WhatsApp…',
    _ => 'WhatsApp connection unavailable',
  };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Responder Control'),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _locked ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Connection settings',
            onPressed: _locked ? null : _settings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            if (!_locked) await _load();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Your conversations. Your rules.',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Control who receives replies and how your assistant responds.',
                      ),
                      const SizedBox(height: 24),
                      if (_loading || _busy)
                        const LinearProgressIndicator(
                          semanticsLabel: 'Contacting server',
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        MaterialBanner(
                          content: Text(_error!),
                          leading: const Icon(Icons.cloud_off_outlined),
                          actions: [
                            TextButton(
                              onPressed: _locked ? null : _load,
                              child: const Text('Retry'),
                            ),
                            TextButton(
                              onPressed: _locked ? null : _settings,
                              child: const Text('Connection settings'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (status != null) ...[
                        _card(
                          'Responder',
                          _connectionLabel,
                          Column(
                            children: [
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  status.isActive
                                      ? 'Replies enabled'
                                      : 'Replies paused',
                                ),
                                subtitle: const Text(
                                  'Only allowed chats receive replies while WhatsApp is connected.',
                                ),
                                value: status.isActive,
                                onChanged: _locked || _error != null
                                    ? null
                                    : (value) => _change(
                                        () async {
                                          await _api.setActive(value);
                                        },
                                        value
                                            ? 'Replies enabled'
                                            : 'Replies paused',
                                      ),
                              ),
                              const Divider(),
                              Wrap(
                                spacing: 24,
                                runSpacing: 8,
                                children: [
                                  Text('${status.sent} sent'),
                                  Text('${status.pending} pending'),
                                  Text('${status.failed} failed'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _card(
                          'Allowed chats',
                          'Add a full WhatsApp chat ID. An empty list means nobody receives automated replies.',
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _jid,
                                autocorrect: false,
                                enabled: !_locked,
                                decoration: const InputDecoration(
                                  labelText: 'WhatsApp chat ID',
                                  hintText: '15551234567@s.whatsapp.net',
                                  helperText:
                                      'Contacts: @s.whatsapp.net or @lid · Groups: @g.us',
                                  helperMaxLines: 2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  onPressed: _locked
                                      ? null
                                      : () {
                                          final jid = _jid.text.trim();
                                          if (!RegExp(
                                            r'^(?:[1-9]\d{4,19}@s\.whatsapp\.net|[1-9]\d{4,19}(?:-\d{1,20})?@g\.us|[1-9]\d{4,19}@lid)$',
                                          ).hasMatch(jid)) {
                                            _toast(
                                              'Enter a valid WhatsApp chat ID.',
                                            );
                                            return;
                                          }
                                          _change(() async {
                                            await _api.addChat(jid);
                                            if (mounted) _jid.clear();
                                          }, 'Chat added');
                                        },
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add chat'),
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (status.allowedChats.isEmpty)
                                const Text('No chats allowed yet.'),
                              for (final jid in status.allowedChats)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.chat_bubble_outline,
                                  ),
                                  title: Text(jid),
                                  trailing: IconButton(
                                    tooltip: 'Remove $jid',
                                    onPressed: _locked
                                        ? null
                                        : () => _change(() async {
                                            await _api.removeChat(jid);
                                          }, 'Chat removed'),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _card(
                          'Reply instructions',
                          'Describe the tone, purpose, and boundaries for your assistant.',
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _prompt,
                                enabled: !_busy,
                                minLines: 4,
                                maxLines: 12,
                                maxLength: 8000,
                                decoration: const InputDecoration(
                                  labelText: 'System prompt',
                                  alignLabelWithHint: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  onPressed:
                                      _locked ||
                                          _prompt.text.trim().isEmpty ||
                                          _prompt.text == _savedPrompt
                                      ? null
                                      : () {
                                          final prompt = _prompt.text.trim();
                                          _change(() async {
                                            final saved = await _api
                                                .updatePrompt(prompt);
                                            if (mounted) {
                                              setState(() {
                                                _savedPrompt = saved;
                                                _prompt.text = saved;
                                              });
                                            }
                                          }, 'Instructions saved');
                                        },
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(
                                    _prompt.text == _savedPrompt
                                        ? 'Instructions saved'
                                        : 'Save instructions',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionDialog extends StatefulWidget {
  final String baseUrl;
  final String apiKey;
  const _ConnectionDialog({required this.baseUrl, required this.apiKey});
  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late final TextEditingController address;
  late final TextEditingController key;
  @override
  void initState() {
    super.initState();
    address = TextEditingController(text: widget.baseUrl);
    key = TextEditingController(text: widget.apiKey);
  }

  @override
  void dispose() {
    address.dispose();
    key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect to your server'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use the address reachable from this device. Connection settings entered here last for this session.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: 'https://responder.example.com',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Control API key'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (address.text.trim(), key.text.trim())),
        child: const Text('Connect'),
      ),
    ],
  );
}
