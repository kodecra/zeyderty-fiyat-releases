import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'trendyol_calculator.dart';
import 'trendyol_api.dart';
import 'products_page.dart' show cachedProducts, onProductUpdated;
import 'settings_helper.dart';
import 'database_helper.dart';
import 'widgets/professional_dialog.dart';

// Settings listener için global notifier referansı
late SettingsNotifier _settingsNotifier;

enum SortType {
  profitDesc, // En çok kar
  stockAsc, // En az stok
  stockDesc, // En çok stok
  profitAsc, // En düşük kar
}

class SuggestedPricePage extends StatefulWidget {
  const SuggestedPricePage({super.key});

  @override
  State<SuggestedPricePage> createState() => _SuggestedPricePageState();
}

class _SuggestedPricePageState extends State<SuggestedPricePage> {
   List<Map<String, dynamic>> _groupedProducts = [];
   List<Map<String, dynamic>> _filteredProducts = [];
   final _hedefKarController = TextEditingController(text: '50');
   final TextEditingController _searchController = TextEditingController();
   bool _loading = true;
   SortType _currentSort = SortType.profitDesc;
   int _displayPage = 0;
   int _itemsPerPage = 10; // Sayfa başına ürün
   Set<String> _selectedProducts = {}; // Seçilen ürünler
   bool _updating = false; // Güncelleme durumu

   @override
   void initState() {
     super.initState();
     
     _settingsNotifier = SettingsNotifier();
     _settingsNotifier.addListener(_onSettingsChanged);
     
     _loadProducts();
     _searchController.addListener(_onSearchChanged);
   }

   @override
   void dispose() {
     _hedefKarController.dispose();
     _searchController.removeListener(_onSearchChanged);
     _searchController.dispose();
     _settingsNotifier.removeListener(_onSettingsChanged);
     super.dispose();
   }

   void _onSettingsChanged() {
     // Ayarlar değiştiğinde önerilen fiyatları yeniden hesapla
     if (mounted && _groupedProducts.isNotEmpty) {
       _calculateProfitRatios().then((_) {
         if (mounted) {
           setState(() {
             _sortProducts();
           });
         }
       });
       debugPrint('✅ Önerilen Fiyat sekmesi ayar değişikliğine göre güncellendi');
     }
   }

  void _onSearchChanged() {
    _filterProducts(_searchController.text);
  }

