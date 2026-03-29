import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// GitHub Releases ile OTA Güncelleme Kontrol Servisi
/// 
/// Bu servis, GitHub Releases API'sini kullanarak
/// güncelleme kontrolü yapar ve APK indirme/yükleme işlemini yönetir.
class UpdateChecker {
  // GitHub konfigürasyonu
  static const String _githubToken = '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';
  static const String _repoOwner = 'kodecra';
  static const String _repoName = 'zeyderty-fiyat-releases';
  static const String _githubApiBaseUrl = 'https://api.github.com';
  
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $_githubToken',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ),
  );
  
  /// Versiyon kontrolü yapar ve güncelleme varsa dialog gösterir
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      // 24 saatlik kontrol aralığı - eğer gerekli değilse kontrol etme
      if (!await shouldCheckForUpdate()) {
        debugPrint('Son kontrol 24 saatten az bir süre önce yapıldı, kontrol atlanıyor.');
        return;
      }
      
      // Mevcut versiyonu al
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;
      
      debugPrint('Mevcut versiyon: $currentVersion (build: $currentBuildNumber)');
      
      // GitHub Releases API'den son sürümü çek
      final latestRelease = await _getLatestRelease();
      
      if (latestRelease == null) {
        debugPrint('GitHub\'dan release bilgisi alınamadı.');
        return;
      }
      
      // Release bilgilerini parse et
      final tagName = latestRelease['tag_name'] as String;
      final releaseName = latestRelease['name'] as String? ?? tagName;
      final body = latestRelease['body'] as String? ?? 'Yeni özellikler ve hata düzeltmeleri.';
      final assets = latestRelease['assets'] as List;
      
      // Tag'den versiyon numarasını çıkar (örn: v1.0.1 -> 1.0.1)
      final latestVersion = tagName.replaceFirst('v', '');
      
      // Build number'ı parse et (örn: 1.0.1+2 formatında olabilir)
      int latestBuildNumber = 1;
      if (latestVersion.contains('+')) {
        final parts = latestVersion.split('+');
        latestBuildNumber = int.tryParse(parts[1]) ?? 1;
      } else {
        // Eğer + yoksa version numarasından build number oluştur
        final versionParts = latestVersion.split('.');
        if (versionParts.length == 3) {
          latestBuildNumber = int.tryParse(versionParts[2]) ?? 1;
        }
      }
      
      debugPrint('Son release: $latestVersion (build: $latestBuildNumber)');
      
      // APK asset'ini bul
      String? apkDownloadUrl;
      for (var asset in assets) {
        final assetName = asset['name'] as String;
        if (assetName.toLowerCase().endsWith('.apk')) {
          apkDownloadUrl = asset['browser_download_url'] as String;
          debugPrint('APK bulundu: $assetName');
          break;
        }
      }
      
      if (apkDownloadUrl == null) {
        debugPrint('Release\'de APK dosyası bulunamadı.');
        return;
      }
      
      // Versiyon karşılaştırması
      if (latestBuildNumber > currentBuildNumber) {
        debugPrint('Yeni versiyon mevcut! Güncelleme dialog\'u gösteriliyor.');
        
        // Son kontrol zamanını kaydet
        await _saveLastCheckTime();
        
        // Güncelleme var, dialog göster
        if (context.mounted) {
          _showUpdateDialog(
            context,
            currentVersion,
            latestVersion,
            releaseName,
            body,
            apkDownloadUrl,
            false, // GitHub releases'da force update bilgisi olmadığı için false
          );
        }
      } else {
        debugPrint('Uygulama güncel durumda.');
        // Son kontrol zamanını kaydet
        await _saveLastCheckTime();
      }
    } catch (e, stackTrace) {
      // Hata durumunda sessizce geç (uygulamanın normal çalışmasını engelleme)
      debugPrint('Güncelleme kontrolü hatası: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }
  
  /// GitHub'dan en son release'i çeker
  static Future<Map<String, dynamic>?> _getLatestRelease() async {
    try {
      final url = '$_githubApiBaseUrl/repos/$_repoOwner/$_repoName/releases/latest';
      debugPrint('GitHub API çağrısı yapılıyor: $url');
      
      final response = await _dio.get(url);
      
      if (response.statusCode == 200) {
        debugPrint('GitHub API başarılı yanıt verdi.');
        return response.data as Map<String, dynamic>;
      } else {
        debugPrint('GitHub API hata döndü: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('GitHub API hatası: $e');
      return null;
    }
  }
  
  /// Güncelleme dialog'unu gösterir
  static void _showUpdateDialog(
    BuildContext context,
    String currentVersion,
    String latestVersion,
    String releaseName,
    String changelog,
    String downloadUrl,
    bool forceUpdate,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (context) => PopScope(
        canPop: !forceUpdate,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.system_update_alt,
                color: Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  releaseName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mevcut: $currentVersion → Yeni: $latestVersion',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Yenilikler:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  changelog,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (forceUpdate) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bu güncelleme zorunludur.',
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!forceUpdate)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Daha Sonra',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _downloadAndInstallApk(context, downloadUrl, forceUpdate);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Güncelle',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// APK indirir ve yükler
  static Future<void> _downloadAndInstallApk(
    BuildContext context,
    String downloadUrl,
    bool forceUpdate,
  ) async {
    // İndirme progress değişkeni
    double downloadProgress = 0.0;
    
    // İndirme dialog'u göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    value: downloadProgress > 0 ? downloadProgress / 100 : null,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Güncelleme indiriliyor...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    downloadProgress > 0 
                        ? '${downloadProgress.toStringAsFixed(0)}%'
                        : 'Lütfen bekleyin',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    
    try {
      // İndirme dizinini al
      final directory = await getTemporaryDirectory();
      final apkPath = '${directory.path}/update_${DateTime.now().millisecondsSinceEpoch}.apk';
      
      debugPrint('APK indiriliyor: $downloadUrl');
      debugPrint('İndirme yolu: $apkPath');
      
      // APK indir - GitHub için public URL olduğundan token gereksiz
      await _dio.download(
        downloadUrl,
        apkPath,
        options: Options(
          headers: {
            'Accept': 'application/octet-stream',
          },
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            downloadProgress = (received / total * 100);
            debugPrint('İndirme ilerlemesi: ${downloadProgress.toStringAsFixed(0)}%');
          }
        },
      );
      
      debugPrint('APK başarıyla indirildi: $apkPath');
      
      // Dialog'u kapat
      if (context.mounted) {
        Navigator.pop(context);
      }
      
      // Dosyanın varlığını kontrol et
      final file = File(apkPath);
      if (!await file.exists()) {
        throw Exception('APK dosyası bulunamadı');
      }
      
      final fileSize = await file.length();
      debugPrint('APK dosya boyutu: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // APK'yı aç ve yükle
      debugPrint('APK yükleniyor...');
      final result = await OpenFile.open(apkPath);
      
      if (result.type == ResultType.done) {
        debugPrint('APK yükleme başarılı');
      } else if (result.type == ResultType.error) {
        debugPrint('APK yükleme hatası: ${result.message}');
        if (context.mounted) {
          _showErrorDialog(
            context,
            'APK yüklenemedi: ${result.message}\n\nLütfen manuel olarak yüklemeyi deneyin.',
          );
        }
      } else {
        debugPrint('APK yükleme durumu: ${result.type}');
      }
    } catch (e, stackTrace) {
      debugPrint('APK indirme/yükleme hatası: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // Hata durumunda dialog'u kapat ve hata göster
      if (context.mounted) {
        Navigator.pop(context);
        _showErrorDialog(
          context,
          'İndirme başarısız: ${e.toString()}',
        );
      }
    }
  }
  
  /// Hata dialog'u gösterir
  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 28,
            ),
            SizedBox(width: 12),
            Text(
              'Hata',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Tamam',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Son güncelleme kontrol zamanını kaydeder
  static Future<void> _saveLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_update_check', DateTime.now().millisecondsSinceEpoch);
    debugPrint('Son kontrol zamanı kaydedildi: ${DateTime.now()}');
  }
  
  /// Son güncelleme kontrol zamanını alır
  static Future<DateTime?> getLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('last_update_check');
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }
  
  /// Güncelleme kontrolü yapılması gerekip gerekmediğini kontrol eder
  /// (24 saatlik kontrol aralığı)
  static Future<bool> shouldCheckForUpdate() async {
    final lastCheck = await getLastCheckTime();
    if (lastCheck == null) return true;
    
    final now = DateTime.now();
    final difference = now.difference(lastCheck);
    
    // 24 saatten fazla zaman geçmişse kontrol yap
    return difference.inHours >= 24;
  }
  
  /// Manuel güncelleme kontrolü (Ayarlar sayfası için)
  static Future<void> checkForUpdateManually(BuildContext context) async {
    // Loading dialog göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    try {
      // Mevcut versiyonu al
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;
      
      // GitHub'dan son sürümü çek
      final latestRelease = await _getLatestRelease();
      
      if (context.mounted) {
        Navigator.pop(context); // Loading dialog'u kapat
      }
      
      if (latestRelease == null) {
        if (context.mounted) {
          _showErrorDialog(context, 'GitHub\'dan versiyon bilgisi alınamadı.');
        }
        return;
      }
      
      // Release bilgilerini parse et
      final tagName = latestRelease['tag_name'] as String;
      final releaseName = latestRelease['name'] as String? ?? tagName;
      final body = latestRelease['body'] as String? ?? 'Yeni özellikler ve hata düzeltmeleri.';
      final assets = latestRelease['assets'] as List;
      
      final latestVersion = tagName.replaceFirst('v', '');
      int latestBuildNumber = 1;
      if (latestVersion.contains('+')) {
        final parts = latestVersion.split('+');
        latestBuildNumber = int.tryParse(parts[1]) ?? 1;
      } else {
        final versionParts = latestVersion.split('.');
        if (versionParts.length == 3) {
          latestBuildNumber = int.tryParse(versionParts[2]) ?? 1;
        }
      }
      
      // APK asset'ini bul
      String? apkDownloadUrl;
      for (var asset in assets) {
        final assetName = asset['name'] as String;
        if (assetName.toLowerCase().endsWith('.apk')) {
          apkDownloadUrl = asset['browser_download_url'] as String;
          break;
        }
      }
      
      if (apkDownloadUrl == null) {
        if (context.mounted) {
          _showErrorDialog(context, 'Release\'de APK dosyası bulunamadı.');
        }
        return;
      }
      
      // Versiyon karşılaştırması
      if (latestBuildNumber > currentBuildNumber) {
        if (context.mounted) {
          _showUpdateDialog(
            context,
            currentVersion,
            latestVersion,
            releaseName,
            body,
            apkDownloadUrl,
            false,
          );
        }
      } else {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Güncel Durumda',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: Text(
                'Uygulamanız zaten güncel durumda.\n\nMevcut versiyon: $currentVersion',
                style: const TextStyle(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Tamam',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Loading dialog'u kapat
        _showErrorDialog(context, 'Güncelleme kontrolü başarısız: ${e.toString()}');
      }
    }
  }
}
