import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
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
        return File(file.path!);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Shares the PDF file with other apps (WhatsApp, Gmail, Drive, etc.)
  static Future<void> sharePdf(String filePath, {String? text}) async {
    try {
      final xFile = XFile(filePath);
      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          text: text ?? 'Compressed PDF Document',
        ),
      );
    } catch (e) {
      // Handle share error gracefully
    }
  }

  /// Saves the compressed PDF to the device's public Downloads directory
  static Future<String?> savePdfToDownloads(File sourceFile, String customName) async {
    try {
      Directory? downloadsDir;
      
      if (Platform.isAndroid) {
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) {
          downloadsDir = publicDownload;
        } else {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        return null;
      }

      String destinationPath = '${downloadsDir.path}/$customName';
      int counter = 1;
      final nameWithoutExt = customName.replaceAll('.pdf', '');

      while (await File(destinationPath).exists()) {
        destinationPath = '${downloadsDir.path}/${nameWithoutExt}_$counter.pdf';
        counter++;
      }

      final savedFile = await sourceFile.copy(destinationPath);
      return savedFile.path;
    } catch (e) {
      return null;
    }
  }

  /// Opens the PDF with the system's default PDF viewer
  static Future<bool> openPdf(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      return result.type == ResultType.done;
    } catch (e) {
      return false;
    }
  }
}
