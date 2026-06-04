// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class ScreenTwo extends StatefulWidget {
  const ScreenTwo({super.key});

  @override
  State<ScreenTwo> createState() => _ScreenTwoState();
}

class _ScreenTwoState extends State<ScreenTwo> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _apiUrlController = TextEditingController();
  final _modelNameController = TextEditingController(); // Added 4th controller

  // Static hints for labelText
  final _defaultBaseUrl = "Base Url";
  final _defaultApiKey = "Api Key";
  final _defaultApiUrl = "Api Url";
  final _defaultModelName = "Model Name"; // Added 4th default hint

  String _statusText = '';
  bool _isSaving = false;
  String _selectedProvider = 'Ollama';
  final List<String> _providers = ['Ollama', 'OpenRouter'];

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _apiUrlController.dispose();
    _modelNameController.dispose(); // Dispose 4th controller
    super.dispose();
  }

  Future<void> _loadSavedConfig() async {
    final baseUrl = await _getBaseUrl();
    final apiKey = await _getApiKey();
    final apiUrl = await _getApiUrl();
    final modelName = await _getModelName(); // Load 4th variable
    final provider = await _getProvider();

    if (!mounted) return;
    setState(() {
      _selectedProvider = provider;
      if (baseUrl != "Base Url") {
        _baseUrlController.text = baseUrl;
      }
      if (apiKey != "Api Key") {
        _apiKeyController.text = apiKey;
      }
      if (apiUrl != "Api Url") {
        _apiUrlController.text = apiUrl;
      }
      if (modelName != "Model Name") {
        _modelNameController.text = modelName;
      }
    });
  }

  Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString("base_url");
    if (baseUrl != null && baseUrl.isNotEmpty) {
      return baseUrl;
    }
    return "Base Url";
  }

  Future<String> _getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString("api_key");
    if (apiKey != null && apiKey.isNotEmpty) {
      return apiKey;
    }
    return "Api Key";
  }

  Future<String> _getApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final apiUrl = prefs.getString("api_url");
    if (apiUrl != null && apiUrl.isNotEmpty) {
      return apiUrl;
    }
    return "Api Url";
  }

  // Helper method for 4th variable
  Future<String> _getModelName() async {
    final prefs = await SharedPreferences.getInstance();
    final modelName = prefs.getString("model_name");
    if (modelName != null && modelName.isNotEmpty) {
      return modelName;
    }
    return "Model Name";
  }

  Future<String> _getProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("llm_provider") ?? "Ollama";
  }

  void _onProviderChanged(String? provider) {
    if (provider == null) return;
    setState(() {
      _selectedProvider = provider;
      if (provider == 'Ollama') {
        _apiUrlController.text = 'http://127.0.0.1:11434';
        if (_modelNameController.text.isEmpty || _modelNameController.text == 'Model Name') {
          _modelNameController.text = 'llama3.2';
        }
      } else if (provider == 'OpenRouter') {
        _apiUrlController.text = 'https://openrouter.ai/api/v1';
        if (_modelNameController.text.isEmpty || _modelNameController.text == 'Model Name') {
          _modelNameController.text = 'openai/gpt-4o';
        }
      }
    });
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Fetch the currently saved values to check for modifications
      final savedBaseUrl = prefs.getString("base_url") ?? "";
      final savedApiKey = prefs.getString("api_key") ?? "";
      final savedApiUrl = prefs.getString("api_url") ?? "";
      final savedModelName = prefs.getString("model_name") ?? ""; // 4th saved value
      final savedProvider = prefs.getString("llm_provider") ?? "Ollama";

      final currentBaseUrl = _baseUrlController.text.trim();
      final currentApiKey = _apiKeyController.text.trim();
      final currentApiUrl = _apiUrlController.text.trim();
      final currentModelName = _modelNameController.text.trim(); // 4th current value
      final currentProvider = _selectedProvider;

      // CASE: If ALL values match what is already saved, don't write to disk
      if (savedBaseUrl == currentBaseUrl &&
          savedApiKey == currentApiKey &&
          savedApiUrl == currentApiUrl &&
          savedModelName == currentModelName &&
          savedProvider == currentProvider) {
        if (!mounted) return;
        setState(() {
          _statusText = 'No changes detected. Configuration is already up to date.';
        });
        return;
      }

      // If changes are detected, proceed with saving
      setState(() => _isSaving = true);

      // Save the values
      await prefs.setString("base_url", currentBaseUrl);
      await prefs.setString("api_key", currentApiKey);
      await prefs.setString("api_url", currentApiUrl);
      await prefs.setString("model_name", currentModelName); // Save 4th value
      await prefs.setString("llm_provider", currentProvider);

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _statusText = 'Configuration updated successfully.';
      });

      // Refresh the background UI text fields/labels
      await _loadSavedConfig();

      // POPUP DIALOG: Displays the variables with a close button
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text(
              'SAVED CONFIGURATION',
              style: TextStyle(
                color: Colors.cyanAccent,
                fontSize: 18,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Base URL:',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  currentBaseUrl,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 16),
                const Text(
                  'API Key:',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  currentApiKey,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 16),
                const Text(
                  'API URL:',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  currentApiUrl,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 16),
                // Added Model Name display section inside popup dialog
                const Text(
                  'Model Name:',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  currentModelName,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 16),
                const Text(
                  'LLM Provider:',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  currentProvider,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'CLOSE',
                  style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _statusText = 'Save failed: $e';
      });
    }
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      final baseUrl = _baseUrlController.text;

      setState(() => _statusText = 'Connecting...');

      HttpClient? httpClient;
      StreamSubscription? subscription;

      try {
        httpClient = HttpClient();
        httpClient.connectionTimeout = const Duration(seconds: 7);

        final request = await httpClient.getUrl(Uri.parse(baseUrl));

        request.headers.set('User-Agent', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        request.headers.set('Accept', 'text/plain, text/event-stream, application/json');

        final response = await request.close();

        if (response.statusCode == 200) {
          setState(() => _statusText = '');

          subscription = response
              .transform(utf8.decoder)
              .listen(
                (String chunk) {
              setState(() {
                if (chunk.trim().isNotEmpty) {
                  _statusText += '${chunk.trim()} ';
                }
              });
            },
            onError: (error) {
              setState(() => _statusText = 'Stream error: $error');
              subscription?.cancel();
              httpClient?.close();
            },
            onDone: () {
              subscription?.cancel();
              httpClient?.close();
            },
            cancelOnError: true,
          );
        } else {
          setState(() => _statusText = 'Server returned code: ${response.statusCode}');
          httpClient.close();
        }
      } on TimeoutException catch (_) {
        setState(() => _statusText = 'Connection timed out.');
        subscription?.cancel();
        httpClient?.close();
      } catch (e) {
        setState(() => _statusText = 'Connection failed: $e');
        subscription?.cancel();
        httpClient?.close();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 400,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'CONFIGURATION',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 20,
                    letterSpacing: 4,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: _providers.contains(_selectedProvider) ? _selectedProvider : _providers.first,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'LLM Provider',
                    labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 16),
                    border: const OutlineInputBorder(),
                  ),
                  items: _providers.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                  onChanged: _onProviderChanged,
                ),
                const SizedBox(height: 16),
                // 1. Base URL Field
                TextFormField(
                  controller: _baseUrlController,
                  decoration: InputDecoration(
                    labelText: _defaultBaseUrl,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a base URL';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // 2. API Key Field
                TextFormField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    labelText: _defaultApiKey,
                    border: const OutlineInputBorder(),
                  ),
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  validator: (value) {
                    if (_selectedProvider == 'OpenRouter' && (value == null || value.isEmpty)) {
                      return 'API key required for OpenRouter';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // 3. API URL Field
                TextFormField(
                  controller: _apiUrlController,
                  decoration: InputDecoration(
                    labelText: _defaultApiUrl,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter an API URL';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // 4. New Model Name Field Added Here
                TextFormField(
                  controller: _modelNameController,
                  decoration: InputDecoration(
                    labelText: _defaultModelName,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a model name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveConfig,
                        child: _isSaving
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                            : const Text('SAVE'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submit,
                        child: const Text('CONNECT'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _statusText,
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 22),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}