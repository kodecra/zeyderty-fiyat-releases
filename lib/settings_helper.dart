import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsNotifier extends ChangeNotifier {
  static final SettingsNotifier _instance = SettingsNotifier._internal();

  factory SettingsNotifier() {
    return _instance;
  }

  SettingsNotifier._internal();

  double _komisyon = 21.5;
  double _stopaj = 1.0;
  double _hizmet = 13.19;
  double _kargo = 77.54;
  double _kdv = 10;

  // Getters
  double get komisyon => _komisyon;
  double get stopaj => _stopaj;
  double get hizmet => _hizmet;
  double get kargo => _kargo;
  double get kdv => _kdv;

  // Initialize from SharedPreferences
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _komisyon = double.tryParse(prefs.getString('komisyon') ?? '21.5') ?? 21.5;
    _stopaj = double.tryParse(prefs.getString('stopaj') ?? '1.0') ?? 1.0;
    _hizmet = double.tryParse(prefs.getString('hizmet') ?? '13.19') ?? 13.19;
    _kargo = double.tryParse(prefs.getString('kargo') ?? '77.54') ?? 77.54;
    _kdv = double.tryParse(prefs.getString('kdv') ?? '10') ?? 10;
    notifyListeners();
  }

  // Update methods
  Future<void> updateSettings({
    double? komisyon,
    double? stopaj,
    double? hizmet,
    double? kargo,
    double? kdv,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (komisyon != null) {
      _komisyon = komisyon;
      await prefs.setString('komisyon', komisyon.toString());
    }
    if (stopaj != null) {
      _stopaj = stopaj;
      await prefs.setString('stopaj', stopaj.toString());
    }
    if (hizmet != null) {
      _hizmet = hizmet;
      await prefs.setString('hizmet', hizmet.toString());
    }
    if (kargo != null) {
      _kargo = kargo;
      await prefs.setString('kargo', kargo.toString());
    }
    if (kdv != null) {
      _kdv = kdv;
      await prefs.setString('kdv', kdv.toString());
    }

    notifyListeners();
  }

  Map<String, double> getAll() {
    return {
      'komisyon': _komisyon,
      'stopaj': _stopaj,
      'hizmet': _hizmet,
      'kargo': _kargo,
      'kdv': _kdv,
    };
  }
}

// Legacy static methods for backward compatibility
class SettingsHelper {
  static Future<double> getKomisyon() async {
    final prefs = await SharedPreferences.getInstance();
    return double.tryParse(prefs.getString('komisyon') ?? '21.5') ?? 21.5;
  }

  static Future<double> getStopaj() async {
    final prefs = await SharedPreferences.getInstance();
    return double.tryParse(prefs.getString('stopaj') ?? '1.0') ?? 1.0;
  }

  static Future<double> getHizmet() async {
    final prefs = await SharedPreferences.getInstance();
    return double.tryParse(prefs.getString('hizmet') ?? '13.19') ?? 13.19;
  }

  static Future<double> getKargo() async {
    final prefs = await SharedPreferences.getInstance();
    return double.tryParse(prefs.getString('kargo') ?? '77.54') ?? 77.54;
  }

  static Future<double> getKDV() async {
    final prefs = await SharedPreferences.getInstance();
    return double.tryParse(prefs.getString('kdv') ?? '10') ?? 10;
  }

  static Future<double> getHedefKar() async {
    final prefs = await SharedPreferences.getInstance();
    return double.tryParse(prefs.getString('hedef_kar') ?? '50') ?? 50;
  }

  static Future<Map<String, double>> getAllSettings() async {
    return {
      'komisyon': await getKomisyon(),
      'stopaj': await getStopaj(),
      'hizmet': await getHizmet(),
      'kargo': await getKargo(),
      'kdv': await getKDV(),
      'hedef_kar': await getHedefKar(),
    };
  }
}
