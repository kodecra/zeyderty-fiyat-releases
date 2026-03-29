# GitHub OTA Güncelleme Sistemi - Adım Adım Kurulum

## 📋 Gerekli Bilgiler

1. GitHub hesabınız (github.com)
2. Personal Access Token (oluşturacağız)
3. Private repository (oluşturacağız)

---

## 🔧 Adım 1: GitHub Personal Access Token Oluştur

1. GitHub'da oturum açın: https://github.com
2. Sağ üst köşeden profil resminize tıklayın
3. **Settings** > **Developer settings** > **Personal access tokens** > **Tokens (classic)**
4. **Generate new token (classic)** butonuna tıklayın
5. Token adı: `ZeyderTY OTA Updates`
6. Permissions (şunları seçin):
   - ✅ `repo` (tüm repo yetkisi)
   - ✅ `read:org` (optional)
7. **Generate token** butonuna tıklayın
8. ⚠️ **Token'ı HEMEN KAYDET** - bir daha göremezsiniz!
   - Örnek token: `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxx`

---

## 🔧 Adım 2: Private Repository Oluştur

1. GitHub ana sayfada, sağ üstte **+** > **New repository**
2. Repository bilgileri:
   - **Repository name**: `zeyderty-fiyat-releases`
   - **Description**: `ZeyderTY Fiyat uygulama güncellemeleri`
   - **Visibility**: ✅ **Private** (önemli!)
   - **Initialize**: README ekleyebilirsiniz (optional)
3. **Create repository** butonuna tıklayın

---

## 🔧 Adım 3: İlk Release Oluştur

1. Oluşturduğunuz repo sayfasında, sağ tarafta **Releases** > **Create a new release**
2. Release bilgileri:
   - **Tag version**: `v1.0.0` (küçük harfle v zorunlu)
   - **Release title**: `ZeyderTY Fiyat v1.0.0`
   - **Description**: 
     ```
     ## Değişiklikler
     - İlk sürüm yayınlandı
     - Tüm temel özellikler eklendi
     - OTA güncelleme sistemi aktif
     ```
3. **Attach binaries**: APK dosyanızı buraya sürükleyin
   - Dosya adı: `ZeyderTY-Fiyat-v1.0.0.apk`
4. **Publish release** butonuna tıklayın

---

## 🔧 Adım 4: Repo Bilgilerini Bana Verin

Şunları söyleyin:
1. GitHub kullanıcı adınız: `________________`
2. Repository adı: `zeyderty-fiyat-releases` (veya başka)
3. Personal Access Token: `ghp_________________`

Bu bilgilerle update_checker.dart dosyasını güncelleyeceğim!

---

## 🎯 Sonraki Adımlar (Ben Yapacağım)

1. `lib/update_checker.dart` dosyasını GitHub API için düzenleyeceğim
2. Repository ve token bilgilerini ekleyeceğim
3. Yeni APK build alacağız
4. Test edip çalıştığını doğrulayacağız

---

## 📱 Kullanım (Siz)

### Yeni Versiyon Yayınlarken:

1. Flutter projede version değiştirin:
   ```yaml
   # pubspec.yaml
   version: 1.0.1+2  # Versiyon artırın
   ```

2. APK build alın:
   ```bash
   flutter build apk --release
   ```

3. GitHub'da yeni release oluşturun:
   - Tag: `v1.0.1`
   - Title: `ZeyderTY Fiyat v1.0.1`
   - Description: Değişiklikleri yazın
   - APK'yı yükleyin

4. Kullanıcılar uygulamayı açtığında otomatik güncelleme bildirimi görecek!

---

## 🔒 Güvenlik

- ✅ Repository private - Sadece siz erişebilirsiniz
- ✅ Token güvenli - Kimse göremez
- ✅ APK imzalı - Orijinal uygulama doğrulanır

---

## ❓ Sorun Giderme

**Token çalışmıyor:**
- Token'ın `repo` yetkisi var mı kontrol edin
- Token'ı doğru kopyaladığınızdan emin olun

**Release görünmüyor:**
- Repository private mı kontrol edin
- Tag formatı doğru mu? (örn: `v1.0.0`)

**APK indirilmiyor:**
- İnternet bağlantısı var mı?
- APK boyutu çok büyük değil mi?

---

Hazır olduğunuzda bilgileri paylaşın!
