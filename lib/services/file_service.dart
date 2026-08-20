import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileService {
  /// Picks a single PDF file from the device storage
  static Future<File?> pickPdfFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (file != null && file.path != null) {
        final f = File(file.path!);
        if (await f.exists()) {
          return f;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Shares the PDF file with other apps (WhatsApp, Gmail, Drive, etc.) with custom name
  static Future<bool> sharePdf(
    String filePath, {
    String? customName,
    String? text,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      String sharePath = filePath;
      if (customName != null && customName.trim().isNotEmpty) {
        final cleanName = customName.endsWith('.pdf') ? customName.trim() : '${customName.trim()}.pdf';
        final tempDir = await getTemporaryDirectory();
        final renamedFile = File('${tempDir.path}/$cleanName');
        await file.copy(renamedFile.path);
        sharePath = renamedFile.path;
      }

      final fileName = p.basename(sharePath);
      final xFile = XFile(
        sharePath,
        mimeType: 'application/pdf',
        name: fileName,
      );

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          text: text ?? 'Compressed PDF ($fileName)',
        ),
      );

      return result.status == ShareResultStatus.success;
    } catch (e) {
      return false;
    }
  }

  /// Saves the compressed PDF to the device's public Downloads directory with a custom name
  static Future<String?> savePdfToDownloads(File sourceFile, String customName) async {
    try {
      if (!await sourceFile.exists()) {
        return null;
      }

      final bytes = await sourceFile.readAsBytes();
      late Directory targetDir;

      if (Platform.isAndroid) {
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) {
          targetDir = publicDownload;
        } else {
          targetDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        }
      } else {
        targetDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      final cleanName = customName.endsWith('.pdf') ? customName.trim() : '${customName.trim()}.pdf';
      String destinationPath = '${targetDir.path}/$cleanName';
      int counter = 1;
      final nameWithoutExt = p.basenameWithoutExtension(cleanName);

      while (await File(destinationPath).exists()) {
        destinationPath = '${targetDir.path}/${nameWithoutExt}_$counter.pdf';
        counter++;
      }

      final savedFile = File(destinationPath);
      await savedFile.writeAsBytes(bytes, flush: true);

      return savedFile.path;
    } catch (e) {
      return null;
    }
  }

  /// Opens the PDF with the system's default PDF viewer
  static Future<bool> openPdf(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final result = await OpenFilex.open(filePath, type: 'application/pdf');
      return result.type == ResultType.done;
    } catch (e) {
      return false;
    }
  }
}
