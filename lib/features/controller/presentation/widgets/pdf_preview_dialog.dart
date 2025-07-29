import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;

class PDFPreviewDialog extends StatelessWidget {
  final List<int> pdfBytes;
  final String fileName;

  const PDFPreviewDialog({
    super.key,
    required this.pdfBytes,
    this.fileName = 'exam_timetable.pdf',
  });

  Future<void> _downloadPDF() async {
    if (kIsWeb) {
      final blob = html.Blob([pdfBytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      try {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save exam timetable',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );

        final file = File(outputFile!);
        await file.writeAsBytes(pdfBytes);
            } catch (e) {
        debugPrint('Error saving PDF: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Exam Timetable'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_as_pdf, size: 64, color: Colors.red),
          SizedBox(height: 16),
          Text('PDF has been generated successfully!'),
          SizedBox(height: 8),
          Text(
            'Click the download button to save the timetable.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _downloadPDF,
          icon: const Icon(Icons.download),
          label: const Text('Download PDF'),
        ),
      ],
    );
  }
}
