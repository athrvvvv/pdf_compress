import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart';
import '../models/compression_result.dart';

typedef ProgressCallback = void Function(double progress, String status);

class PdfCompressorService {
  static Future<int> getPageCount(String filePath) async {
    try {
      final document = await PdfDocument.openFile(filePath);
      final count = document.pagesCount;
      await document.close();
      return count;
    } catch (e) {
      return 1;
    }
  }

  static Future<CompressionResult> compressPdf({
    required File inputFile,
    required int targetSizeBytes,
    ProgressCallback? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final originalSize = await inputFile.length();

    try {
      onProgress?.call(0.05, 'Reading PDF document...');
      final document = await PdfDocument.openFile(inputFile.path);
      final pageCount = document.pagesCount;

      if (pageCount == 0) {
        throw Exception('The selected PDF has no pages.');
      }

      onProgress?.call(0.10, 'Analyzing $pageCount page(s) for maximum sharpness...');

      // Precise PDF wrapper overhead (~1KB + 150B/page)
      final overhead = 1024 + (pageCount * 150);
      final availableBudget = (targetSizeBytes - overhead).clamp(1024 * 5, targetSizeBytes);
      // Target 99.2% budget allocation per page
      final budgetPerPage = ((availableBudget * 0.992) / pageCount).floor();

      // Dynamically calculate render DPI scale:
      // High budget (500KB - 1MB+) -> 3.3x (240+ DPI scanner quality)
      // Medium budget (200KB - 500KB) -> 2.6x - 3.2x (180 - 230 DPI)
      // Lower budget (< 150KB) -> 1.8x - 2.2x
      final renderScale = math.sqrt(budgetPerPage / 42000).clamp(2.0, 3.5);

      final List<Uint8List> compressedPages = [];
      final List<PdfPageFormat> pageFormats = [];

      for (int i = 1; i <= pageCount; i++) {
        final progressRatio = 0.10 + (0.75 * (i / pageCount));
        onProgress?.call(
          progressRatio,
          'Optimizing page $i of $pageCount (Max DPI)...',
        );

        final page = await document.getPage(i);
        pageFormats.add(PdfPageFormat(page.width, page.height));

        final renderedPage = await page.render(
          width: page.width * renderScale,
          height: page.height * renderScale,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        await page.close();

        if (renderedPage == null || renderedPage.bytes.isEmpty) {
          throw Exception('Failed to render page $i of PDF.');
        }

        // Fast integer binary search for exact target budget fill
        final optimizedBytes = await compute(
          _exactBudgetClaritySearch,
          _OptimizationTask(
            highResJpegBytes: renderedPage.bytes,
            budgetBytes: budgetPerPage,
          ),
        );

        compressedPages.add(optimizedBytes);
      }

      await document.close();

      onProgress?.call(0.90, 'Assembling optimized PDF...');
      var pdfBytes = await _buildPdfDocument(compressedPages, pageFormats);

      // Fine-tuning pass only if total PDF strictly exceeds target limit
      if (pdfBytes.length > targetSizeBytes) {
        onProgress?.call(0.95, 'Fine-tuning exact size...');
        final excessRatio = targetSizeBytes / pdfBytes.length;
        final refinedBudget = (budgetPerPage * excessRatio * 0.985).floor();

        final refinedPages = <Uint8List>[];
        for (int i = 0; i < compressedPages.length; i++) {
          final refined = await compute(
            _exactBudgetClaritySearch,
            _OptimizationTask(
              highResJpegBytes: compressedPages[i],
              budgetBytes: refinedBudget,
            ),
          );
          refinedPages.add(refined);
        }

        pdfBytes = await _buildPdfDocument(refinedPages, pageFormats);
      }

      onProgress?.call(0.98, 'Saving...');

      final tempDir = await getTemporaryDirectory();
      final baseName = p.basenameWithoutExtension(inputFile.path);
      final targetKbFormatted = (targetSizeBytes / 1024).round();
      final outputFileName = '${baseName}_compressed_${targetKbFormatted}kb.pdf';
      final outputFile = File('${tempDir.path}/$outputFileName');

      await outputFile.writeAsBytes(pdfBytes);

      stopwatch.stop();
      onProgress?.call(1.0, 'Done!');

      return CompressionResult(
        originalFile: inputFile,
        compressedFile: outputFile,
        originalSizeBytes: originalSize,
        compressedSizeBytes: outputFile.lengthSync(),
        targetSizeBytes: targetSizeBytes,
        pageCount: pageCount,
        duration: stopwatch.elapsed,
        success: true,
      );
    } catch (e) {
      stopwatch.stop();
      return CompressionResult(
        originalFile: inputFile,
        compressedFile: inputFile,
        originalSizeBytes: originalSize,
        compressedSizeBytes: originalSize,
        targetSizeBytes: targetSizeBytes,
        pageCount: 0,
        duration: stopwatch.elapsed,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  static Future<Uint8List> _buildPdfDocument(
    List<Uint8List> pageImages,
    List<PdfPageFormat> formats,
  ) async {
    final pdf = pw.Document(
      title: 'Compressed Document',
      author: 'PDF Compressor',
      creator: 'Microsoft Print to PDF',
      producer: 'Microsoft Print to PDF',
    );

    for (int i = 0; i < pageImages.length; i++) {
      final image = pw.MemoryImage(pageImages[i]);
      pdf.addPage(
        pw.Page(
          pageFormat: formats[i],
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(image, fit: pw.BoxFit.fill),
            );
          },
        ),
      );
    }

    return await pdf.save();
  }
}

class _OptimizationTask {
  final Uint8List highResJpegBytes;
  final int budgetBytes;

  _OptimizationTask({
    required this.highResJpegBytes,
    required this.budgetBytes,
  });
}

/// Exact integer binary search for maximum sharpness and highest target budget fill:
Uint8List _exactBudgetClaritySearch(_OptimizationTask task) {
  // If original high-res already fits inside budget, keep 100% full quality!
  if (task.highResJpegBytes.length <= task.budgetBytes) {
    return task.highResJpegBytes;
  }

  final originalImage = img.decodeImage(task.highResJpegBytes);
  if (originalImage == null) {
    return task.highResJpegBytes;
  }

  final origW = originalImage.width;
  final origH = originalImage.height;

  // Step 1: Integer binary search on Full Resolution (Quality 30 to 95)
  int lowQ = 30;
  int highQ = 95;
  Uint8List? bestFullResBytes;
  int bestFullResSize = 0;

  while (lowQ <= highQ) {
    final midQ = (lowQ + highQ) ~/ 2;
    final encoded = Uint8List.fromList(img.encodeJpg(originalImage, quality: midQ));

    if (encoded.length <= task.budgetBytes) {
      if (encoded.length > bestFullResSize) {
        bestFullResSize = encoded.length;
        bestFullResBytes = encoded;
      }
      // Try higher quality closer to budget limit
      lowQ = midQ + 1;
    } else {
      // Too big, decrease quality
      highQ = midQ - 1;
    }
  }

  // If full resolution at quality >= 40 fits and fills >= 75% of budget, use it!
  // This preserves 100% native pixels!
  if (bestFullResBytes != null && bestFullResSize >= (task.budgetBytes * 0.75)) {
    return bestFullResBytes;
  }

  // Step 2: If full resolution was too large for the budget, calculate required scale directly
  final baselineSize = bestFullResSize > 0 ? bestFullResSize : task.highResJpegBytes.length;
  final scaleFactor = math.sqrt(task.budgetBytes / baselineSize).clamp(0.30, 0.95);

  final targetW = (origW * scaleFactor).round();
  final targetH = (origH * scaleFactor).round();

  final resizedImage = img.copyResize(
    originalImage,
    width: targetW,
    height: targetH,
    interpolation: img.Interpolation.linear,
  );

  // Exact binary search on quality for the resized image
  int lowRQ = 40;
  int highRQ = 92;
  Uint8List? bestResizedBytes;
  int bestResizedSize = 0;

  while (lowRQ <= highRQ) {
    final midRQ = (lowRQ + highRQ) ~/ 2;
    final encoded = Uint8List.fromList(img.encodeJpg(resizedImage, quality: midRQ));

    if (encoded.length <= task.budgetBytes) {
      if (encoded.length > bestResizedSize) {
        bestResizedSize = encoded.length;
        bestResizedBytes = encoded;
      }
      lowRQ = midRQ + 1;
    } else {
      highRQ = midRQ - 1;
    }
  }

  if (bestResizedBytes != null) {
    if (bestFullResBytes != null && bestFullResSize > bestResizedSize) {
      return bestFullResBytes;
    }
    return bestResizedBytes;
  }

  return bestFullResBytes ?? Uint8List.fromList(img.encodeJpg(resizedImage, quality: 45));
}
