import 'dart:io';

class CompressionResult {
  final File originalFile;
  final File compressedFile;
  final int originalSizeBytes;
  final int compressedSizeBytes;
  final int targetSizeBytes;
  final int pageCount;
  final Duration duration;
  final bool success;
  final String? errorMessage;

  CompressionResult({
    required this.originalFile,
    required this.compressedFile,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    required this.targetSizeBytes,
    required this.pageCount,
    required this.duration,
    this.success = true,
    this.errorMessage,
  });

  double get reductionPercentage {
    if (originalSizeBytes <= 0) return 0.0;
    final diff = originalSizeBytes - compressedSizeBytes;
    return (diff / originalSizeBytes) * 100;
  }

  bool get isUnderTarget => compressedSizeBytes <= targetSizeBytes;

  String get originalSizeFormatted => formatBytes(originalSizeBytes);
  String get compressedSizeFormatted => formatBytes(compressedSizeBytes);
  String get targetSizeFormatted => formatBytes(targetSizeBytes);

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
