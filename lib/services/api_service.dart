import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static Future<String> _getBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('base_url') ?? 'http://localhost:8000';
  }

  static Future<List<String>> listDatasets() async {
    final base = await _getBackendUrl();
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$base/api/v1/datasets/list'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      return List<String>.from(data['datasets'] ?? []);
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> uploadDataset(List<int> bytes, String filename) async {
    final base = await _getBackendUrl();
    final client = HttpClient();
    try {
      final boundary = 'boundary${DateTime.now().millisecondsSinceEpoch}';
      final uri = Uri.parse('$base/api/v1/datasets/upload');
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');

      final header = utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="file"; filename="$filename"\r\nContent-Type: text/csv\r\n\r\n');
      final footer = utf8.encode('\r\n--$boundary--\r\n');
      final body = header + bytes + footer;
      req.contentLength = body.length;
      req.add(body);
      final resp = await req.close();
      final responseBody = await resp.transform(utf8.decoder).join();
      return jsonDecode(responseBody);
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> getMetadata(String datasetName) async {
    final base = await _getBackendUrl();
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$base/api/v1/datasets/$datasetName/metadata'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      return jsonDecode(body);
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> getChartData({
    required String dataset,
    required String chartType,
    required String columnX,
    String? columnY,
    String aggregation = 'count',
  }) async {
    final base = await _getBackendUrl();
    final client = HttpClient();
    try {
      final body = jsonEncode({
        'chart_type': chartType,
        'column_x': columnX,
        'column_y': columnY,
        'aggregation': aggregation,
      });
      final req = await client.postUrl(Uri.parse('$base/api/v1/datasets/$dataset/chart'));
      req.headers.set('Content-Type', 'application/json');
      req.write(body);
      final resp = await req.close();
      final responseBody = await resp.transform(utf8.decoder).join();
      return jsonDecode(responseBody);
    } finally {
      client.close();
    }
  }

  static Stream<String> chat({
    required String prompt,
    required String dataset,
    required String apiUrl,
    required String apiKey,
    required String model,
  }) async* {
    final base = await _getBackendUrl();
    final client = HttpClient();
    try {
      final boundary = 'boundary${DateTime.now().millisecondsSinceEpoch}';
      final uri = Uri.parse('$base/api/v1/chat');
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      req.headers.set('Accept', 'text/event-stream');

      final fields = {
        'prompt': prompt,
        'dataset': dataset,
        'api_url': apiUrl,
        'api_key': apiKey,
        'model': model,
      };

      final parts = <int>[];
      for (final entry in fields.entries) {
        parts.addAll(utf8.encode('--$boundary\r\n'));
        parts.addAll(utf8.encode('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n'));
        parts.addAll(utf8.encode('${entry.value}\r\n'));
      }
      parts.addAll(utf8.encode('--$boundary--\r\n'));

      req.contentLength = parts.length;
      req.add(parts);
      final resp = await req.close();

      await for (final chunk in resp.transform(utf8.decoder)) {
        for (final line in const LineSplitter().convert(chunk)) {
          if (line.startsWith('data: ')) {
            yield line.substring(6);
          }
        }
      }
    } finally {
      client.close();
    }
  }
}
