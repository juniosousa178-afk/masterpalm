// lib/services/upload_manager.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:pool/pool.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../src/io_compat.dart' show createFile;
import 'package:file_picker/file_picker.dart' show PlatformFile;

/// ===============================================================
/// UploadManager (File + Bytes) – compatível com Android/Windows/Web
/// ===============================================================
/// - Android/Windows: usa putFile(File)
/// - Web: usa putData(Uint8List)
/// - Controle de concorrência com Pool
/// - Progresso via snapshotEvents
/// - ✅ dispose(): cancela uploads e impede novos uploads após fechar tela
/// ===============================================================

/// Descrição de um upload por FILE (Android/Windows)
class UploadRequest {
  UploadRequest({
    required this.platformFile,
    required this.storagePath,
    this.metadata,
    this.onProgress,
    this.onState,
  });

  final PlatformFile platformFile;
  final String storagePath;
  final SettableMetadata• metadata;

  final void Function(double p)• onProgress;
  final void Function(TaskState s)• onState;
}


/// Upload por BYTES (Web)
class UploadBytesRequest {
  UploadBytesRequest({
    required this.bytes,
    required this.storagePath,
    this.metadata,
    this.onProgress,
    this.onState,
  });

  final Uint8List bytes;

  /// Ex.: 'lojas/masterpalm/midias/banners/IMG_001.jpg'
  final String storagePath;

  final SettableMetadata• metadata;

  /// 0.0 → 1.0
  final void Function(double progress)• onProgress;

  /// Estados do Firebase Storage (running, success, error…)
  final void Function(TaskState state)• onState;
}

/// Resultado final de um upload
class UploadResult {
  UploadResult({
    required this.storagePath,
    required this.downloadUrl,
    required this.bytesSent,
    required this.totalBytes,
  });

  final String storagePath;
  final String downloadUrl;
  final int bytesSent;
  final int totalBytes;
}

/// Gerencia fila, concorrência e progresso.
class UploadManager {
  UploadManager({int maxConcurrent = 3})
      : _pool = Pool(maxConcurrent),
        _storage = FirebaseStorage.instance;

  final Pool _pool;
  final FirebaseStorage _storage;

  /// Uploads em andamento (permite cancelar)
  final Map<String, UploadTask> _inFlight = {};

  bool _disposed = false;
  bool get isDisposed => _disposed;

  void _ensureAlive() {
    if (_disposed) {
      throw StateError(
        'UploadManager já foi descartado (dispose). '
        'Evite iniciar upload após fechar a tela.',
      );
    }
  }

 // ===============================================================
// UPLOAD POR FILE (Android/Windows) + fallback Web (PlatformFile.bytes)
// ===============================================================
Future<UploadResult> enqueue(UploadRequest req) async {
  _ensureAlive();

  return _pool.withResource(() async {
    _ensureAlive();

    final ref = _storage.ref().child(req.storagePath);

    // ✅ WEB: PlatformFile geralmente vem com bytes (withData: true)
    if (kIsWeb) {
      final bytes = req.platformFile.bytes;
      if (bytes == null) {
        throw StateError(
          'No web, o PlatformFile precisa ter bytes. '
          'Use FilePicker com withData: true ou chame enqueueBytes().',
        );
      }

      final task = ref.putData(bytes, req.metadata);
      _inFlight[req.storagePath] = task;

      final sub = task.snapshotEvents.listen((snap) {
        if (_disposed) return;
        if (snap.totalBytes > 0) {
          req.onProgress?.call(snap.bytesTransferred / snap.totalBytes);
        }
        req.onState?.call(snap.state);
      });

      try {
        final snapshot = await task.whenComplete(() {});
        final url = await snapshot.ref.getDownloadURL();

        return UploadResult(
          storagePath: req.storagePath,
          downloadUrl: url,
          bytesSent: snapshot.bytesTransferred,
          totalBytes: snapshot.totalBytes,
        );
      } finally {
        await sub.cancel();
        _inFlight.remove(req.storagePath);
      }
    }

    // ✅ ANDROID/WINDOWS/macOS/Linux: usa path + putFile
    final path = req.platformFile.path;
    if (path == null || path.isEmpty) {
      throw StateError('Arquivo sem path. Em web use enqueueBytes() ou withData: true.');
    }

    final UploadTask task;
    if (kIsWeb) {
      // No web, putFile não funciona - deve usar enqueueBytes
      throw StateError('No web, use enqueueBytes() em vez de enqueue() com path.');
    } else {
      // Plataformas IO: Android, Windows, macOS, Linux
      task = ref.putFile(createFile(path), req.metadata);
    }

    _inFlight[req.storagePath] = task;

    final sub = task.snapshotEvents.listen((snap) {
      if (_disposed) return;
      if (snap.totalBytes > 0) {
        req.onProgress?.call(snap.bytesTransferred / snap.totalBytes);
      }
      req.onState?.call(snap.state);
    });

    try {
      final snapshot = await task.whenComplete(() {});
      final url = await snapshot.ref.getDownloadURL();

      return UploadResult(
        storagePath: req.storagePath,
        downloadUrl: url,
        bytesSent: snapshot.bytesTransferred,
        totalBytes: snapshot.totalBytes,
      );
    } finally {
      await sub.cancel();
      _inFlight.remove(req.storagePath);
    }
  });
}

