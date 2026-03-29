import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'trendyol_api.dart';
import 'trendyol_calculator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_helper.dart';
import 'database_helper.dart';

// Global ürün listesi - bellekte saklanacak
List<Map<String, dynamic>> cachedProducts = [];
bool _costsLoaded = false;
// Global callback - ürün güncellendiğinde çağrılır
Function(String)? onProductUpdated;

// Settings listener için global notifier referansı
late SettingsNotifier _settingsNotifier;

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

enum SortType {
  stockAsc, // Stok azalan
  stockDesc, // Stok çoklayan
  profitDesc, // Kar oranı yüksek
}

class _ProductsPageState extends State<ProductsPage> {
   List<Map<String, dynamic>> _groupedProducts = [];
   List<Map<String, dynamic>> _filteredProducts = [];
   bool _loading = false;
   String? _error;
   int _currentPage = 0;
   bool _hasMore = true;
   SortType _currentSort = SortType.profitDesc;
   Set<String> _selectedProducts = {};
   bool _selectionMode = false;
   int _currentProgress = 0;
   int _totalProgress = 0;
   int _loadedCount = 0;
   bool _isLoadingMore = false;
   int _displayPage = 0; // Görüntülenen sayfa
   int _itemsPerPage = 10; // Sayfa başına ürün
   final TextEditingController _searchController = TextEditingController();

