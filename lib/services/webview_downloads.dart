import 'dart:async';
import 'package:webspace/platform/host_platform.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:webspace/services/blob_url_capture.dart';
import 'package:webspace/services/download_engine.dart';
import 'package:webspace/services/download_manager.dart';
import 'package:webspace/settings/proxy.dart';
import 'package:webspace/services/log_service.dart';
import 'package:webspace/services/webview_config.dart';
import 'package:webspace/widgets/root_messenger.dart';

/// Downloads a site webview starts: http(s) through the site's proxy, data:
/// and blob: URLs from the page, each saved where the user picks.
abstract final class WebViewDownloads {
  /// Whether two absolute HTTP(S) URLs share an origin, including effective
  /// default ports. Used to keep a page bridge from downloading another host.
  @visibleForTesting
  static bool isSameHttpOrigin(String candidate, {required String current}) {
    final a = Uri.tryParse(candidate);
    final b = Uri.tryParse(current);
    if (a == null || b == null || !_isHttp(a) || !_isHttp(b)) return false;
    int port(Uri uri) => uri.hasPort
        ? uri.port
        : (uri.scheme.toLowerCase() == 'http' ? 80 : 443);
    return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        port(a) == port(b);
  }

  static bool _isHttp(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') &&
        uri.host.isNotEmpty &&
        (!uri.hasPort || (uri.port > 0 && uri.port <= 65535));
  }

  static Future<void> handleDownloadRequest(
    inapp.InAppWebViewController controller, {
    required inapp.DownloadStartRequest req,
    required WebViewConfig config,
    String? referer,
    UserProxySettings? proxy,
  }) async {
    final urlStr = req.url.toString();
    final scheme = req.url.scheme.toLowerCase();

    switch (scheme) {
      case 'http':
      case 'https':
        await _handleHttpDownload(
          controller,
          req: req,
          config: config,
          referer: referer,
          proxy: proxy,
        );
        return;
      case 'data':
        _handleDataDownload(req);
        return;
      case 'blob':
        await handleBlobDownload(controller,
            blobUrl: urlStr, suggestedFilename: req.suggestedFilename);
        return;
      default:
        _showDownloadSnack('Can\'t download $scheme: URL.');
    }
  }

  static Future<void> handleHttpDownloadFromAnchor(
    inapp.InAppWebViewController controller, {
    required WebViewConfig config,
    required String url,
    required String suggestedFilename,
    required String referer,
  }) async {
    if (!hostIsAndroid || !isSameHttpOrigin(url, current: referer)) return;
    String? userAgent;
    try {
      userAgent = await inapp.InAppWebViewController.getDefaultUserAgent();
    } catch (_) {}
    final req = inapp.DownloadStartRequest(
      url: inapp.WebUri(url),
      userAgent: userAgent,
      contentDisposition: null,
      contentLength: -1,
      mimeType: null,
      suggestedFilename: suggestedFilename.isEmpty ? null : suggestedFilename,
      textEncodingName: null,
    );
    try {
      await controller.stopLoading();
    } catch (_) {}
    await _handleHttpDownload(
      controller,
      req: req,
      config: config,
      referer: referer,
      proxy: config.posture.container.proxy,
    );
  }

