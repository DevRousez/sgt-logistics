import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

Future<void> saveAndOpenFile(Uint8List bytes, String fileName) async {
  try {
    final directory = await getTemporaryDirectory();
    final String path = "${directory.path}/$fileName";
    final File file = File(path);
    await file.writeAsBytes(bytes);
    await OpenFilex.open(path);
  } catch (e) {
    throw Exception("No se pudo abrir el archivo local: $e");
  }
}
