import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class TrendyolAPIException implements Exception {
  final String message;
  TrendyolAPIException(this.message);
  
  @override
  String toString() => 'TrendyolAPIException: $message';
}

class TrendyolAPI {
  static const String baseUrl = 'https://apigw.trendyol.com';
  
  final String sellerId;
  final String apiKey;
  final String apiSecret;
  
  late final http.Client _client;
  late final String _auth;

  TrendyolAPI({
    required this.sellerId,
    required this.apiKey,
    required this.apiSecret,
  }) {
    _client = http.Client();
    _auth = 'Basic ${base64Encode(utf8.encode('$apiKey:$apiSecret'))}';
  }

  Map<String, String> get _headers => {
    'Authorization': _auth,
    'Content-Type': 'application/json',
    'User-Agent': '$sellerId - TrendyolHesaplayici',
  };

  /// Bağlantıyı test eder
  Future<bool> testConnection() async {
    try {
      final url = '$baseUrl/integration/product/sellers/$sellerId/products?page=0&size=1';
      final response = await _client.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200 || response.statusCode == 400;
    } catch (e) {
      debugPrint('Bağlantı testi hatası: $e');
      return false;
    }
  }

  /// Ürünleri sayfalı olarak getirir
  Future<Map<String, dynamic>> getProducts({int page = 0, int size = 50}) async {
    try {
      final url = '$baseUrl/integration/product/sellers/$sellerId/products?page=$page&size=$size';
      final response = await _client.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw TrendyolAPIException(
          'Ürün çekilemedi: ${response.statusCode} - ${response.body.substring(0, 200)}',
        );
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw TrendyolAPIException('Ürün çekme hatası: $e');
    }
  }

  /// Tüm ürünleri getirir (sayfalama ile)
  Future<List<Map<String, dynamic>>> getAllProducts({
    void Function(int current, int total, int productCount)? onProgress,
  }) async {
    final List<Map<String, dynamic>> allProducts = [];
    int page = 0;
    int totalPages = 1;

    while (page < totalPages) {
      final data = await getProducts(page: page, size: 200);
      final content = (data['content'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      allProducts.addAll(content);
      
      totalPages = data['totalPages'] as int? ?? 1;
      
      if (onProgress != null) {
        onProgress(page + 1, totalPages, allProducts.length);
      }

      page++;
      
      if (page < totalPages) {
        await Future.delayed(const Duration(milliseconds: 300)); // Rate limiting
      }
    }

    return allProducts;
  }

  /// Resmi indirir ve cache'e kaydeder
  Future<String?> downloadAndCacheImage(String imageUrl, String barcode) async {
    try {
      // Cache dizini oluştur
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${appDir.path}/product_images');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      // Dosya yolunu belirle
      final fileExtension = path.extension(imageUrl);
      final fileName = '${barcode}_main$fileExtension';
      final filePath = '${cacheDir.path}/$fileName';

      // Dosya zaten var mı kontrol et
      final file = File(filePath);
      if (await file.exists()) {
        return filePath;
      }

      // İndir
      final response = await _client.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      }

      return null;
    } catch (e) {
      debugPrint('Resim indirme hatası: $e');
      return null;
    }
  }

  /// Fiyat ve stok günceller
  Future<Map<String, dynamic>> updatePriceAndStock({
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final url = '$baseUrl/integration/inventory/sellers/$sellerId/products/price-and-inventory';
      
      // Payload formatı
      final priceItems = items.map((item) => {
        'barcode': item['barcode'].toString(),
        'quantity': item['quantity'] as int,
        'salePrice': (item['salePrice'] as num).toDouble(),
        'listPrice': ((item['listPrice'] ?? item['salePrice']) as num).toDouble(),
      }).toList();

      final payload = {'items': priceItems};

      final response = await _client.post(
        Uri.parse(url),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw TrendyolAPIException(
          'Güncelleme hatası: ${response.statusCode} - ${response.body.substring(0, 500)}',
        );
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw TrendyolAPIException('Güncelleme hatası: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
