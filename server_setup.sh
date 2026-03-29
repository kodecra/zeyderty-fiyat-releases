#!/bin/bash

# OTA Güncelleme Sunucusu Kurulum Script'i
# Sunucu: 37.247.99.103
# User: administrator

echo "=========================================="
echo "OTA Güncelleme Sunucusu Kurulumu"
echo "=========================================="

# 1. Updates klasörünü oluştur
echo "1. Updates klasörü oluşturuluyor..."
mkdir -p /var/www/html/updates
cd /var/www/html/updates

# 2. Uygulama klasörlerini oluştur
echo "2. Uygulama klasörleri oluşturuluyor..."
mkdir -p zeyder_fiyat
mkdir -p zeyder_stok

# 3. Apache izinlerini ayarla
echo "3. Apache izinleri ayarlanıyor..."
chown -R www-data:www-data /var/www/html/updates
chmod -R 755 /var/www/html/updates

# 4. .htaccess ile Basic Auth oluştur (opsiyonel)
echo "4. Basic Auth yapılandırması..."
cat > /var/www/html/updates/.htaccess << 'EOF'
AuthType Basic
AuthName "OTA Update Server"
AuthUserFile /etc/apache2/.htpasswd
Require valid-user
EOF

# 5. Kullanıcı oluştur (şifre: 6M879USAxQSm)
echo "5. Admin kullanıcısı oluşturuluyor..."
htpasswd -bc /etc/apache2/.htpasswd admin 6M879USAxQSm

# 6. Apache modülünü aktifleştir
echo "6. Apache modülleri aktifleştiriliyor..."
a2enmod auth_basic
a2enmod authn_file

# 7. Apache'yi yeniden başlat
echo "7. Apache yeniden başlatılıyor..."
systemctl restart apache2

echo ""
echo "=========================================="
echo "Kurulum Tamamlandı!"
echo "=========================================="
echo ""
echo "Klasör yapısı:"
echo "/var/www/html/updates/"
echo "├── zeyder_fiyat/"
echo "│   └── version.json"
echo "├── zeyder_stok/"
echo "│   └── version.json"
echo "└── .htaccess"
echo ""
echo "Sonraki adımlar:"
echo "1. Uygulamalar için version.json dosyalarını oluşturun"
echo "2. APK dosyalarını ilgili klasörlere yükleyin"
echo "3. Test edin"
echo ""
