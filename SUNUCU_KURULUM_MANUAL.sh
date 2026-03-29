#!/bin/bash

# Sunucu Kurulum - Manuel Adımlar
# Bu dosya sunucu kurulumunun manuel olarak yapılması gerektiğini gösterir.

cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║         OTA GÜNCELLEME SİSTEMİ - SUNUCU KURULUM KILAVUZU       ║
╚════════════════════════════════════════════════════════════════╝

ÖNEMLİ: SSH bağlantısı nedeniyle bu kurulum manuel olarak yapılmalıdır.

SUNUCU BİLGİLERİ:
─────────────────────────────────────────────────────────────────
IP Adresi:        37.247.99.103
Kullanıcı:        administrator
Şifre:            6M879USAxQSm
Protocol:         HTTP (HTTPS'ye geçilebilir)
Sunucu Türü:      Apache + PHP

ADIM 1: SSH Bağlantısı
─────────────────────────────────────────────────────────────────
Terminalde çalıştırın:
$ ssh administrator@37.247.99.103

Şifreyi sorduğunda girin: 6M879USAxQSm

ADIM 2: Klasör Yapısını Oluştur
─────────────────────────────────────────────────────────────────
$ sudo mkdir -p /var/www/html/updates/zeyder_fiyat
$ sudo mkdir -p /var/www/html/updates/zeyder_stok

ADIM 3: İzinleri Ayarla
─────────────────────────────────────────────────────────────────
$ sudo chown -R www-data:www-data /var/www/html/updates
$ sudo chmod -R 755 /var/www/html/updates

ADIM 4: Basic Authentication Ayarla (Opsiyonel)
─────────────────────────────────────────────────────────────────
$ sudo htpasswd -bc /etc/apache2/.htpasswd admin 6M879USAxQSm

ADIM 5: .htaccess Dosyası Oluştur
─────────────────────────────────────────────────────────────────
$ sudo nano /var/www/html/updates/.htaccess

Aşağıdaki kodu yapıştırın:
───────────────────────────────
AuthType Basic
AuthName "OTA Update Server"
AuthUserFile /etc/apache2/.htpasswd
Require valid-user
───────────────────────────────

Kaydet: Ctrl+X, Y, Enter

ADIM 6: Apache Modüllerini Aktifleştir
─────────────────────────────────────────────────────────────────
$ sudo a2enmod auth_basic
$ sudo a2enmod authn_file

ADIM 7: Apache'yi Yeniden Başlat
─────────────────────────────────────────────────────────────────
$ sudo systemctl restart apache2

Veya:
$ sudo service apache2 restart

ADIM 8: Kurulumu Kontrol Et
─────────────────────────────────────────────────────────────────
$ curl -u admin:6M879USAxQSm http://37.247.99.103/updates/

Çıktı:
  zeyder_fiyat/
  zeyder_stok/
  .htaccess

olmalıdır.

ADIM 9: Version.json Dosyasını Oluştur
─────────────────────────────────────────────────────────────────
Lokal makinanızda:

zeyder_fiyat için:
$ cat > version.json << 'EOFJ'
{
  "version": "1.0.0",
  "buildNumber": 1,
  "downloadUrl": "http://37.247.99.103/updates/zeyder_fiyat/zeyder_fiyat_v1.0.0.apk",
  "forceUpdate": false,
  "changelog": "İlk sürüm"
}
EOFJ

Sunucuya upload edin:
$ scp version.json administrator@37.247.99.103:/var/www/html/updates/zeyder_fiyat/

ADIM 10: APK Dosyasını Upload Et
─────────────────────────────────────────────────────────────────
APK oluşturduktan sonra:

$ scp app-release.apk administrator@37.247.99.103:/var/www/html/updates/zeyder_fiyat/zeyder_fiyat_v1.0.0.apk

ADIM 11: İzinleri Tekrar Kontrol Et
─────────────────────────────────────────────────────────────────
$ sudo chown -R www-data:www-data /var/www/html/updates
$ sudo chmod -R 755 /var/www/html/updates

TAMAMLAMA KONTROL LİSTESİ:
═════════════════════════════════════════════════════════════════
☐ SSH bağlantısı sağlandı
☐ /var/www/html/updates/ klasörü oluşturuldu
☐ zeyder_fiyat/ klasörü oluşturuldu
☐ zeyder_stok/ klasörü oluşturuldu
☐ İzinler ayarlandı (755, www-data)
☐ Basic Auth password file oluşturuldu
☐ .htaccess dosyası oluşturuldu
☐ Apache modülleri aktifleştirildi (auth_basic, authn_file)
☐ Apache yeniden başlatıldı
☐ Version.json dosyaları oluşturuldu
☐ APK dosyaları upload edildi
☐ Sunucu erişimi curl ile test edildi

HATA GIDERME:
═════════════════════════════════════════════════════════════════

1. "Permission denied" hatası:
   → Sudo ile komutu çalıştır veya root olarak oturum aç

2. "htpasswd: command not found":
   → $ sudo apt-get install apache2-utils

3. "Module not found":
   → a2enmod komutuyla modülü aktifleştir

4. Apache restart başarısız:
   → $ sudo systemctl status apache2
   → Hata loglarını kontrol et: $ sudo tail -f /var/log/apache2/error.log

5. Dosya indirme sırasında 401 Unauthorized:
   → Basic Auth hesabının doğru olduğunu kontrol et
   → curl -u admin:6M879USAxQSm http://37.247.99.103/updates/version.json

6. APK yükleme başarısız:
   → Dosya dizininin www-data'ya ait olduğunu kontrol et
   → chmod 644 *.apk ile dosya izinlerini ayarla

NOTLAR:
═════════════════════════════════════════════════════════════════
• Tüm dosyaların www-data kullanıcısına ait olması gerekir
• Klasör izinleri 755, dosya izinleri 644 olmalıdır
• HTTPS geçişi için SSL sertifikası ve Apache konfigürasyonu gereklidir
• Şifreyi güvenli bir yerde saklayın

EOF