  // ===============================================================
  // UPLOAD POR BYTES (WEB)
  // ===============================================================
  Future<UploadResult> enqueueBytes(UploadBytesRequest req) async {
    _ensureAlive();

    return _pool.withResource(() async {
      _ensureAlive();

      final ref = _storage.ref().child(req.storagePath);

      final task = ref.putData(req.bytes, req.metadata);
      _inFlight[req.storagePath] = task;

      final sub = task.snapshotEvents.listen((TaskSnapshot snap) {
        if (_disposed) return;

        if (snap.totalBytes > 0) {
          final p = snap.bytesTransferred / snap.totalBytes;
          req.onProgress?.call(p);
        }
        req.onState?.call(snap.state);
      });

      try {
        final snapshot = await task.whenComplete(() {});
        final url = await snapshot.ref.getDownloadURL();
        return UploadResult(
          storagePath: req.storagePath,
          downloadUrl: url,
          bytesSent: snapshot.bytesTransferred,
          totalBytes: snapshot.totalBytes,
        );
      } finally {
        await sub.cancel();
        _inFlight.remove(req.storagePath);
      }
    });
  }

  // ===============================================================
  // UPLOAD EM LOTE (FILE)
  // ===============================================================
  Future<List<UploadResult>> enqueueAll(List<UploadRequest> requests) async {
    _ensureAlive();
    return Future.wait(requests.map(enqueue));
  }

  // ===============================================================
  // UPLOAD EM LOTE (BYTES/WEB)
  // ===============================================================
  Future<List<UploadResult>> enqueueAllBytes(
    List<UploadBytesRequest> requests,
  ) async {
    _ensureAlive();
    return Future.wait(requests.map(enqueueBytes));
  }

  // ===============================================================
  // CANCELAMENTOS
  // ===============================================================
  Future<void> cancel(String storagePath) async {
    final task = _inFlight[storagePath];
    if (task != null) {
      try {
        // Só cancela se não estiver em estado final (success/error/canceled)
        final snapshot = task.snapshot;
        if (snapshot.state != TaskState.success &&
            snapshot.state != TaskState.error &&
            snapshot.state != TaskState.canceled) {
          await task.cancel();
        }
      } catch (_) {
        // Ignora erros de cancelamento (tarefa já finalizada)
      } finally {
        _inFlight.remove(storagePath);
      }
    }
  }

  Future<void> cancelAll() async {
    final tasks = List<UploadTask>.from(_inFlight.values);
    for (final t in tasks) {
      try {
        // Só cancela se não estiver em estado final
        final snapshot = t.snapshot;
        if (snapshot.state != TaskState.success &&
            snapshot.state != TaskState.error &&
            snapshot.state != TaskState.canceled) {
          await t.cancel();
        }
      } catch (_) {
        // Ignora erros de cancelamento
      }
    }
    _inFlight.clear();
  }

  // ===============================================================
  // ✅ DISPOSE (para telas)
  // ===============================================================
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    unawaited(cancelAll());
    unawaited(_pool.close());
  }
}