  void _filterProducts(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = _groupedProducts;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredProducts = _groupedProducts.where((product) {
          final productMainId = (product['productMainId'] as String? ?? '').toLowerCase();
          final title = (product['title'] as String? ?? '').toLowerCase();
          
          return productMainId.contains(lowerQuery) || title.contains(lowerQuery);
        }).toList();
      }
      _displayPage = 0; // Arama yapınca ilk sayfaya dön
    });
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);

    // Ürünleri grupla
    final grouped = _groupProductsByModel(cachedProducts);

    setState(() {
      _groupedProducts = grouped;
    });

    // Kar oranlarını hesapla
    await _calculateProfitRatios();

    setState(() {
      _loading = false;
      _filterProducts(_searchController.text); // Arama filtresini uygula
    });

    // Sırala
    _sortProducts();
  }

  void _sortProducts() {
    setState(() {
      switch (_currentSort) {
        case SortType.profitDesc:
          // Önerilen fiyata göre en çok kar
          _groupedProducts.sort((a, b) => (b['suggestedProfit'] as double).compareTo(a['suggestedProfit'] as double));
          break;
        case SortType.profitAsc:
          // Önerilen fiyata göre en düşük kar
          _groupedProducts.sort((a, b) => (a['suggestedProfit'] as double).compareTo(b['suggestedProfit'] as double));
          break;
        case SortType.stockAsc:
          // En az stok
          _groupedProducts.sort((a, b) => (a['totalQuantity'] as int).compareTo(b['totalQuantity'] as int));
          break;
        case SortType.stockDesc:
          // En çok stok
          _groupedProducts.sort((a, b) => (b['totalQuantity'] as int).compareTo(a['totalQuantity'] as int));
          break;
      }
    });
  }

  Future<void> _calculateProfitRatios() async {
    final prefs = await SharedPreferences.getInstance();
    
    for (var product in _groupedProducts) {
      final productMainId = product['productMainId'] as String;
      final variants = product['variants'] as List<Map<String, dynamic>>;
      final currentPrice = product['currentPrice'] as double;
      
      // Maliyet bul
      double costPrice = prefs.getDouble('cost_$productMainId') ?? 0;
      
      if (costPrice == 0) {
        double totalCost = 0;
        int costCount = 0;
        
        for (var variant in variants) {
          final barcode = variant['barcode'] as String?;
          if (barcode != null) {
            final variantCost = prefs.getDouble('cost_$barcode') ?? 0;
            if (variantCost > 0) {
              totalCost += variantCost;
              costCount++;
            }
          }
        }
        
        if (costCount > 0) {
          costPrice = totalCost / costCount;
        }
      }
      
      if (costPrice > 0) {
        // Ayarlardan değerleri al
        final settings = await SettingsHelper.getAllSettings();
        
        // Mevcut kar oranını hesapla
        final currentCalc = TrendyolCalculator.calculate(
          satisFiyati: currentPrice,
          alisFiyati: costPrice,
          komisyonOrani: settings['komisyon'] ?? 21.5,
          kdvOrani: settings['kdv'] ?? 10,
          kargoUcreti: settings['kargo'] ?? 77.54,
          stopajOrani: settings['stopaj'] ?? 1.0,
          hizmetBedeli: settings['hizmet'] ?? 13.19,
        );
        
        product['suggestedProfit'] = currentCalc['kar_orani'] ?? 0.0;
      }
    }
  }

  List<Map<String, dynamic>> _groupProductsByModel(List<Map<String, dynamic>> products) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var product in products) {
      final productMainId = product['productMainId'] as String? ??
                           product['stockCode'] as String? ??
                           product['barcode'] as String? ?? '';
      if (productMainId.isNotEmpty) {
        if (!grouped.containsKey(productMainId)) {
          grouped[productMainId] = [];
        }
        grouped[productMainId]!.add(product);
      }
    }

    final result = <Map<String, dynamic>>[];
    for (var entry in grouped.entries) {
      final variants = entry.value;
      final first = variants.first;

      final totalQuantity = variants.fold<int>(
        0,
        (sum, p) => sum + (p['quantity'] as int? ?? 0),
      );

      // Debug: Stok detaylarını logla
      debugPrint('🔍 Model ${entry.key} stok hesaplaması:');
      for (var v in variants) {
        debugPrint('  ${v['barcode']}: ${v['quantity']} adet');
      }
      debugPrint('  Toplam stok: $totalQuantity');

      // Stok 0 olanları gösterme
      if (totalQuantity <= 0) continue;

      // Fiyat al - salePrice, listPrice veya price alanlarını dene
      double avgPrice = 0;
      for (var p in variants) {
        double price = 0;
        
        // Önce salePrice'ı dene
        if (p['salePrice'] != null) {
          price = (p['salePrice'] as num).toDouble();
        }
        // Yoksa listPrice'ı dene
        else if (p['listPrice'] != null) {
          price = (p['listPrice'] as num).toDouble();
        }
        // Yoksa price'ı dene
        else if (p['price'] != null) {
          price = (p['price'] as num).toDouble();
        }
        
        avgPrice += price;
      }
      avgPrice /= variants.length;
      
      // Debug: İlk varyasyonun fiyat bilgilerini logla
      if (variants.isNotEmpty) {
        final first = variants.first;
        debugPrint('🔍 Model ${entry.key} fiyat bilgileri:');
        debugPrint('  salePrice: ${first['salePrice']}');
        debugPrint('  listPrice: ${first['listPrice']}');
        debugPrint('  price: ${first['price']}');
        debugPrint('  hesaplanan avgPrice: $avgPrice');
      }

      String? imageUrl;
      if (first['images'] != null && (first['images'] as List).isNotEmpty) {
        imageUrl = (first['images'] as List).first['url'] as String?;
      }

      result.add({
        'productMainId': entry.key,
        'title': first['title'] as String? ?? 'İsimsiz',
        'variants': variants,
        'totalQuantity': totalQuantity,
        'currentPrice': avgPrice,
        'imageUrl': imageUrl,
        'variantCount': variants.length,
        'suggestedProfit': 0.0, // _calculateProfitRatios'ta doldurulacak
      });
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Önerilen Fiyat'),
        actions: [
          // Arama ikonu (isteğe bağlı, zaten search bar var)
          if (_searchController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '${(_searchController.text.isNotEmpty ? _filteredProducts : _groupedProducts).length}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          // Seçili ürünleri güncelle
          if (_selectedProducts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.green.shade400,
                        Colors.green.shade600,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _updating ? null : _updateSelectedProducts,
                    icon: _updating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 20),
                    label: Text(
                      _updating ? 'Güncelleniyor...' : '${_selectedProducts.length} Ürün Güncelle',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
              ),
            ),
          PopupMenuButton<SortType>(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() {
                _currentSort = value;
              });
              _sortProducts();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: SortType.profitDesc,
                child: Text('En Çok Kar'),
              ),
              const PopupMenuItem(
                value: SortType.profitAsc,
                child: Text('En Düşük Kar'),
              ),
              const PopupMenuItem(
                value: SortType.stockAsc,
                child: Text('En Az Stok'),
              ),
              const PopupMenuItem(
                value: SortType.stockDesc,
                child: Text('En Çok Stok'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Arama Çubuğu
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade50,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Model kodu veya ürün adı ara...',
                prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _filterProducts('');
                    },
                  )
                : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.orange, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          // Hedef Kar Ayarı
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.orange.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Hedef Kar Oranı:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hedefKarController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          suffixText: '%',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Uygula'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Ürün Listesi
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange.shade400,
                                Colors.orange.shade600,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.price_check,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Fiyatlar Hesaplanıyor',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Lütfen bekleyin...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  )
                : _groupedProducts.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('Önce Ürünler sekmesinden ürün çekin', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : Column(
                       children: [
                         Expanded(
                           child: _searchController.text.isNotEmpty && _filteredProducts.isEmpty
                               ? Center(
                                   child: Column(
                                     mainAxisAlignment: MainAxisAlignment.center,
                                     children: [
                                       Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                                       const SizedBox(height: 16),
                                       Text(
                                         '0 sonuç',
                                         style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                                       ),
                                       const SizedBox(height: 8),
                                       Text(
                                         'Arama kriterlerine uygun ürün bulunamadı',
                                         style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                                       ),
                                     ],
                                   ),
                                 )
                               : ListView.builder(
                                   itemCount: _getDisplayedProducts().length,
                                   itemBuilder: (context, index) {
                                     return _buildProductCard(_getDisplayedProducts()[index]);
                                   },
                                 ),
                         ),
                         _buildPaginationControls(),
                       ],
                     ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getDisplayedProducts() {
    final products = _searchController.text.isNotEmpty ? _filteredProducts : _groupedProducts;
    final start = _displayPage * _itemsPerPage;
    final end = start + _itemsPerPage;
    final total = products.length;
    
    if (start >= total) return [];
    return products.sublist(start, end > total ? total : end);
  }

  int _getTotalPages() {
    final products = _searchController.text.isNotEmpty ? _filteredProducts : _groupedProducts;
    return (products.length / _itemsPerPage).ceil();
  }

  Widget _buildPaginationControls() {
    final products = _searchController.text.isNotEmpty ? _filteredProducts : _groupedProducts;
    final totalPages = _getTotalPages();
    
    if (products.isEmpty) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey.shade100,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton(
                onPressed: _displayPage > 0
                    ? () => setState(() => _displayPage--)
                    : null,
                child: const Text('← Önceki'),
              ),
              ElevatedButton(
                onPressed: _displayPage < totalPages - 1
                    ? () => setState(() => _displayPage++)
                    : null,
                child: const Text('Sonraki →'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sayfa ${_displayPage + 1}/$totalPages',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
              ),
              if (_searchController.text.isNotEmpty)
                Text(
                  '${products.length} sonuç',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final productMainId = product['productMainId'] as String;
    final title = product['title'] as String;
    final currentPrice = product['currentPrice'] as double;
    final totalQuantity = product['totalQuantity'] as int;
    final variantCount = product['variantCount'] as int;
    final imageUrl = product['imageUrl'] as String?;
    final variants = product['variants'] as List<Map<String, dynamic>>;

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        SharedPreferences.getInstance(),
        SettingsHelper.getAllSettings(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final prefs = snapshot.data![0] as SharedPreferences;
        final settings = snapshot.data![1] as Map<String, dynamic>;
        final hedefKar = double.tryParse(_hedefKarController.text) ?? 50;

        // Maliyet bul
        double costPrice = prefs.getDouble('cost_$productMainId') ?? 0;
        
        if (costPrice == 0) {
          double totalCost = 0;
          int costCount = 0;
          
          for (var variant in variants) {
            final barcode = variant['barcode'] as String?;
            if (barcode != null) {
              final variantCost = prefs.getDouble('cost_$barcode') ?? 0;
              if (variantCost > 0) {
                totalCost += variantCost;
                costCount++;
              }
            }
          }
          
          if (costCount > 0) {
            costPrice = totalCost / costCount;
          }
        }

        if (costPrice == 0) {
          return const SizedBox.shrink(); // Maliyeti olmayan ürünleri gösterme
        }
        
        // Önerilen fiyat hesapla
        final suggestedPrice = TrendyolCalculator.suggestPrice(
          alisFiyati: costPrice,
          komisyonOrani: settings['komisyon'] ?? 21.5,
          kdvOrani: settings['kdv'] ?? 10,
          kargoUcreti: settings['kargo'] ?? 77.54,
          stopajOrani: settings['stopaj'] ?? 1.0,
          hizmetBedeli: settings['hizmet'] ?? 13.19,
          hedefKarOrani: hedefKar,
        );

        // Önerilen fiyatla kar hesapla
        final suggestedCalc = TrendyolCalculator.calculate(
          satisFiyati: suggestedPrice,
          alisFiyati: costPrice,
          komisyonOrani: settings['komisyon'] ?? 21.5,
          kdvOrani: settings['kdv'] ?? 10,
          kargoUcreti: settings['kargo'] ?? 77.54,
          stopajOrani: settings['stopaj'] ?? 1.0,
          hizmetBedeli: settings['hizmet'] ?? 13.19,
        );

        final suggestedProfitRatio = suggestedCalc['kar_orani'] ?? 0;

        // Mevcut kar oranını product'tan al (zaten _calculateProfitRatios'ta hesaplandı)
        final currentProfitRatio = product['suggestedProfit'] as double? ?? 0.0;
        
        // Mevcut kar miktarını doğru hesapla
        final currentCalc = TrendyolCalculator.calculate(
          satisFiyati: currentPrice,
          alisFiyati: costPrice,
          komisyonOrani: settings['komisyon'] ?? 21.5,
          kdvOrani: settings['kdv'] ?? 10,
          kargoUcreti: settings['kargo'] ?? 77.54,
          stopajOrani: settings['stopaj'] ?? 1.0,
          hizmetBedeli: settings['hizmet'] ?? 13.19,
        );
        final currentProfit = currentCalc['kar'] ?? 0.0;

        final priceDiff = suggestedPrice - currentPrice;
        final diffColor = priceDiff > 0 ? Colors.red : Colors.green;
        const imageSize = 40.0; // Daha küçük
        const spacing = 12.0;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showPriceDetail(product, costPrice, suggestedPrice, hedefKar),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Checkbox
                  Checkbox(
                    value: _selectedProducts.contains(productMainId),
                    onChanged: (selected) {
                      setState(() {
                        if (selected == true) {
                          _selectedProducts.add(productMainId);
                        } else {
                          _selectedProducts.remove(productMainId);
                        }
                      });
                    },
                  ),
                  
                  // Resim
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: imageSize,
                        height: imageSize,
                        fit: BoxFit.cover,
                        memCacheWidth: 80,
                        errorWidget: (context, url, error) =>
                            Icon(Icons.image_not_supported, size: imageSize),
                      ),
                    )
                  else
                    Icon(Icons.image_not_supported, size: imageSize),
                  SizedBox(width: spacing * 0.7),

                  // Bilgiler
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: spacing * 0.2),
                        Text(
                          'Model: $productMainId',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Stok: $totalQuantity ($variantCount varyasyon)',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Maliyet: ${costPrice.toStringAsFixed(2)} ₺',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.red.shade400,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: spacing * 0.2),
                        Row(
                          children: [
                            Text(
                              'Mevcut: ${currentPrice.toStringAsFixed(0)} ₺',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: spacing * 0.3),
                            Text(
                              '(${currentProfit.toStringAsFixed(0)} ₺ / %${currentProfitRatio.toStringAsFixed(1)})',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(width: spacing * 0.3),
                            Text(
                              '${priceDiff >= 0 ? '+' : ''}${priceDiff.toStringAsFixed(0)} ₺',
                              style: TextStyle(
                                fontSize: 10,
                                color: diffColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Önerilen Fiyat
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.orange.shade50,
                          Colors.orange.shade100,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.shade300, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ÖNERİLEN',
                          style: TextStyle(
                            fontSize: 7,
                            color: Colors.orange,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(height: spacing * 0.1),
                        Text(
                          '${suggestedPrice.toStringAsFixed(2)} ₺',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.orange,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '%${suggestedProfitRatio.toStringAsFixed(1)}',
                            style: const TextStyle(
                              fontSize: 7,
                              color: Colors.orange,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPriceDetail(Map<String, dynamic> product, double costPrice, double suggestedPrice, double hedefKar) async {
    final currentPrice = product['currentPrice'] as double;
    
    final settings = await SettingsHelper.getAllSettings();
    
    final currentCalc = TrendyolCalculator.calculate(
      satisFiyati: currentPrice,
      alisFiyati: costPrice,
      komisyonOrani: settings['komisyon'] ?? 21.5,
      kdvOrani: settings['kdv'] ?? 10,
      kargoUcreti: settings['kargo'] ?? 77.54,
      stopajOrani: settings['stopaj'] ?? 1.0,
      hizmetBedeli: settings['hizmet'] ?? 13.19,
    );

    final suggestedCalc = TrendyolCalculator.calculate(
      satisFiyati: suggestedPrice,
      alisFiyati: costPrice,
      komisyonOrani: settings['komisyon'] ?? 21.5,
      kdvOrani: settings['kdv'] ?? 10,
      kargoUcreti: settings['kargo'] ?? 77.54,
      stopajOrani: settings['stopaj'] ?? 1.0,
      hizmetBedeli: settings['hizmet'] ?? 13.19,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product['title']),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Maliyet: ${costPrice.toStringAsFixed(2)} ₺'),
              Text('Hedef Kar: %$hedefKar'),
              const Divider(),
              const Text('MEVCUT FİYAT:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Fiyat: ${currentPrice.toStringAsFixed(2)} ₺'),
              Text('Komisyon: ${currentCalc['komisyon']?.toStringAsFixed(2)} ₺'),
              Text('Stopaj: ${currentCalc['stopaj']?.toStringAsFixed(2)} ₺'),
              Text('Hizmet Bedeli: ${currentCalc['hizmet_bedeli']?.toStringAsFixed(2)} ₺'),
              Text('Kargo Ücreti: 77.54 ₺'),
              const Divider(),
              Text('Kar: ${currentCalc['kar']?.toStringAsFixed(2)} ₺'),
              Text('Kar Oranı: %${currentCalc['kar_orani']?.toStringAsFixed(1)}'),
              const Divider(),
              const Text('ÖNERİLEN FİYAT:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              Text('Fiyat: ${suggestedPrice.toStringAsFixed(2)} ₺', style: const TextStyle(color: Colors.orange)),
              Text('Komisyon: ${suggestedCalc['komisyon']?.toStringAsFixed(2)} ₺', style: const TextStyle(color: Colors.orange)),
              Text('Stopaj: ${suggestedCalc['stopaj']?.toStringAsFixed(2)} ₺', style: const TextStyle(color: Colors.orange)),
              Text('Hizmet Bedeli: ${suggestedCalc['hizmet_bedeli']?.toStringAsFixed(2)} ₺', style: const TextStyle(color: Colors.orange)),
              Text('Kargo Ücreti: 77.54 ₺', style: const TextStyle(color: Colors.orange)),
              const Divider(),
              Text('Kar: ${suggestedCalc['kar']?.toStringAsFixed(2)} ₺', style: const TextStyle(color: Colors.orange)),
              Text('Kar Oranı: %${suggestedCalc['kar_orani']?.toStringAsFixed(1)}', style: const TextStyle(color: Colors.orange)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('KAPAT'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSelectedProducts() async {
    if (_selectedProducts.isEmpty) return;

    setState(() => _updating = true);
    
    // Loading dialog göster
    if (mounted) {
      ProfessionalDialog.showLoading(
        context,
        message: 'Fiyatlar güncelleniyor...',
      );
    }

    try {
      final api = TrendyolAPI(
        sellerId: '687036',
        apiKey: 'hiYLAuM5KUY015QIkQ0L',
        apiSecret: 'jiF8ry0HPSjU5ShJYwG3',
      );

      final prefs = await SharedPreferences.getInstance();
      final settings = await SettingsHelper.getAllSettings();
      final hedefKar = double.tryParse(_hedefKarController.text) ?? 50;
      final List<Map<String, dynamic>> itemsToUpdate = [];
      final List<String> updatedModelCodes = [];

      // Seçilen ürünlerin varyasyonlarını topla
      for (var product in _groupedProducts) {
        final productMainId = product['productMainId'] as String;
        if (!_selectedProducts.contains(productMainId)) continue;

        final variants = product['variants'] as List<Map<String, dynamic>>;
        
        // Maliyet bul - önce model kodundan, yoksa varyasyonların ortalamasından
        double costPrice = prefs.getDouble('cost_$productMainId') ?? 0;
        
        if (costPrice == 0) {
          double totalCost = 0;
          int costCount = 0;
          
          for (var variant in variants) {
            final barcode = variant['barcode'] as String?;
            if (barcode != null) {
              final variantCost = prefs.getDouble('cost_$barcode') ?? 0;
              if (variantCost > 0) {
                totalCost += variantCost;
                costCount++;
              }
            }
          }
          
          if (costCount > 0) {
            costPrice = totalCost / costCount;
          }
        }

        if (costPrice == 0) {
          debugPrint('⚠️ Maliyet bulunamadı: $productMainId');
          continue;
        }
        
        debugPrint('✅ Güncellenecek: $productMainId - Maliyet: $costPrice');
        updatedModelCodes.add(productMainId);

        // Önerilen fiyatı hesapla
        final suggestedPrice = TrendyolCalculator.suggestPrice(
          alisFiyati: costPrice,
          komisyonOrani: settings['komisyon'] ?? 21.5,
          kdvOrani: settings['kdv'] ?? 10,
          kargoUcreti: settings['kargo'] ?? 77.54,
          stopajOrani: settings['stopaj'] ?? 1.0,
          hizmetBedeli: settings['hizmet'] ?? 13.19,
          hedefKarOrani: hedefKar,
        );

        // Her varyasyon için güncelleme öğesi oluştur
        for (var variant in variants) {
          final barcode = variant['barcode'] as String?;
          
          if (barcode != null) {
            // Mevcut stok miktarını koru, sadece fiyatı güncelle
            final quantity = variant['quantity'] as int? ?? 0;
            
            itemsToUpdate.add({
              'barcode': barcode,
              'quantity': quantity,
              'salePrice': suggestedPrice,
              'listPrice': suggestedPrice,
            });
            
            // cachedProducts'ı güncelle
            final index = cachedProducts.indexWhere((p) => p['barcode'] == barcode);
            if (index != -1) {
              cachedProducts[index]['salePrice'] = suggestedPrice;
              cachedProducts[index]['listPrice'] = suggestedPrice;
              cachedProducts[index]['price'] = suggestedPrice;
            }
            
            debugPrint('  → $barcode: $quantity adet, ${suggestedPrice.toStringAsFixed(2)} ₺');
          }
        }
      }

      if (itemsToUpdate.isEmpty) {
        if (mounted) {
          await ProfessionalDialog.showInfo(
            context,
            title: 'Uyarı',
            message: 'Güncellenecek ürün bulunamadı.\n\nLütfen en az bir ürün seçin.',
          );
        }
        return;
      }

      // API'ye gönder (100'erli gruplar halinde)
      int successCount = 0;
      int failCount = 0;
      
      for (int i = 0; i < itemsToUpdate.length; i += 100) {
        final batch = itemsToUpdate.skip(i).take(100).toList();
        try {
          await api.updatePriceAndStock(items: batch);
          successCount += batch.length;
        } catch (e) {
          failCount += batch.length;
          debugPrint('Batch güncelleme hatası: $e');
        }
      }

      // Database'e kaydet
      if (successCount > 0) {
        final db = DatabaseHelper.instance;
        await db.saveProducts(cachedProducts);
        debugPrint('💾 Güncellemeler database\'e kaydedildi');
        
        // Ürünler sekmesini bilgilendir
        if (onProductUpdated != null) {
          for (var modelCode in updatedModelCodes) {
            onProductUpdated!(modelCode);
          }
        }
        
        // Tüm sekmelere bildirim gönder - fiyatlar değişti
        // Not: notifyListeners() doğrudan çağrılamaz, bunun yerine settings güncellemesi yapılır
        debugPrint('✅ Fiyat güncellemesi tamamlandı');
      }

      if (mounted) {
        // Loading dialog'ı kapat
        Navigator.of(context).pop();
        
        setState(() {
          _selectedProducts.clear();
        });

        // Model kodlarını hazırla
        final modelCodesText = updatedModelCodes.length <= 3
            ? updatedModelCodes.join(', ')
            : '${updatedModelCodes.take(3).join(', ')} ve ${updatedModelCodes.length - 3} diğer';

        // Detaylı bilgi listesi
        final details = <String>[];
        details.add('✓ $successCount varyasyon güncellendi');
        if (failCount > 0) {
          details.add('✗ $failCount varyasyon hatalı');
        }
        details.add('📦 ${updatedModelCodes.length} model kodu');
        
        // Success dialog göster
        await ProfessionalDialog.showSuccess(
          context,
          title: 'Fiyatlar Güncellendi!',
          message: '$modelCodesText\nbaşarıyla güncellendi.',
          details: details,
          duration: const Duration(seconds: 5),
        );
      }
    } catch (e) {
      if (mounted) {
        // Loading dialog'ı kapat
        Navigator.of(context).pop();
        
        // Error dialog göster
        await ProfessionalDialog.showError(
          context,
          title: 'Güncelleme Hatası',
          message: 'Fiyatlar güncellenirken bir hata oluştu.',
          errorDetails: e.toString(),
        );
      }
    } finally {
      setState(() => _updating = false);
    }
  }
}
