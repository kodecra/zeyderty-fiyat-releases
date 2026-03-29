/// Trendyol kar-zarar hesaplama motoru
/// Tüm fiyatlar KDV DAHİL girilmelidir
class TrendyolCalculator {
  // Kargo, komisyon ve hizmet bedeli üzerindeki KDV oranı (%20)
  static const double kargoKdvOrani = 20.0;
  static const double komisyonKdvOrani = 20.0;
  static const double hizmetKdvOrani = 20.0;

  /// Tüm maliyet ve kâr değerlerini hesaplar
  static Map<String, double> calculate({
    required double satisFiyati,
    required double alisFiyati,
    required double komisyonOrani,
    required double kdvOrani,
    required double kargoUcreti,
    required double stopajOrani,
    required double hizmetBedeli,
  }) {
    if (satisFiyati <= 0) {
      return _emptyResult();
    }

    final kdvMultiplier = kdvOrani / (100.0 + kdvOrani);

    // Ana hesaplamalar
    final komisyon = satisFiyati * (komisyonOrani / 100.0);

    // Stopaj: Satış (KDV hariç) × stopajOrani
    final satisKdvsiz = satisFiyati / (1.0 + kdvOrani / 100.0);
    final stopaj = satisKdvsiz * (stopajOrani / 100.0);

    // Kâr = Satış - Alış - Komisyon - Kargo - Stopaj - Hizmet
    final kar = satisFiyati - alisFiyati - komisyon - kargoUcreti - stopaj - hizmetBedeli;

    final karOrani = alisFiyati > 0 ? (kar / alisFiyati * 100.0) : 0.0;
    final yatirimGeriDonus = satisFiyati > 0 ? (kar / satisFiyati * 100.0) : 0.0;

    // KDV Hesaplamaları
    final satisKdv = satisFiyati * kdvMultiplier;
    final alisKdv = alisFiyati * kdvMultiplier;

    final kargoKdvMult = kargoKdvOrani / (100.0 + kargoKdvOrani);
    final komisyonKdvMult = komisyonKdvOrani / (100.0 + komisyonKdvOrani);
    final hizmetKdvMult = hizmetKdvOrani / (100.0 + hizmetKdvOrani);

    final kargoKdv = kargoUcreti * kargoKdvMult;
    final komisyonKdv = komisyon * komisyonKdvMult;
    final hizmetKdv = hizmetBedeli * hizmetKdvMult;

    final odenecekKdv = satisKdv - alisKdv - kargoKdv - komisyonKdv - hizmetKdv;

    return {
      'komisyon': _round(komisyon),
      'stopaj': _round(stopaj),
      'hizmet_bedeli': _round(hizmetBedeli),
      'kar': _round(kar),
      'kar_orani': _round(karOrani),
      'yatirim_geri_donus': _round(yatirimGeriDonus),
      'satis_kdv': _round(satisKdv),
      'alis_kdv': _round(alisKdv),
      'kargo_kdv': _round(kargoKdv),
      'komisyon_kdv': _round(komisyonKdv),
      'hizmet_kdv': _round(hizmetKdv),
      'odenecek_kdv': _round(odenecekKdv),
    };
  }

  static Map<String, double> _emptyResult() {
    const keys = [
      'komisyon',
      'stopaj',
      'hizmet_bedeli',
      'kar',
      'kar_orani',
      'yatirim_geri_donus',
      'satis_kdv',
      'alis_kdv',
      'kargo_kdv',
      'komisyon_kdv',
      'hizmet_kdv',
      'odenecek_kdv',
    ];
    return Map.fromIterable(keys, key: (k) => k as String, value: (_) => 0.0);
  }

  static double _round(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  /// Hedef kâr oranına göre önerilen satış fiyatını hesaplar
  /// Hedef kâr oranı ALIŞ FİYATI üzerinden hesaplanır (Kâr/Alış×100)
  static double suggestPrice({
    required double alisFiyati,
    required double komisyonOrani,
    required double kdvOrani,
    required double kargoUcreti,
    required double stopajOrani,
    required double hizmetBedeli,
    required double hedefKarOrani,
  }) {
    final hedefKar = alisFiyati * hedefKarOrani / 100.0;
    final k = komisyonOrani / 100.0;
    final kdvFactor = 1.0 + kdvOrani / 100.0;
    final s = stopajOrani / 100.0;

    // Satış × [1 - k - s/kdvFactor] = Alış + Kargo + Hizmet + Hedef Kâr
    final divisor = 1.0 - k - s / kdvFactor;
    
    if (divisor <= 0) {
      return 0.0;
    }

    final suggested = (alisFiyati + kargoUcreti + hizmetBedeli + hedefKar) / divisor;
    return _round(suggested);
  }
}