  static Future<void> _handleHttpDownload(
    inapp.InAppWebViewController controller, {
    required inapp.DownloadStartRequest req,
    required WebViewConfig config,
    String? referer,
    UserProxySettings? proxy,
  }) async {
    final initialFilename = DownloadEngine.deriveFilename(
      suggested: req.suggestedFilename,
      url: req.url.toString(),
      mimeType: req.mimeType,
    );
    Future<bool> handOffToBrowser(String reason) async {
      final fallback = config.onHttpDownload;
      if (fallback == null) return false;
      try {
        final launched = await fallback(req.url.toString());
        if (!launched) {
          LogTag.download.warning(
            '$reason: system browser launch returned false',
            sensitive: true,
          );
        }
        return launched;
      } catch (e, stack) {
        LogTag.download.warning(
          '$reason: system browser launch failed: $e\n$stack',
          sensitive: true,
        );
        return false;
      }
    }

    final List<inapp.Cookie> cookies;
    try {
      // Scope the read to this WebView so isolated site sessions survive.
      cookies = await inapp.CookieManager.instance().getCookies(
        url: req.url,
        webViewController: controller,
      );
    } catch (e, stack) {
      if (await handOffToBrowser('Internal cookie read failed')) {
        LogTag.download.warning(
          'Internal cookie read failed; handed off to system browser: $e',
          sensitive: true,
        );
        return;
      }
      LogTag.download.error(
        'Cookie read failed: $e\n$stack',
        sensitive: true,
      );
      final task = DownloadsService.instance.start(
        filename: initialFilename,
        url: req.url.toString(),
        bytesTotal: req.contentLength > 0 ? req.contentLength : null,
      );
      DownloadsService.instance.fail(
        task.id,
        message: 'Could not read site cookies',
      );
      return;
    }

    final task = DownloadsService.instance.start(
      filename: initialFilename,
      url: req.url.toString(),
      bytesTotal: req.contentLength > 0 ? req.contentLength : null,
    );
    try {
      final cookieHeader = DownloadEngine.buildCookieHeader(
        cookies.map((c) => MapEntry(c.name, c.value.toString())),
      );
      LogTag.download.debug(
          'HTTP download: url=${req.url} cookies=${cookies.length} '
          'ua=${req.userAgent != null} referer=${referer != null}',
          sensitive: true);
      final engine = DownloadEngine(proxy: proxy);
      final result = await engine.fetch(
        url: req.url.toString(),
        cookieHeader: cookieHeader,
        cookieHeaderFor: (uri) async {
          final hop = await inapp.CookieManager.instance().getCookies(
            url: inapp.WebUri(uri.toString()),
            webViewController: controller,
          );
          return DownloadEngine.buildCookieHeader(
            hop.map((c) => MapEntry(c.name, c.value.toString())),
          );
        },
        userAgent: req.userAgent,
        referer: referer,
        suggestedFilename: req.suggestedFilename,
        mimeTypeHint: req.mimeType,
        onProgress: (done, {required bytesTotal}) => DownloadsService.instance
            .updateProgress(task.id, bytesDone: done, bytesTotal: bytesTotal),
      );
      task.filename = result.filename;
      final savedPath = await saveViaPicker(result);
      if (savedPath == null) {
        DownloadsService.instance.cancel(task.id);
      } else {
        DownloadsService.instance.complete(task.id, savedPath: savedPath);
      }
    } on DownloadException catch (e) {
      if (await handOffToBrowser('Internal download failed')) {
        DownloadsService.instance.cancel(task.id);
      } else {
        DownloadsService.instance.fail(task.id, message: e.message);
      }
    } catch (e, stack) {
      LogTag.download.error('Download error: $e\n$stack', sensitive: true);
      DownloadsService.instance.fail(task.id, message: e.toString());
    }
  }

  static void _handleDataDownload(inapp.DownloadStartRequest req) async {
    final task = DownloadsService.instance.start(
      filename: req.suggestedFilename?.isNotEmpty == true
          ? req.suggestedFilename!
          : 'download',
      url: req.url.toString(),
    );
    try {
      final result = DownloadEngine.decodeDataUri(
        url: req.url.toString(),
        suggestedFilename: req.suggestedFilename,
      );
      task.filename = result.filename;
      DownloadsService.instance.updateProgress(task.id,
          bytesDone: result.bytes.length, bytesTotal: result.bytes.length);
      final savedPath = await saveViaPicker(result);
      if (savedPath == null) {
        DownloadsService.instance.cancel(task.id);
      } else {
        DownloadsService.instance.complete(task.id, savedPath: savedPath);
      }
    } on DownloadException catch (e) {
      DownloadsService.instance.fail(task.id, message: e.message);
    } catch (e, stack) {
      LogTag.download.error(
          'Data-URI download error: $e\n$stack', sensitive: true);
      DownloadsService.instance.fail(task.id, message: e.toString());
    }
  }

  static Future<void> handleBlobDownload(
    inapp.InAppWebViewController controller, {
    required String blobUrl,
    required String? suggestedFilename,
  }) async {
    final task = DownloadsService.instance.start(
      filename: suggestedFilename?.isNotEmpty == true
          ? suggestedFilename!
          : 'download',
      url: blobUrl,
    );
    final script = buildBlobDownloadIife(
      blobUrl: blobUrl,
      taskId: task.id,
      suggestedFilename: suggestedFilename,
    );
    try {
      await controller.evaluateJavascript(source: script);
    } catch (e, stack) {
      LogTag.download.error(
          'Blob download eval error: $e\n$stack', sensitive: true);
      DownloadsService.instance.fail(task.id, message: e.toString());
    }
  }

  static Future<String?> saveViaPicker(DownloadResult result) async {
    final isMobile = !kIsWeb && (hostIsIOS || hostIsAndroid);
    final outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save download',
      fileName: result.filename,
      bytes: isMobile ? result.bytes : null,
    );
    if (outputPath == null) return null;
    if (!isMobile) {
      await hostWriteBytes(outputPath, bytes: result.bytes);
    }
    return outputPath;
  }

  static void _showDownloadSnack(String message) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Coerce a JS handler arg to an int. Small integers come back as int
  /// but large ones can arrive as double (JSON number serialization), so
  /// normalize both.
  static int? asInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
