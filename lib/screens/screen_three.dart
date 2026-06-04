import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/file_store.dart';

class ScreenThree extends StatefulWidget {
  const ScreenThree({super.key});

  @override
  State<ScreenThree> createState() => _ScreenThreeState();
}

class _ScreenThreeState extends State<ScreenThree> {
  bool _isUploading = false;
  bool _isLoadingMeta = false;
  Map<String, dynamic>? _metadata;
  List<String> _datasets = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _refreshDatasets();
  }

  Future<void> _refreshDatasets() async {
    try {
      final list = await ApiService.listDatasets();
      if (!mounted) return;
      setState(() => _datasets = list);
    } catch (_) {}
  }

  Future<void> _pickAndUpload() async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;

      List<int> bytes;

      if (kIsWeb) {
        if (file.bytes == null) throw Exception("Could not read file data.");
        bytes = file.bytes!;
      } else {
        if (file.path == null) throw Exception("File path is missing.");
        final ioFile = File(file.path!);
        bytes = await ioFile.readAsBytes();
      }

      await _uploadBytes(bytes, file.name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Picker Error: ${e.toString()}";
      });
    }
  }

  Future<void> _uploadBytes(List<int> bytes, String filename) async {
    setState(() {
      _isUploading = true;
      _metadata = null;
    });

    try {
      final response = await ApiService.uploadDataset(bytes, filename);
      if (!mounted) return;
      await FileStore.addDataset(filename.replaceAll('.csv', ''));
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _metadata = response['metadata'];
      });
      await _refreshDatasets();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _metadata = {'error': 'Upload failed: $e'};
      });
    }
  }

  Future<void> _loadMetadata(String name) async {
    setState(() {
      _isLoadingMeta = true;
      _metadata = null;
    });
    try {
      final meta = await ApiService.getMetadata(name);
      if (!mounted) return;
      await FileStore.addDataset(name);
      setState(() {
        _isLoadingMeta = false;
        _metadata = meta;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMeta = false;
        _metadata = {'error': 'Failed to load metadata: $e'};
      });
    }
  }

  // -------------------------------------------------------
  // Build
  // -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'DATA LAB',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 20,
              letterSpacing: 4,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Upload section
          _buildUploadSection(),
          const SizedBox(height: 20),

          // Existing datasets list
          if (_datasets.isNotEmpty) ...[
            const Text(
              'AVAILABLE DATASETS',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            ..._datasets.map((name) => Card(
              color: const Color(0xFF1A1A1A),
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: const Icon(Icons.description, color: Colors.cyanAccent),
                title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () => _loadMetadata(name),
              ),
            )),
            const SizedBox(height: 16),
          ],

          // Metadata
          if (_isLoadingMeta)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )),

          if (_metadata != null && !_isLoadingMeta) ...[
            const Text(
              'DATASET PROFILE',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            _buildMetadataView(),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 48, color: Colors.cyanAccent),
          const SizedBox(height: 12),
          const Text(
            'Upload a CSV dataset',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Only .csv files are accepted',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            child: ElevatedButton.icon(
              onPressed: _isUploading ? null : _pickAndUpload,
              icon: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.folder_open),
              label: Text(_isUploading ? 'Uploading...' : 'Pick CSV File'),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetadataView() {
    final meta = _metadata!;

    if (meta.containsKey('error')) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Text(
          meta['error'] as String,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }

    final totalRows = meta['total_rows'] ?? '?';
    final totalCols = meta['total_columns'] ?? '?';
    final dtypes = Map<String, dynamic>.from(meta['dtypes'] ?? {});
    final nullCounts = Map<String, dynamic>.from(meta['null_counts'] ?? {});
    final uniqueCounts = Map<String, dynamic>.from(meta['unique_counts'] ?? {});
    final memoryBytes = meta['memory_usage_bytes'] as int? ?? 0;
    final numericStats = Map<String, dynamic>.from(meta['numeric_stats'] ?? {});
    final catTop = Map<String, dynamic>.from(meta['categorical_top'] ?? {});
    final corrMatrix = meta['correlation_matrix'] as Map<String, dynamic>?;
    final sampleRows = List<Map<String, dynamic>>.from(meta['sample_rows'] ?? []);
    final profileSummary = meta['profile_summary'] as String? ?? '';
    final memoryMb = (memoryBytes / (1024 * 1024)).toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _StatCard(label: 'Rows', value: '$totalRows', icon: Icons.table_rows)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(label: 'Columns', value: '$totalCols', icon: Icons.view_column)),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Memory: ${memoryMb}MB',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ),
        const SizedBox(height: 16),
        _AccordionSection(
          title: 'Column Details',
          initiallyExpanded: true,
          child: Column(
            children: dtypes.entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          '${uniqueCounts[e.key] ?? '?'} unique',
                          style: const TextStyle(color: Colors.grey, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('${e.value}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${nullCounts[e.key] ?? 0} nulls',
                    style: TextStyle(
                      color: (nullCounts[e.key] as num? ?? 0) > 0 ? Colors.orangeAccent : Colors.grey,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
        if (numericStats.isNotEmpty)
          _AccordionSection(
            title: 'Numeric Statistics',
            child: Column(
              children: numericStats.entries.map((e) {
                final col = e.key;
                final stats = Map<String, dynamic>.from(e.value ?? {});
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(col, style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: stats.entries.map((s) => Text(
                            '${s.key}: ${_fmtNum(s.value)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        if (catTop.isNotEmpty)
          _AccordionSection(
            title: 'Categorical Top Values',
            child: Column(
              children: catTop.entries.map((e) {
                final col = e.key;
                final top = Map<String, dynamic>.from(e.value ?? {});
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(col, style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        ...top.entries.take(5).map((v) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Row(
                            children: [
                              Expanded(child: Text(v.key.toString(), style: const TextStyle(color: Colors.white70, fontSize: 11))),
                              Text(v.value.toString(), style: const TextStyle(color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        if (corrMatrix != null)
          _AccordionSection(
            title: 'Correlation Matrix',
            child: _buildCorrelationMatrix(corrMatrix),
          ),
        if (sampleRows.isNotEmpty)
          _AccordionSection(
            title: 'Sample Rows (${sampleRows.length})',
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFF2A2A2A)),
                dataRowColor: WidgetStateProperty.all(const Color(0xFF1A1A1A)),
                columnSpacing: 16,
                columns: sampleRows.first.keys.map((c) => DataColumn(
                  label: Text(c, style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                )).toList(),
                rows: sampleRows.map((row) => DataRow(
                  cells: row.values.map((v) => DataCell(
                    Text('$v', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  )).toList(),
                )).toList(),
              ),
            ),
          ),
        if (profileSummary.isNotEmpty)
          _AccordionSection(
            title: 'Profile Summary',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
              ),
              child: SelectableText(
                profileSummary,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCorrelationMatrix(Map<String, dynamic> corr) {
    final cols = List<String>.from(corr['columns'] ?? []);
    final vals = List<List<dynamic>>.from(corr['values'] ?? []);
    if (cols.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF2A2A2A)),
        dataRowColor: WidgetStateProperty.all(const Color(0xFF1A1A1A)),
        columnSpacing: 12,
        columns: [const DataColumn(label: Text('', style: TextStyle(fontSize: 0))), ...cols.map((c) => DataColumn(
          label: Text(c, style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
        ))],
        rows: List.generate(cols.length, (i) => DataRow(
          cells: [DataCell(Text(cols[i], style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold))), ...vals[i].map((v) {
            final fv = (v as num).toDouble();
            final color = fv.abs() > 0.7 ? Colors.greenAccent : fv.abs() > 0.4 ? Colors.yellowAccent : Colors.white70;
            return DataCell(Text(
              fv.toStringAsFixed(2),
              style: TextStyle(color: color, fontSize: 10),
            ));
          })],
        )),
      ),
    );
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '?';
    if (v is num) {
      if (v == v.roundToDouble()) return v.toInt().toString();
      return v.toStringAsFixed(3);
    }
    return v.toString();
  }

}

class _AccordionSection extends StatefulWidget {
  final String title;
  final bool initiallyExpanded;
  final Widget child;

  const _AccordionSection({
    required this.title,
    this.initiallyExpanded = false,
    required this.child,
  });

  @override
  State<_AccordionSection> createState() => _AccordionSectionState();
}

class _AccordionSectionState extends State<_AccordionSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: _expanded
                  ? const BorderRadius.vertical(top: Radius.circular(8))
                  : BorderRadius.circular(8),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more, color: Colors.grey, size: 20),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              border: Border(
                left: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.2)),
                right: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.2)),
                bottom: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.2)),
              ),
            ),
            child: widget.child,
          ),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(color: Colors.cyanAccent, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}
