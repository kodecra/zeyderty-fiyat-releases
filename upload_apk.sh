#!/bin/bash

# APK Upload Script'i
# Kullanım: ./upload_apk.sh <uygulama_adi> <versiyon> <apk_dosyasi>

if [ $# -ne 3 ]; then
    echo "Kullanım: $0 <uygulama_adi> <versiyon> <apk_dosyasi>"
    echo ""
    echo "Örnek:"
    echo "  $0 zeyder_fiyat 1.0.1 app-release.apk"
    echo "  $0 zeyder_stok 1.0.1 app-release.apk"
    exit 1
fi

APP_NAME=$1
VERSION=$2
APK_FILE=$3
SERVER="administrator@37.247.99.103"
REMOTE_DIR="/var/www/html/updates"

# APK dosyasının varlığını kontrol et
if [ ! -f "$APK_FILE" ]; then
    echo "HATA: APK dosyası bulunamadı: $APK_FILE"
    exit 1
fi

echo "=========================================="
echo "APK Upload İşlemi"
echo "=========================================="
echo "Uygulama: $APP_NAME"
echo "Versiyon: $VERSION"
echo "APK Dosyası: $APK_FILE"
echo ""

# APK dosyasını yükle
echo "1. APK dosyası yükleniyor..."
scp "$APK_FILE" "$SERVER:$REMOTE_DIR/$APP_NAME/${APP_NAME}_v${VERSION}.apk"

if [ $? -ne 0 ]; then
    echo "HATA: APK upload başarısız!"
    exit 1
fi

echo "✓ APK yüklendi"
echo ""

# version.json dosyasını oluştur
echo "2. version.json oluşturuluyor..."
cat > /tmp/version.json << EOF
{
  "version": "$VERSION",
  "buildNumber": $(echo $VERSION | tr -d '.' | sed 's/^0*//'),
  "downloadUrl": "http://37.247.99.103/updates/$APP_NAME/${APP_NAME}_v${VERSION}.apk",
  "forceUpdate": false,
  "changelog": "• Versiyon $VERSION güncellemesi\n• Yeni özellikler ve hata düzeltmeleri"
}
EOF

# version.json dosyasını yükle
echo "3. version.json yükleniyor..."
scp /tmp/version.json "$SERVER:$REMOTE_DIR/$APP_NAME/version.json"

if [ $? -ne 0 ]; then
    echo "HATA: version.json upload başarısız!"
    exit 1
fi

echo "✓ version.json yüklendi"
echo ""

# Geçici dosyayı temizle
rm -f /tmp/version.json

echo "=========================================="
echo "Upload Tamamlandı!"
echo "=========================================="
echo ""
echo "URL'ler:"
echo "  APK: http://37.247.99.103/updates/$APP_NAME/${APP_NAME}_v${VERSION}.apk"
echo "  Version: http://37.247.99.103/updates/$APP_NAME/version.json"
echo ""
echo "Test etmek için:"
echo "  curl -u admin:6M879USAxQSm http://37.247.99.103/updates/$APP_NAME/version.json"
echo ""