   @override
   void initState() {
     super.initState();
     
     _settingsNotifier = SettingsNotifier();
     _settingsNotifier.addListener(_onSettingsChanged);
     
     _loadModelCosts().then((_) async {
       debugPrint('Maliyetler yüklendi, ürünler yükleniyor...');
       
       // Önce cache'den yükle
       await _loadFromCache();
       
       // Sonra arka planda yeni ürün kontrolü yap
       _checkForNewProducts();
     });
     
     _searchController.addListener(_onSearchChanged);
   }


  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _settingsNotifier.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    // Ayarlar değiştiğinde ürünler sekmesini yenile
    if (mounted && _groupedProducts.isNotEmpty) {
      setState(() {
        _groupedProducts = _groupProductsByStockCode(cachedProducts);
        _filterProducts(_searchController.text);
      });
      debugPrint('✅ Ürünler sekmesi ayar değişikliğine göre güncellendi');
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
          final stockCode = (product['stockCode'] as String? ?? '').toLowerCase();
          final barcode = (product['barcode'] as String? ?? '').toLowerCase();
          
          return productMainId.contains(lowerQuery) ||
                 title.contains(lowerQuery) ||
                 stockCode.contains(lowerQuery) ||
                 barcode.contains(lowerQuery);
        }).toList();
      }
      _displayPage = 0; // Arama yapınca ilk sayfaya dön
    });
  }
  
  // Cache'den ürünleri yükle
  Future<void> _loadFromCache() async {
    try {
      final db = DatabaseHelper.instance;
      final products = await db.loadProducts();
      
      if (products.isNotEmpty) {
        cachedProducts = products;
        await _loadProducts();
        debugPrint('✅ Cache\'den ${products.length} ürün yüklendi');
      } else {
        debugPrint('ℹ️ Cache boş, API\'den çekilmeli');
      }
    } catch (e) {
      debugPrint('❌ Cache yükleme hatası: $e');
    }
  }
  
  // Yeni ürünleri kontrol et ve ekle
  Future<void> _checkForNewProducts() async {
    if (cachedProducts.isEmpty) {
      // Cache boşsa tam yükleme yap
      debugPrint('🔄 Cache boş, tam yükleme yapılıyor...');
      await _syncFromAPI(loadMore: false);
      return;
    }
    
    debugPrint('🔍 Yeni ürünler kontrol ediliyor...');
    
    final api = TrendyolAPI(
      sellerId: '687036',
      apiKey: 'hiYLAuM5KUY015QIkQ0L',
      apiSecret: 'jiF8ry0HPSjU5ShJYwG3',
    );
    
    try {
      // İlk sayfayı çek
      final allProducts = await api.getAllProducts(
        onProgress: (current, total, productCount) {},
      );
      
      // Yeni ürünleri tespit et
      final existingBarcodes = cachedProducts.map((p) => p['barcode'] as String? ?? '').toSet();
      final newProducts = allProducts.where((p) => !existingBarcodes.contains(p['barcode'] as String? ?? '')).toList();
      
      if (newProducts.isNotEmpty) {
        debugPrint('🆕 ${newProducts.length} yeni ürün bulundu!');
        
        // Yeni ürünleri başa ekle
        cachedProducts = [...newProducts, ...cachedProducts];
        
        // Database'e kaydet
        final db = DatabaseHelper.instance;
        await db.saveProducts(cachedProducts);
        
        // UI'ı güncelle
        setState(() {
          _groupedProducts = _groupProductsByStockCode(cachedProducts);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${newProducts.length} yeni ürün eklendi'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        debugPrint('✅ Yeni ürün yok');
      }
    } catch (e) {
      debugPrint('❌ Yeni ürün kontrolü hatası: $e');
    } finally {
      api.dispose();
    }
  }

  // JSON'dan maliyetleri SharedPreferences'a yükle
  Future<void> _loadModelCosts() async {
    if (_costsLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      int loadedCount = 0;

      // Model maliyetlerini yükle
      try {
        final modelJson = await rootBundle.loadString('assets/model_costs.json');
        final List<dynamic> modelData = jsonDecode(modelJson);

        for (var item in modelData) {
          final modelCode = item['model_code'] as String;
          final costPrice = (item['cost_price'] as num?)?.toDouble() ?? 0;
          await prefs.setDouble('cost_$modelCode', costPrice);
          loadedCount++;
        }
      } catch (e) {
        debugPrint('Model maliyet yükleme hatası: $e');
      }

      // Barkod maliyetlerini yükle
      try {
        final productJson = await rootBundle.loadString('assets/product_costs.json');
        final List<dynamic> productData = jsonDecode(productJson);

        for (var item in productData) {
          final barcode = item['barcode'] as String;
          final costPrice = (item['cost_price'] as num?)?.toDouble() ?? 0;
          await prefs.setDouble('cost_$barcode', costPrice);
          loadedCount++;
        }
      } catch (e) {
        debugPrint('Barkod maliyet yükleme hatası: $e');
      }

      _costsLoaded = true;
      debugPrint('$loadedCount maliyet yüklendi');
    } catch (e) {
      debugPrint('Maliyet yükleme hatası: $e');
    }
  }

  Future<void> _loadProducts() async {
    // Ürünleri stockCode'a göre grupla
    final grouped = _groupProductsByStockCode(cachedProducts);
    setState(() {
      _groupedProducts = grouped;
      _filterProducts(_searchController.text); // Arama filtresini uygula
    });
  }

  // Ürünleri productMainId'ye göre grupla (model kodu)
  List<Map<String, dynamic>> _groupProductsByStockCode(List<Map<String, dynamic>> products) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var product in products) {
      // productMainId model kodudur - aynı modelin varyasyonlarını gruplar
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

    // Her grup için özet bilgileri hesapla
    final result = <Map<String, dynamic>>[];
    for (var entry in grouped.entries) {
      final variants = entry.value;
      final first = variants.first;

      // Toplam stok hesapla
      final totalQuantity = variants.fold<int>(
        0,
        (sum, p) => sum + (p['quantity'] as int? ?? 0),
      );

      // Stok 0 olanları gösterme
      if (totalQuantity <= 0) continue;

      // Fiyat al - salePrice, listPrice veya price alanlarını dene
      double avgPrice = 0;
      for (var p in variants) {
        double price = 0;
        
        if (p['salePrice'] != null) {
          price = (p['salePrice'] as num).toDouble();
        } else if (p['listPrice'] != null) {
          price = (p['listPrice'] as num).toDouble();
        } else if (p['price'] != null) {
          price = (p['price'] as num).toDouble();
        }
        
        avgPrice += price;
      }
      avgPrice /= variants.length;

      // İlk resmi al
      String? imageUrl;
      if (first['images'] != null && (first['images'] as List).isNotEmpty) {
        imageUrl = (first['images'] as List).first['url'] as String?;
      }

      result.add({
        'productMainId': entry.key, // Model kodu
        'title': first['title'] as String? ?? 'İsimsiz',
        'barcode': first['barcode'] as String? ?? '',
        'stockCode': first['stockCode'] as String? ?? '',
        'variants': variants,
        'totalQuantity': totalQuantity,
        'avgPrice': avgPrice,
        'imageUrl': imageUrl,
        'variantCount': variants.length,
      });
    }

    // productMainId'ye göre sırala
    result.sort((a, b) => (a['productMainId'] as String).compareTo(b['productMainId'] as String));
    return result;
  }

  Future<void> _syncFromAPI({bool loadMore = false}) async {
    final api = TrendyolAPI(
      sellerId: '687036',
      apiKey: 'hiYLAuM5KUY015QIkQ0L',
      apiSecret: 'jiF8ry0HPSjU5ShJYwG3',
    );

    if (!loadMore) {
      setState(() {
        _loading = true;
        _error = null;
        _currentProgress = 0;
        _totalProgress = 0;
        _loadedCount = 0;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final connected = await api.testConnection();
      if (!connected) {
        throw Exception('API bağlantısı başarısız');
      }

      // Tüm ürünleri çek
      final allProducts = await api.getAllProducts(
        onProgress: (current, total, productCount) {
          setState(() {
            _currentProgress = current;
            _totalProgress = total;
            _loadedCount = productCount;
          });
          debugPrint('Yükleniyor: $current/$total sayfa, $productCount ürün');
        },
      );

      // Debug: İlk ürünün fiyat alanlarını logla
      if (allProducts.isNotEmpty) {
        debugPrint('🔍 İlk ürün fiyat bilgileri:');
        final firstProduct = allProducts.first;
        debugPrint('  barcode: ${firstProduct['barcode']}');
        debugPrint('  salePrice: ${firstProduct['salePrice']}');
        debugPrint('  listPrice: ${firstProduct['listPrice']}');
        debugPrint('  price: ${firstProduct['price']}');
        debugPrint('  tüm anahtarlar: ${firstProduct.keys.toList()}');
      }

      // Yeni ürünleri tespit et ve başa ekle
      final existingBarcodes = cachedProducts.map((p) => p['barcode'] as String? ?? '').toSet();
      final newProducts = allProducts.where((p) => !existingBarcodes.contains(p['barcode'] as String? ?? '')).toList();
      final oldProducts = allProducts.where((p) => existingBarcodes.contains(p['barcode'] as String? ?? '')).toList();

      // Yeni ürünleri başa, eski ürünleri arkaya ekle
      cachedProducts = [...newProducts, ...oldProducts];

      debugPrint('✅ Toplam: ${allProducts.length} ürün');
      debugPrint('🆕 Yeni: ${newProducts.length} ürün');
      debugPrint('📦 Eski: ${oldProducts.length} ürün');

      // Database'e kaydet
      final db = DatabaseHelper.instance;
      await db.saveProducts(cachedProducts);
      debugPrint('💾 Database\'e kaydedildi');

      // Ürünleri grupla
      final grouped = _groupProductsByStockCode(cachedProducts);

      setState(() {
        _groupedProducts = grouped;
        _loading = false;
        _isLoadingMore = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${allProducts.length} ürün yüklendi (${newProducts.length} yeni, ${grouped.length} grup)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _isLoadingMore = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      api.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ürünler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _syncFromAPI(loadMore: false),
            tooltip: 'API\'den Ürün Çek',
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
                hintText: 'Model kodu, barkod veya ürün adı ara...',
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
          // İçerik
          Expanded(
            child: _loading
               ? Center(
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       _buildLoadingAnimation(),
                       if (_totalProgress > 0) ...[
                         const SizedBox(height: 32),
                         Column(
                           children: [
                             Text(
                               'Sayfa $_currentProgress/$_totalProgress',
                               style: const TextStyle(
                                 fontSize: 16,
                                 fontWeight: FontWeight.w600,
                                 letterSpacing: 0.5,
                               ),
                             ),
                             const SizedBox(height: 12),
                             Text(
                               '$_loadedCount ürün yüklendi',
                               style: const TextStyle(
                                 fontSize: 14,
                                 color: Colors.grey,
                                 fontWeight: FontWeight.w500,
                               ),
                             ),
                             const SizedBox(height: 24),
                             Padding(
                               padding: const EdgeInsets.symmetric(horizontal: 32),
                               child: _buildProgressBar(),
                             ),
                           ],
                         ),
                       ],
                     ],
                   ),
                 )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Hata: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _syncFromAPI,
                        child: const Text('API\'den Tüm Ürünleri Çek'),
                      ),
                    ],
                  ),
                )
              : _groupedProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'Ürün bulunmuyor',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'API\'den ürün çekmek için yukarıdaki butona tıklayın',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
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
                                    final product = _getDisplayedProducts()[index];
                                    return _buildProductCard(product);
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
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      Text(
                        '${products.length} sonuç',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
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
    final title = product['title'] as String? ?? 'İsimsiz';
    final avgPrice = product['avgPrice'] as double? ?? 0;
    final totalQuantity = product['totalQuantity'] as int? ?? 0;
    final variantCount = product['variantCount'] as int? ?? 1;
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
        
        // Önce productMainId'den maliyet ara
        double costPrice = prefs.getDouble('cost_$productMainId') ?? 0;
        
        // Yoksa varyasyonların maliyetlerinden ortalama al
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
        
        // Kar hesapla
        final result = TrendyolCalculator.calculate(
          satisFiyati: avgPrice,
          alisFiyati: costPrice,
          komisyonOrani: settings['komisyon'] ?? 21.5,
          kdvOrani: settings['kdv'] ?? 10,
          kargoUcreti: settings['kargo'] ?? 77.54,
          stopajOrani: settings['stopaj'] ?? 1.0,
          hizmetBedeli: settings['hizmet'] ?? 13.19,
        );

        final kar = result['kar'] ?? 0;
        final karOrani = result['kar_orani'] ?? 0;
        final karRengi = kar >= 0 ? Colors.green : Colors.red;

        const imageSize = 80.0;
        const spacing = 12.0;
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: InkWell(
            onTap: () => _showProductDetail(product, result, costPrice),
            onLongPress: () => _editCostPrice(productMainId, costPrice),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Resim
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: imageSize,
                        height: imageSize,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const CircularProgressIndicator(),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.image_not_supported, size: 80),
                      ),
                    )
                  else
                    Icon(Icons.image_not_supported, size: imageSize),
                  SizedBox(width: spacing),

                  // Bilgiler
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: spacing * 0.3),
                        Text(
                          'Model: $productMainId',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: spacing * 0.2),
                        Text(
                          'Ort. Satış: ${avgPrice.toStringAsFixed(2)} ₺ | Stok: $totalQuantity',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (variantCount > 1)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '$variantCount varyasyon',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (costPrice > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Maliyet: ${costPrice.toStringAsFixed(2)} ₺',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade400,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Kar bilgisi
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: kar >= 0
                            ? [Colors.green.shade50, Colors.green.shade100]
                            : [Colors.red.shade50, Colors.red.shade100],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: karRengi.withOpacity(0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: karRengi.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${kar.toStringAsFixed(0)} ₺',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: karRengi,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(height: spacing * 0.2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: karRengi.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '%${karOrani.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: karRengi,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
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

  void _showProductDetail(Map<String, dynamic> product, Map<String, double> result, double costPrice) {
    final variants = product['variants'] as List<Map<String, dynamic>>;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product['title'] ?? 'Ürün Detayı'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Model Kodu: ${product['productMainId']}'),
              Text('Varyasyon Sayısı: ${product['variantCount']}'),
              const Divider(),
              _detailRow('Ortalama Satış', '${product['avgPrice']} ₺'),
              _detailRow('Maliyet', '${costPrice.toStringAsFixed(2)} ₺'),
              const Divider(),
              _detailRow('Komisyon', '${result['komisyon']} ₺'),
              _detailRow('Stopaj', '${result['stopaj']} ₺'),
              _detailRow('Hizmet Bedeli', '${result['hizmet_bedeli']} ₺'),
              _detailRow('Kargo Ücreti', '77.54 ₺'),
              const Divider(),
              _detailRow(
                'KAR',
                '${result['kar']} ₺',
                color: (result['kar'] ?? 0) >= 0 ? Colors.green : Colors.red,
                bold: true,
              ),
              _detailRow(
                'Kar Oranı',
                '%${result['kar_orani']}',
                color: (result['kar'] ?? 0) >= 0 ? Colors.green : Colors.red,
              ),
              const Divider(),
              const Text('Varyasyonlar:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...variants.map((v) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${v['barcode']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      '${v['quantity']} adet | ${v['salePrice']} ₺',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              )),
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

  void _editCostPrice(String productMainId, double currentCost) {
    final costController = TextEditingController(text: currentCost.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Maliyet Düzenle - $productMainId'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: costController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Maliyet Fiyatı (₺)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İPTAL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cost = double.tryParse(costController.text) ?? 0;

              final prefs = await SharedPreferences.getInstance();
              await prefs.setDouble('cost_$productMainId', cost);

              setState(() {
                _groupedProducts = _groupProductsByStockCode(cachedProducts);
              });

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Maliyet kaydedildi'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('KAYDET'),
          ),
        ],
      ),
    );
  }

  // Özel loading animasyonu
  Widget _buildLoadingAnimation() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1500),
      builder: (context, value, child) {
        return Column(
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
                    blurRadius: 20 * value,
                    spreadRadius: 5 * value,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  Icons.shopping_bag_outlined,
                  size: 40,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Ürünler Yükleniyor',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lütfen bekleyin...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        );
      },
      onEnd: () {
        // Animasyonu tekrar başlat
        if (_loading) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && _loading) {
              setState(() {});
            }
          });
        }
      },
    );
  }

  // Özel progress bar
  Widget _buildProgressBar() {
    final progress = _totalProgress > 0 ? (_currentProgress / _totalProgress).toDouble() : 0.0;
    
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress >= 1 ? Colors.green : Colors.orange,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '%${(progress * 100).toStringAsFixed(0)} tamamlandı',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: progress >= 1 ? Colors.green : Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
