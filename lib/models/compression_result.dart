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
    required this.success,
    this.errorMessage,
  });

  double get reductionPercentage {
    if (originalSizeBytes == 0) return 0.0;
    final diff = originalSizeBytes - compressedSizeBytes;
    return (diff / originalSizeBytes * 100).clamp(0.0, 100.0);
  }

  String get originalSizeFormatted => formatBytes(originalSizeBytes);
  String get compressedSizeFormatted => formatBytes(compressedSizeBytes);
  String get targetSizeFormatted => formatBytes(targetSizeBytes);

  /// Consistent decimal file size formatting matching Android OS, WhatsApp, and upload portals
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1000 * 950) {
      final kb = bytes / 1000.0;
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = bytes / 1000000.0;
    return '${mb.toStringAsFixed(2)} MB';
  }
}
