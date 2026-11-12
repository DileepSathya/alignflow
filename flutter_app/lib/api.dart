import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

const defaultApiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');
const _serverAddressKey = 'server_address';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

String normalizeServerAddress(String input) {
  final value = input.trim();
  if (value.isEmpty) {
    throw ApiException('Enter the PC IP address, for example 192.168.1.25:8000.');
  }
  final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
  if (uri == null || !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty || uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') || uri.hasQuery || uri.hasFragment ||
      uri.port < 1 || uri.port > 65535) {
    throw ApiException('Enter a valid server address, such as 192.168.1.25:8000.');
  }
  final parts = uri.host.split('.');
  if (parts.length == 4 && parts.every((part) => int.tryParse(part) != null) &&
      parts.any((part) => part.isEmpty || int.parse(part) > 255)) {
    throw ApiException('Enter a valid PC IP address.');
  }
  final port = uri.hasPort ? uri.port : 8000;
  return '${uri.scheme}://${uri.host}:$port';
}

class Api {
  String serverAddress = defaultApiBase;
  String? token;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    serverAddress = prefs.getString(_serverAddressKey) ?? defaultApiBase;
    token = prefs.getString('token');
  }

  Future<void> useServer(String address) async {
    final normalized = normalizeServerAddress(address);
    final prefs = await SharedPreferences.getInstance();
    if (serverAddress != normalized) {
      token = null;
      await prefs.remove('token');
    }
    serverAddress = normalized;
    await prefs.setString(_serverAddressKey, normalized);
  }

  Future<void> checkServer() async {
    try {
      final response = await http.get(Uri.parse('$serverAddress/health'))
          .timeout(const Duration(seconds: 6));
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 || body is! Map || body['ok'] != true) {
        throw ApiException('This address is not an AlignFlow server.');
      }
    } on ApiException { rethrow; }
    on TimeoutException { throw ApiException('Connection timed out. Check the PC address and Wi-Fi.'); }
    on SocketException { throw ApiException('Cannot reach the PC. Check its IP, Wi-Fi, and firewall.'); }
    on http.ClientException { throw ApiException('Cannot reach the PC. Check its IP, Wi-Fi, and firewall.'); }
    on FormatException { throw ApiException('This address is not an AlignFlow server.'); }
  }

  Future<Map<String, dynamic>> request(String method, String path, [Map<String, dynamic>? data]) async {
    try {
      final response = http.Request(method, Uri.parse('$serverAddress$path'));
      response.headers['Content-Type'] = 'application/json';
      if (token != null) response.headers['Authorization'] = 'Bearer $token';
      if (data != null) response.body = jsonEncode(data);
      final sent = await response.send().timeout(const Duration(seconds: 10));
      final body = await sent.stream.bytesToString();
      Map<String, dynamic> decoded = {};
      if (body.isNotEmpty) decoded = jsonDecode(body) as Map<String, dynamic>;
      if (sent.statusCode < 200 || sent.statusCode >= 300) {
        throw ApiException(decoded['detail']?.toString() ?? 'Server returned ${sent.statusCode}.');
      }
      return decoded;
    } on ApiException { rethrow; }
    on TimeoutException { throw ApiException('The server did not respond in time.'); }
    on SocketException { throw ApiException('Connection lost. Check the PC and Wi-Fi.'); }
    on http.ClientException { throw ApiException('Connection lost. Check the PC and Wi-Fi.'); }
    on FormatException { throw ApiException('The server sent an invalid response.'); }
  }

  Future<Map<String, dynamic>> uploadOrderFile(String orderId, PlatformFile file) async {
    if ((await file.length() ?? 0) > 20 * 1024 * 1024) {
      throw ApiException('File exceeds 20 MB.');
    }
    final bytes = await file.readAsBytes();
    final request = http.MultipartRequest('POST', Uri.parse('$serverAddress/api/orders/$orderId/documents'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: file.name));
    final response = await request.send();
    final body = jsonDecode(await response.stream.bytesToString()) as Map<String, dynamic>;
    if (response.statusCode >= 300) throw ApiException(body['detail']?.toString() ?? 'Upload failed.');
    return body;
  }

  Future<List<int>> downloadOrderFile(String orderId, String fileId) async {
    final response = await http.get(Uri.parse('$serverAddress/api/orders/$orderId/documents/$fileId'),
        headers: {if (token != null) 'Authorization': 'Bearer $token'});
    if (response.statusCode >= 300) throw ApiException('Download failed.');
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final result = await request('POST', '/api/login', {'username': username, 'password': password});
    token = result['token'] as String;
    await (await SharedPreferences.getInstance()).setString('token', token!);
    return result['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me() async => (await request('GET', '/api/me'))['user'] as Map<String, dynamic>;

  Future<void> logout() async {
    try {
      if (token != null) await request('POST', '/api/logout');
    } catch (_) {
      // A local sign-out must still work if the session has expired or the API is offline.
    } finally {
      token = null;
      await (await SharedPreferences.getInstance()).remove('token');
    }
  }
}
