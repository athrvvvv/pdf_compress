import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/compression_result.dart';
import '../services/file_service.dart';
import '../services/pdf_compressor_service.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  File? _selectedFile;
  int _originalSizeBytes = 0;
  int _pageCount = 0;

  // Target size configuration
  final TextEditingController _targetSizeController = TextEditingController(text: '500');
  String _targetUnit = 'KB'; // 'KB' or 'MB'
  int _selectedPreset = 500; // KB

  // Output filename configuration
  final TextEditingController _fileNameController = TextEditingController();
  bool _isFileNameEdited = false;

  // Compression state
  bool _isCompressing = false;
  double _compressionProgress = 0.0;
  String _progressStatus = '';
  CompressionResult? _lastResult;

  // Animation & Native Method Channel
  late AnimationController _animController;
  static const _shareChannel = MethodChannel('com.atharv.pdfcompressor/share_intent');

  final List<int> _presetSizesKb = [100, 200, 500, 1024, 2048];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Set up MethodChannel listener for incoming shared PDFs while app is running
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onPdfShared' && call.arguments is String) {
        _handleIncomingSharedFile(call.arguments as String);
      }
    });

    // Check if app was started directly with a shared PDF
    _shareChannel.invokeMethod<String>('getSharedPdf').then((path) {
      if (path != null && path.isNotEmpty) {
        _handleIncomingSharedFile(path);
      }
    });
  }

  void _updateDefaultFileName(String filePath) {
    if (!_isFileNameEdited) {
      final baseName = p.basenameWithoutExtension(filePath);
      // Remove any temporary prefix if present
      final cleanBase = baseName.replaceFirst(RegExp(r'^(picked|shared)_\d+_'), '');
      final targetKb = (_computedTargetSizeBytes / 1024).round();
      _fileNameController.text = '${cleanBase}_compressed_${targetKb}kb';
    }
  }

  Future<void> _handleIncomingSharedFile(String filePath) async {
    final file = await FileService.makePersistentInputFile(filePath);
    if (file != null && await file.exists()) {
      final size = await file.length();
      final pages = await PdfCompressorService.getPageCount(file.path);
      if (mounted) {
        setState(() {
          _selectedFile = file;
          _originalSizeBytes = size;
          _pageCount = pages;
          _lastResult = null;
          _isFileNameEdited = false;
          _updateDefaultFileName(filePath);
        });
        _animController.forward(from: 0.0);
        _showSnackBar('Imported PDF: ${p.basename(filePath)}');
      }
    }
  }

  @override
  void dispose() {
    _targetSizeController.dispose();
    _fileNameController.dispose();
    _animController.dispose();
    super.dispose();
  }

  int get _computedTargetSizeBytes {
    final val = double.tryParse(_targetSizeController.text.trim()) ?? 500;
    if (_targetUnit == 'MB') {
      return (val * 1024 * 1024).round();
    }
    return (val * 1024).round();
  }

  String get _currentOutputName {
    var name = _fileNameController.text.trim();
    if (name.isEmpty) {
      final base = _selectedFile != null
          ? p.basenameWithoutExtension(_selectedFile!.path).replaceFirst(RegExp(r'^(picked|shared)_\d+_'), '')
          : 'document';
      final targetKb = (_computedTargetSizeBytes / 1024).round();
      name = '${base}_compressed_${targetKb}kb';
    }
    return name.endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<void> _pickFile() async {
    final file = await FileService.pickPdfFile();
    if (file != null && mounted) {
      final size = await file.length();
      final pages = await PdfCompressorService.getPageCount(file.path);
      setState(() {
        _selectedFile = file;
        _originalSizeBytes = size;
        _pageCount = pages;
        _lastResult = null;
        _isFileNameEdited = false;
        _updateDefaultFileName(file.path);
      });
      _animController.forward(from: 0.0);
    }
  }

  Future<void> _startCompression() async {
    if (_selectedFile == null) {
      _showSnackBar('Please select a PDF file first.', isError: true);
      return;
    }

    if (!await _selectedFile!.exists()) {
      _showSnackBar('Selected file is not accessible. Please pick it again.', isError: true);
      return;
    }

    final targetBytes = _computedTargetSizeBytes;
    if (targetBytes <= 1024 * 5) {
      _showSnackBar('Please enter a target size of at least 10 KB.', isError: true);
      return;
    }

    setState(() {
      _isCompressing = true;
      _compressionProgress = 0.05;
      _progressStatus = 'Preparing document...';
      _lastResult = null;
    });

    final result = await PdfCompressorService.compressPdf(
      inputFile: _selectedFile!,
      targetSizeBytes: targetBytes,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _compressionProgress = progress;
            _progressStatus = status;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isCompressing = false;
        _lastResult = result;
      });

      if (result.success) {
        _showSnackBar(
          'Compressed to ${result.compressedSizeFormatted} (${result.reductionPercentage.toStringAsFixed(1)}% smaller)!',
        );
      } else {
        _showSnackBar(
          result.errorMessage ?? 'Compression failed. Please try again.',
          isError: true,
        );
      }
    }
  }

  Future<void> _saveToDownloads() async {
    if (_lastResult == null || !_lastResult!.success) {
      _showSnackBar('No compressed PDF available to save.', isError: true);
      return;
    }

    final savedPath = await FileService.savePdfToDownloads(
      _lastResult!.compressedFile,
      _currentOutputName,
    );

    if (savedPath != null) {
      _showSnackBar('Saved to Downloads: ${p.basename(savedPath)}');
    } else {
      _showSnackBar('Failed to save to Downloads folder.', isError: true);
    }
  }

  Future<void> _shareFile() async {
    if (_lastResult == null || !_lastResult!.success) {
      _showSnackBar('No compressed PDF available to share.', isError: true);
      return;
    }

    await FileService.sharePdf(
      _lastResult!.compressedFile.path,
      customName: _currentOutputName,
      text: 'Compressed PDF (${_lastResult!.compressedSizeFormatted})',
    );
  }

  Future<void> _openFile() async {
    if (_lastResult == null || !_lastResult!.success) {
      _showSnackBar('No compressed PDF available to preview.', isError: true);
      return;
    }

    final success = await FileService.openPdf(_lastResult!.compressedFile.path);
    if (!success) {
      await FileService.sharePdf(
        _lastResult!.compressedFile.path,
        customName: _currentOutputName,
      );
    }
  }

  void _showRenameDialog() {
    final textEdit = TextEditingController(
      text: p.basenameWithoutExtension(_currentOutputName),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: AppTheme.primaryColor, size: 22),
            SizedBox(width: 10),
            Text('Rename Output PDF'),
          ],
        ),
        content: TextField(
          controller: textEdit,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'File Name',
            suffixText: '.pdf',
            hintText: 'Enter custom file name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = textEdit.text.trim();
              if (newName.isNotEmpty) {
                setState(() {
                  _fileNameController.text = newName;
                  _isFileNameEdited = true;
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save Name'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.compress, color: AppTheme.primaryColor, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Smart PDF Compressor'),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFileSection(theme),
              const SizedBox(height: 16),
              _buildTargetSizeSection(theme),
              if (_selectedFile != null) ...[
                const SizedBox(height: 16),
                _buildFileNameSection(theme),
              ],
              const SizedBox(height: 24),
              _buildActionButton(theme),
              if (_isCompressing) ...[
                const SizedBox(height: 24),
                _buildProgressCard(theme),
              ],
              if (_lastResult != null && _lastResult!.success) ...[
                const SizedBox(height: 24),
                _buildResultCard(theme),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileSection(ThemeData theme) {
    if (_selectedFile == null) {
      return InkWell(
        onTap: _pickFile,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.picture_as_pdf_rounded,
                  size: 40,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select PDF Document',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap to browse files or share a PDF from any app',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final rawName = p.basename(_selectedFile!.path);
    final displayName = rawName.replaceFirst(RegExp(r'^(picked|shared)_\d+_'), '');
    final sizeStr = CompressionResult.formatBytes(_originalSizeBytes);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          sizeStr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_pageCount page${_pageCount > 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: 'Change File',
              onPressed: _isCompressing ? null : _pickFile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetSizeSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, size: 20, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Set Target Size',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quick Preset Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetSizesKb.map((kb) {
                final isSelected = _selectedPreset == kb;
                final label = kb >= 1024 ? '${kb ~/ 1024} MB' : '$kb KB';

                return ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedPreset = kb;
                        if (kb >= 1024) {
                          _targetSizeController.text = (kb / 1024).toStringAsFixed(0);
                          _targetUnit = 'MB';
                        } else {
                          _targetSizeController.text = kb.toString();
                          _targetUnit = 'KB';
                        }
                        if (_selectedFile != null) {
                          _updateDefaultFileName(_selectedFile!.path);
                        }
                      });
                    }
                  },
                  selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.primaryColor : Colors.grey.shade800,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Custom Size Input & Unit Dropdown
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _targetSizeController,
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      setState(() {
                        _selectedPreset = -1; // custom
                        if (_selectedFile != null) {
                          _updateDefaultFileName(_selectedFile!.path);
                        }
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Custom Target Size',
                      hintText: 'e.g. 500',
                      prefixIcon: Icon(Icons.data_usage_rounded, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _targetUnit,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'KB', child: Text('KB')),
                          DropdownMenuItem(value: 'MB', child: Text('MB')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _targetUnit = val;
                              _selectedPreset = -1;
                              if (_selectedFile != null) {
                                _updateDefaultFileName(_selectedFile!.path);
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileNameSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.drive_file_rename_outline_rounded, size: 20, color: AppTheme.primaryColor),
                    SizedBox(width: 8),
                    Text(
                      'Output File Name',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ],
                ),
                if (_isFileNameEdited)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _isFileNameEdited = false;
                        if (_selectedFile != null) {
                          _updateDefaultFileName(_selectedFile!.path);
                        }
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reset', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fileNameController,
              onChanged: (val) {
                _isFileNameEdited = true;
              },
              decoration: const InputDecoration(
                hintText: 'Enter output file name',
                prefixIcon: Icon(Icons.description_outlined, size: 20),
                suffixText: '.pdf',
                suffixStyle: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(ThemeData theme) {
    final targetStr = CompressionResult.formatBytes(_computedTargetSizeBytes);

    return ElevatedButton.icon(
      onPressed: (_selectedFile == null || _isCompressing) ? null : _startCompression,
      icon: _isCompressing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : const Icon(Icons.bolt_rounded, size: 22),
      label: Text(
        _isCompressing ? 'Compressing PDF...' : 'Compress to $targetStr',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildProgressCard(ThemeData theme) {
    return Card(
      color: AppTheme.primaryColor.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _progressStatus,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  '${(_compressionProgress * 100).toInt()}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _compressionProgress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    final res = _lastResult!;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.successColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: AppTheme.successColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Compression Complete!',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      Text(
                        'Processed in ${res.duration.inMilliseconds / 1000}s',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '-${res.reductionPercentage.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            // Custom Name Display & Inline Rename Trigger
            InkWell(
              onTap: _showRenameDialog,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, size: 18, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentOutputName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined, size: 16, color: AppTheme.primaryColor),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Original Size', res.originalSizeFormatted, Colors.grey.shade800),
                const Icon(Icons.arrow_forward_rounded, color: Colors.grey),
                _buildStatItem('New Size', res.compressedSizeFormatted, AppTheme.successColor, isBold: true),
                const Icon(Icons.flag_rounded, color: Colors.grey),
                _buildStatItem('Target', res.targetSizeFormatted, AppTheme.primaryColor),
              ],
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveToDownloads,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Save'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _shareFile,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _openFile,
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('Preview & Open PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, {bool isBold = false}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
