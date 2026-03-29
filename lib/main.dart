import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'trendyol_calculator.dart';
import 'products_page.dart';
import 'settings_page.dart';
import 'suggested_price_page.dart';
import 'settings_helper.dart';
import 'update_checker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize settings
  await SettingsNotifier().init();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZeyderTY Fiyat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
        fontFamily: GoogleFonts.poppins().fontFamily,
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  
  final List<Widget> _pages = [
    const CalculatorPage(),
    const ProductsPage(),
    const SuggestedPricePage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // Uygulama açıldığında güncelleme kontrolü yap
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    // Güncelleme kontrolü yapılmalı mı kontrol et
    final shouldCheck = await UpdateChecker.shouldCheckForUpdate();
    if (shouldCheck && mounted) {
      await UpdateChecker.checkForUpdate(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            label: 'Hesaplayıcı',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Ürünler',
          ),
          NavigationDestination(
            icon: Icon(Icons.price_check_outlined),
            selectedIcon: Icon(Icons.price_check),
            label: 'Önerilen Fiyat',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ayarlar',
          ),
        ],
      ),
    );
  }
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  final _formKey = GlobalKey<FormState>();
  final _satisFiyatiController = TextEditingController();
  final _alisFiyatiController = TextEditingController();
  final _komisyonController = TextEditingController(text: '21.5');
  final _kdvController = TextEditingController(text: '10');
  final _kargoController = TextEditingController(text: '77.54');
  
  Map<String, double> _result = {};

  @override
  void dispose() {
    _satisFiyatiController.dispose();
    _alisFiyatiController.dispose();
    _komisyonController.dispose();
    _kdvController.dispose();
    _kargoController.dispose();
    super.dispose();
  }

  void _hesapla() {
    if (_formKey.currentState!.validate()) {
      final satis = double.tryParse(_satisFiyatiController.text) ?? 0;
      final alis = double.tryParse(_alisFiyatiController.text) ?? 0;
      final komisyon = double.tryParse(_komisyonController.text) ?? 0;
      final kdv = double.tryParse(_kdvController.text) ?? 0;
      final kargo = double.tryParse(_kargoController.text) ?? 0;

      setState(() {
        _result = TrendyolCalculator.calculate(
          satisFiyati: satis,
          alisFiyati: alis,
          komisyonOrani: komisyon,
          kdvOrani: kdv,
          kargoUcreti: kargo,
          stopajOrani: 1.0,
          hizmetBedeli: 13.19,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trendyol Kar-Zarar Hesaplayıcı',
          style: TextStyle(fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildTextField('Satış Fiyatı (KDV Dahil)', _satisFiyatiController),
              const SizedBox(height: 10),
              _buildTextField('Alış Fiyatı (KDV Dahil)', _alisFiyatiController),
              const SizedBox(height: 10),
              _buildTextField('Komisyon Oranı (%)', _komisyonController),
              const SizedBox(height: 10),
              _buildTextField('KDV Oranı (%)', _kdvController),
              const SizedBox(height: 10),
              _buildTextField('Kargo Ücreti', _kargoController),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _hesapla,
                  child: const Text(
                    'HESAPLA',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
              if (_result.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildResultCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 14),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Lütfen bir değer girin';
        }
        if (double.tryParse(value) == null) {
          return 'Geçerli bir sayı girin';
        }
        return null;
      },
    );
  }

  Widget _buildResultCard() {
    final kar = _result['kar'] ?? 0;
    final karOrani = _result['kar_orani'] ?? 0;
    final komisyon = _result['komisyon'] ?? 0;
    final stopaj = _result['stopaj'] ?? 0;
    final hizmet = _result['hizmet_bedeli'] ?? 0;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SONUÇLAR',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const Divider(height: 12),
            _buildResultRow('Komisyon', komisyon),
            _buildResultRow('Stopaj', stopaj),
            _buildResultRow('Hizmet Bedeli', hizmet),
            const Divider(height: 12),
            _buildResultRow(
              'TAHMİNİ KAR',
              kar,
              color: kar >= 0 ? Colors.green : Colors.red,
              bold: true,
            ),
            _buildResultRow(
              'Kar Oranı',
              karOrani,
              suffix: '%',
              color: kar >= 0 ? Colors.green : Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, double value, {
    String suffix = '₺',
    Color? color,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          Text(
            '${value.toStringAsFixed(2)} $suffix',
            style: TextStyle(
              fontSize: 16,
              color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
