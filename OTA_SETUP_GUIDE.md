# OTA (Over-The-Air) Güncelleme Sistemi

Bu belge, Flutter uygulamalarına OTA güncelleme sistemi kurulum ve kullanım talimatlarını içerir.

## 📋 Genel Bakış

OTA güncelleme sistemi, sunucudan indirilen APK dosyalarıyla uygulamaları güncellemek için tasarlanmıştır. Sistem şunları sağlar:

- ✅ Otomatik versiyon kontrolü
- ✅ Güncelleme bildirim dialogu
- ✅ APK indirme ve yükleme
- ✅ Zorunlu/opsiyonel güncelleme seçeneği
- ✅ Değişiklik günlüğü (changelog) gösterimi

## 🖥️ Sunucu Kurulumu

### Bilgiler
- **IP**: 37.247.99.103
- **Kullanıcı**: administrator
- **Şifre**: 6M879USAxQSm
- **Protocol**: HTTP (HTTP'ye geçirilebilir)

### 1. SSH Bağlantısı
```bash
ssh administrator@37.247.99.103
```

### 2. Otomatik Kurulum
Kurulum script'ini çalıştırın:
```bash
bash server_setup.sh
```

Bu script otomatik olarak:
- `/var/www/html/updates/` klasörünü oluşturur
- `zeyder_fiyat/` ve `zeyder_stok/` alt klasörlerini oluşturur
- Apache Basic Auth'u ayarlar
- Apache modüllerini aktifleştiri

### 3. Manuel Kurulum (Opsiyonel)

```bash
# Klasörleri oluştur
mkdir -p /var/www/html/updates/zeyder_fiyat
mkdir -p /var/www/html/updates/zeyder_stok

# İzinleri ayarla
chown -R www-data:www-data /var/www/html/updates
chmod -R 755 /var/www/html/updates

# Basic Auth password file'ını oluştur
htpasswd -bc /etc/apache2/.htpasswd admin 6M879USAxQSm

# .htaccess dosyası oluştur
cat > /var/www/html/updates/.htaccess << 'EOF'
AuthType Basic
AuthName "OTA Update Server"
AuthUserFile /etc/apache2/.htpasswd
Require valid-user
EOF

# Apache modüllerini aktifleştir ve yeniden başlat
a2enmod auth_basic authn_file
systemctl restart apache2
```

## 📱 Flutter Uygulaması Kurulumu

### 1. pubspec.yaml'a Bağımlılıklar Ekleme

Gerekli paketler otomatik olarak `pubspec.yaml`'a eklenmiştir:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  http: ^1.6.0
  shared_preferences: ^2.5.3
  cached_network_image: ^3.4.1
  google_fonts: ^6.2.1
  open_file: ^3.0.0        # APK açmak için
  path_provider: ^2.1.0    # Dosya yolları
  dio: ^5.3.0              # HTTP indirme
  package_info_plus: ^8.0.0 # Versiyon bilgisi
```

Paketleri yüklemek için:
```bash
flutter pub get
```

### 2. AndroidManifest.xml İzinleri

Gerekli izinler otomatik olarak eklenmiştir:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
```

### 3. Versiyon Bilgisi Ayarlama

`pubspec.yaml`'da versiyon belirleyin:
```yaml
version: 1.0.0+1
```

Formatı: `major.minor.patch+buildNumber`
- `1.0.0` = version string
- `1` = build number (her güncelleme için artırılır)

### 4. main.dart'ı Güncelleme

`update_checker.dart` otomatik olarak `main.dart`'a entegre edilmiştir. Uygulama başladığında:

1. Güncelleme kontrolü yapılır
2. 24 saatte bir kontrol sınırlandırılır
3. Yeni versiyon varsa dialog gösterilir

## 🚀 Kullanım

### APK Upload Etme

Upload script'ini kullanarak APK dosyasını yükleyin:

```bash
bash upload_apk.sh zeyder_fiyat 1.0.1 app/build/outputs/flutter-apk/app-release.apk
```

Veya ikinci uygulama için:
```bash
bash upload_apk.sh zeyder_stok 1.0.1 app/build/outputs/flutter-apk/app-release.apk
```

### Version.json Dosyası

Her uygulama için `version.json` dosyası gereklidir. Örnek yapı:

```json
{
  "version": "1.0.1",
  "buildNumber": 2,
  "downloadUrl": "http://37.247.99.103/updates/zeyder_fiyat/zeyder_fiyat_v1.0.1.apk",
  "forceUpdate": false,
  "changelog": "• Yeni özellikler eklendi\n• Hata düzeltmeleri yapıldı\n• Performans iyileştirmeleri"
}
```

**Parametre Açıklamaları:**
- `version`: Uygulama versiyon numarası (pubspec.yaml'daki version)
- `buildNumber`: Build numarası (pubspec.yaml'daki +)
- `downloadUrl`: APK'nin download URL'i
- `forceUpdate`: `true` ise güncelleme zorunlu (yapma butonu olmaz)
- `changelog`: Değişiklikleri açıklayan metin

### Güncelleme Kontrol Kodunun Özelleştirilmesi

Her uygulama için `update_checker.dart`'da `_appName` değişkenini değiştirin:

```dart
// zeyder_fiyat için
static const String _appName = 'zeyder_fiyat';

// zeyder_stok için (ayrı dosya)
static const String _appName = 'zeyder_stok';
```

## 📝 APK Build Etme

### Release APK

```bash
flutter build apk --release
```

APK şurada bulunur:
```
app/build/outputs/flutter-apk/app-release.apk
```

### Build Number Artırma

Her yeni sürümde `pubspec.yaml`'da build number'ı artırın:

```yaml
# Eski
version: 1.0.0+1

# Yeni
version: 1.0.1+2
```

## 🧪 Test

### 1. Sunucu Kontrolü

Version.json'ın erişilebilir olduğunu kontrol edin:

```bash
# İzinsiz
curl http://37.247.99.103/updates/zeyder_fiyat/version.json

# Basic Auth ile
curl -u admin:6M879USAxQSm http://37.247.99.103/updates/zeyder_fiyat/version.json
```

### 2. Uygulama Testi

1. Eski versiyon APK'sını yükleyin
2. Sunucuya yeni `version.json` ve APK yükleyin
3. Uygulamayı açın
4. Güncelleme bildirimi göründüğünü kontrol edin
5. "Güncelle" butonuna basın
6. APK'nin indirilip yüklendiğini kontrol edin

### 3. Zorunlu Güncelleme Testi

`version.json`'da `forceUpdate`'u `true` yapın:

```json
{
  "version": "1.0.1",
  "buildNumber": 2,
  "downloadUrl": "...",
  "forceUpdate": true,
  "changelog": "..."
}
```

Uygulamayı açın ve "Daha Sonra" butonunun görünmediğini kontrol edin.

## 📂 Klasör Yapısı

Sunucu:
```
/var/www/html/updates/
├── zeyder_fiyat/
│   ├── version.json
│   └── zeyder_fiyat_v1.0.1.apk
├── zeyder_stok/
│   ├── version.json
│   └── zeyder_stok_v1.0.1.apk
└── .htaccess
```

Proje:
```
lib/
├── main.dart                    # Güncelleme kontrolü entegre
├── update_checker.dart          # OTA mantığı
├── products_page.dart
├── settings_page.dart
└── ...

pubspec.yaml                      # Paketler ve versiyon
android/
└── app/src/main/
    └── AndroidManifest.xml       # İzinler
```

## 🔐 Güvenlik (HTTPS Migrasyonu)

Gelecekte HTTPS'ye geçmek için:

1. SSL sertifikası edinin (Let's Encrypt)
2. Apache'de HTTPS'yi yapılandırın
3. `update_checker.dart`'da URL'yi güncelleyin:

```dart
// HTTP'den
static const String _serverUrl = 'http://37.247.99.103/updates';

// HTTPS'ye
static const String _serverUrl = 'https://37.247.99.103/updates';
```

## 🐛 Sorun Giderme

### Güncelleme Dialogu Görmüyorum

1. Build number'ı kontrol edin (artmış mı?)
2. 24 saate kadar bekleme süresi olabilir (test için `shouldCheckForUpdate()`'ı değiştirin)
3. Logları kontrol edin

### APK İndirilemiyor

1. URL'nin erişilebilir olduğunu kontrol edin
2. İnternet izinlerini kontrol edin
3. Sunucuda dosyanın varlığını kontrol edin

### "Hata: APK yüklenemedi" Mesajı

1. Android sürümü 31+ ise `REQUEST_INSTALL_PACKAGES` izni gereklidir
2. APK dosyasının bozuk olmadığını kontrol edin
3. Cihaz depolamasında yer olduğundan emin olun

## 📞 Kaynaklar

- [Flutter package_info_plus](https://pub.dev/packages/package_info_plus)
- [Flutter open_file](https://pub.dev/packages/open_file)
- [Flutter dio](https://pub.dev/packages/dio)
- [Android Permissions](https://developer.android.com/training/permissions)

## 📋 Kontrol Listesi

- [ ] Sunucu kurulumu tamamlandı
- [ ] Basic Auth ayarlandı
- [ ] pubspec.yaml paketleri yüklendi (`flutter pub get`)
- [ ] AndroidManifest.xml izinleri kontrol edildi
- [ ] Versiyon numarası set edildi
- [ ] Test APK'sı upload edildi
- [ ] version.json sunucuya yüklendi
- [ ] Eski versiyon APK'sı yüklenerek test edildi
- [ ] Güncelleme bildirimi göründü
- [ ] APK başarıyla indirilip kuruldu

---

**Son güncelleme**: 29 Mart 2026
**Sistem Versiyonu**: 1.0
