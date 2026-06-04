import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/file_store.dart';
import '../widgets/chart_card.dart';

class _ChatMessage {
  final String text;
  final bool isUser;
  final Map<String, dynamic>? chartData;

  _ChatMessage({required this.text, required this.isUser, this.chartData});
}

class ScreenOne extends StatefulWidget {
  const ScreenOne({super.key});

  @override
  State<ScreenOne> createState() => _ScreenOneState();
}

class _ScreenOneState extends State<ScreenOne> {
  final List<_ChatMessage> _messages = [];
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = false;
  String _selectedDataset = '';
  List<String> _datasets = [];
  String _apiUrl = '';
  String _apiKey = '';
  String _modelName = '';
  StreamSubscription? _subscription;
  List<String> _recentFiles = [];
  int? _textMsgIdx;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _refreshDatasets();
    _loadRecentFiles();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiUrl = prefs.getString('api_url') ?? '';
      _apiKey = prefs.getString('api_key') ?? '';
      _modelName = prefs.getString('model_name') ?? '';
    });
  }

  Future<void> _loadRecentFiles() async {
    final files = await FileStore.getRecentDatasets();
    if (!mounted) return;
    setState(() => _recentFiles = files);
  }

  Future<void> _refreshDatasets() async {
    try {
      final list = await ApiService.listDatasets();
      if (!mounted) return;
      setState(() {
        _datasets = list;
        if (_selectedDataset.isNotEmpty && !list.contains(_selectedDataset)) {
          _selectedDataset = '';
        }
        if (_selectedDataset.isEmpty && list.isNotEmpty) {
          _selectedDataset = list.first;
        }
      });
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    await _loadConfig();
    if (_apiUrl.isEmpty || _apiKey.isEmpty || _modelName.isEmpty) {
      setState(() {
        _messages.add(_ChatMessage(
          text: 'Configure api_url, api_key, and model_name in Settings tab first.',
          isUser: false,
        ));
      });
      return;
    }
    if (_selectedDataset.isEmpty) {
      setState(() {
        _messages.add(_ChatMessage(
          text: 'No dataset selected. Upload a CSV in the Data Lab tab first.',
          isUser: false,
        ));
      });
      return;
    }

    await FileStore.addDataset(_selectedDataset);
    _loadRecentFiles();

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _messages.add(_ChatMessage(text: '', isUser: false));
      _textMsgIdx = _messages.length - 1;
      _isLoading = true;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      final stream = ApiService.chat(
        prompt: text,
        dataset: _selectedDataset,
        apiUrl: _apiUrl,
        apiKey: _apiKey,
        model: _modelName,
      );

      _subscription = stream.listen(
        (String data) {
          if (!mounted) return;
          try {
            final parsed = jsonDecode(data) as Map<String, dynamic>;
            final type = parsed['type'] as String?;
            final content = parsed['content'];

            if (type == 'result') {
              final chunk = content as String? ?? '';
              final chartPattern = RegExp(r'<!--CHART:(.*?)-->');
              final match = chartPattern.firstMatch(chunk);

              if (match != null) {
                final before = chunk.substring(0, match.start);
                final chartJson = match.group(1)!;
                final chartContent = jsonDecode(chartJson) as Map<String, dynamic>;
                final after = chunk.substring(match.end);

                setState(() {
                  if (before.isNotEmpty) {
                    final idx = _textMsgIdx ?? (_messages.length - 1);
                    _messages[idx] = _ChatMessage(
                      text: _messages[idx].text + before,
                      isUser: false,
                      chartData: _messages[idx].chartData,
                    );
                  }
                  _messages.add(_ChatMessage(
                    text: after,
                    isUser: false,
                    chartData: chartContent,
                  ));
                  _textMsgIdx = _messages.length - 1;
                });
                _scrollToBottom();
              } else {
                setState(() {
                  final idx = _textMsgIdx ?? (_messages.length - 1);
                  _messages[idx] = _ChatMessage(
                    text: _messages[idx].text + chunk,
                    isUser: false,
                    chartData: _messages[idx].chartData,
                  );
                });
                _scrollToBottom();
              }
            } else if (type == 'error') {
              final msg = content as String? ?? 'Unknown error';
              setState(() {
                final idx = _textMsgIdx ?? (_messages.length - 1);
                _messages[idx] = _ChatMessage(
                  text: '⚠️ Error:\n$msg',
                  isUser: false,
                  chartData: _messages[idx].chartData,
                );
                _isLoading = false;
              });
              _scrollToBottom();
            } else if (type == 'thinking') {
              setState(() {
                final idx = _textMsgIdx ?? (_messages.length - 1);
                _messages[idx] = _ChatMessage(
                  text: '🤔 ${content ?? ''}',
                  isUser: false,
                  chartData: _messages[idx].chartData,
                );
              });
            }
          } catch (_) {}
        },
        onError: (error) {
          _finalizeMessage('Stream error: $error');
        },
        onDone: () {
          _finalizeLastMessage();
          _cleanup();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _finalizeMessage('Request failed: $e');
      _cleanup();
    }
  }

  void _finalizeLastMessage() {
    if (!mounted) return;
    final idx = _textMsgIdx ?? (_messages.length - 1);
    if (idx >= 0 && _messages[idx].text.isEmpty && _messages[idx].chartData == null) {
      setState(() {
        _messages[idx] = _ChatMessage(text: '(empty response)', isUser: false);
        _isLoading = false;
      });
    }
  }

  void _finalizeMessage(String msg) {
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(text: msg, isUser: false));
      _isLoading = false;
    });
    _scrollToBottom();
  }

  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveChat() async {
    if (_messages.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('# DataAnalice Chat — ${DateTime.now().toIso8601String()}');
    buffer.writeln('---\n');

    for (final msg in _messages) {
      final role = msg.isUser ? '**You**' : '**Assistant**';
      final text = msg.text.isNotEmpty ? '\n${msg.text}\n' : '';
      final chart = msg.chartData != null ? '\n_[Chart: ${msg.chartData!['chart_type'] ?? 'chart'}]_\n' : '';
      buffer.writeln('$role$text$chart\n');
    }

    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save Chat',
        fileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.md',
        type: FileType.any,
      );
      if (path != null) {
        await File(path).writeAsString(buffer.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat saved'), backgroundColor: Colors.cyanAccent, duration: Duration(seconds: 2)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top bar with dataset selector + recent files
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          decoration: const BoxDecoration(
            color: Color(0xFF0D0D0D),
            border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A))),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedDataset.isNotEmpty && _datasets.contains(_selectedDataset)
                          ? _selectedDataset
                          : null,
                      dropdownColor: const Color(0xFF1A1A1A),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Active Dataset',
                        labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.cyanAccent),
                        ),
                      ),
                      items: _datasets.map((name) {
                        return DropdownMenuItem(value: name, child: Text(name));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedDataset = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: IconButton(
                      icon: const Icon(Icons.refresh, size: 20, color: Colors.cyanAccent),
                      onPressed: _refreshDatasets,
                    ),
                  ),
                ],
              ),
              if (_recentFiles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    height: 28,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemCount: _recentFiles.length,
                      itemBuilder: (context, index) {
                        final file = _recentFiles[index];
                        final isActive = file == _selectedDataset;
                        return ActionChip(
                          label: Text(file, style: TextStyle(fontSize: 11, color: isActive ? Colors.black : Colors.cyanAccent)),
                          backgroundColor: isActive ? Colors.cyanAccent : const Color(0xFF1A1A1A),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() => _selectedDataset = file);
                          },
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${_messages.length} message${_messages.length == 1 ? '' : 's'}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _isLoading ? null : () => _saveChat(),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.save_alt, size: 16, color: Colors.cyanAccent),
                                  SizedBox(width: 4),
                                  Text('Save', style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _isLoading ? null : () => setState(() => _messages.clear()),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                  SizedBox(width: 4),
                                  Text('Clear', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isStreaming = index == _messages.length - 1 && _isLoading;
                          return _MessageBubble(key: ValueKey('msg_$index'), message: msg, isStreaming: isStreaming);
                        },
                      ),
                    ),
                  ],
                ),
        ),
        // Input bar
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D0D0D),
            border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Ask about your data...',
                    hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              _isLoading
                  ? CircleAvatar(
                      backgroundColor: Colors.redAccent,
                      radius: 22,
                      child: IconButton(
                        icon: const Icon(Icons.stop, color: Colors.white),
                        onPressed: _cleanup,
                        iconSize: 20,
                      ),
                    )
                  : CircleAvatar(
                      backgroundColor: Colors.cyanAccent,
                      radius: 22,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_upward, color: Colors.black),
                        onPressed: _sendMessage,
                        iconSize: 20,
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 64, color: Color(0x4D80CBC4)),
            const SizedBox(height: 16),
            Text(
              'Chat with DataAnalice',
              style: TextStyle(
                color: Colors.cyanAccent.withValues(alpha: 0.5),
                fontSize: 20,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedDataset.isNotEmpty
                  ? 'Dataset: $_selectedDataset'
                  : 'Upload a CSV in Data Lab tab',
              style: TextStyle(
                color: Colors.grey.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
            if (_recentFiles.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'RECENT FILES',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              ..._recentFiles.take(5).map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: InkWell(
                  onTap: () => setState(() => _selectedDataset = f),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.description, size: 14, color: Colors.cyanAccent),
                      const SizedBox(width: 6),
                      Text(f, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final bool isStreaming;

  const _MessageBubble({super.key, required this.message, this.isStreaming = false});

  @override
  Widget build(BuildContext context) {
    final hasText = message.text.isNotEmpty;
    final hasChart = message.chartData != null;

    if (!hasText && !hasChart) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (!message.isUser) ...[
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.cyanAccent.withValues(alpha: 0.2),
                child: const Text('A', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(width: 10),
            ],
            if (isStreaming)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                ),
                child: const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.cyanAccent.withValues(alpha: 0.2),
              child: const Text('A', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasText)
                  Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: message.isUser ? Colors.cyanAccent.withValues(alpha: 0.15) : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(hasChart ? 4 : (message.isUser ? 18 : 4)),
                        bottomRight: Radius.circular(hasChart ? 4 : (message.isUser ? 4 : 18)),
                      ),
                    ),
                    child: message.isUser
                        ? Text(
                            message.text,
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 15, height: 1.4),
                          )
                        : MarkdownBody(
                            data: message.text,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                              h1: const TextStyle(color: Colors.cyanAccent, fontSize: 20, fontWeight: FontWeight.bold),
                              h2: const TextStyle(color: Colors.cyanAccent, fontSize: 17, fontWeight: FontWeight.bold),
                              h3: const TextStyle(color: Colors.cyanAccent, fontSize: 15, fontWeight: FontWeight.bold),
                              strong: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                              code: const TextStyle(color: Colors.lightGreenAccent, fontSize: 13, fontFamily: 'monospace'),
                              codeblockDecoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                              blockquoteDecoration: BoxDecoration(
                                border: Border(left: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.5), width: 3)),
                                color: Colors.white.withValues(alpha: 0.03),
                              ),
                              listBullet: const TextStyle(color: Colors.cyanAccent),
                              tableHead: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                              tableBody: const TextStyle(color: Colors.white),
                              tableBorder: TableBorder.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            shrinkWrap: true,
                            softLineBreak: true,
                          ),
                  ),
                if (hasChart)
                  Padding(
                    padding: EdgeInsets.only(top: hasText ? 6 : 0),
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ChartCard(data: message.chartData!),
                    ),
                  ),
              ],
            ),
          ),
          if (message.isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }
}
