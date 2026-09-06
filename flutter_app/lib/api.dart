import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}

class Api {
  static const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:5000',
  );
  final http.Client client;
  final storage = const FlutterSecureStorage();
  String? token;
  void Function()? onUnauthorized;
  Api({http.Client? client}) : client = client ?? http.Client();
  Uri uri(String path) => Uri.parse('$baseUrl$path');
  Map<String, String> get headers => {
    if (token != null) 'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
  Future<void> restore() async {
    token = await storage.read(key: 'session:$baseUrl');
  }

  Future<void> clear() async {
    token = null;
    await storage.delete(key: 'session:$baseUrl');
  }

  Future<void> login(String username, String password) async {
    final data = await request('POST', '/api/auth/login', {
      'username': username,
      'password': password,
    });
    token = data['accessToken'] as String;
    await storage.write(key: 'session:$baseUrl', value: token);
  }

  dynamic decode(http.Response response) {
    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      data = null;
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && token != null) onUnauthorized?.call();
      final errors = data is Map ? data['errors'] : null;
      throw ApiException(
        data is Map
            ? (data['message'] ??
                      (errors is Map
                          ? errors.values.expand((v) => v as List).join('\n')
                          : data['title']) ??
                      'Request failed')
                  .toString()
            : 'Request failed (${response.statusCode})',
        response.statusCode,
      );
    }
    return data;
  }

  Future<dynamic> request(String method, String path, [Object? body]) async {
    final request = http.Request(method, uri(path))..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    return decode(
      await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 30)),
      ),
    );
  }

  Future<Json> upload(
    String conversation,
    Uint8List bytes,
    String name,
    String mime,
  ) async {
    if (bytes.length > 25 * 1024 * 1024) {
      throw ApiException('Files must be 25 MB or smaller.', 400);
    }
    final request =
        http.MultipartRequest(
            'POST',
            uri('/api/attachments/conversations/$conversation'),
          )
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: name,
              contentType: MediaType.parse(mime),
            ),
          );
    return Map<String, dynamic>.from(
      decode(
            await http.Response.fromStream(
              await client.send(request).timeout(const Duration(minutes: 2)),
            ),
          )
          as Map,
    );
  }

  Future<Uint8List> download(String path) async {
    // Only send credentials to our own backend.
    final target = uri(path);
    if (target.origin != Uri.parse(baseUrl).origin) {
      throw ApiException('Invalid attachment URL.', 400);
    }
    final response = await client
        .get(target, headers: headers)
        .timeout(const Duration(minutes: 2));
    if (response.statusCode >= 400) decode(response);
    return response.bodyBytes;
  }

  void dispose() => client.close();
}
