import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class DatabaseHelper {
  static Database? _database;
  static const String _tableName = 'products';
  static const int _version = 1;

  // Singleton pattern
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'trendyol_products.db');

    return await openDatabase(
      path,
      version: _version,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            barcode TEXT PRIMARY KEY,
            productMainId TEXT,
            stockCode TEXT,
            title TEXT,
            quantity INTEGER,
            salePrice REAL,
            listPrice REAL,
            price REAL,
            images TEXT,
            lastUpdated INTEGER
          )
        ''');
      },
    );
  }

  // Ürünleri kaydet
  Future<void> saveProducts(List<Map<String, dynamic>> products) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (var product in products) {
      final barcode = product['barcode'] as String?;
      if (barcode == null || barcode.isEmpty) continue;

      batch.insert(
        _tableName,
        {
          'barcode': barcode,
          'productMainId': product['productMainId'] as String? ?? '',
          'stockCode': product['stockCode'] as String? ?? '',
          'title': product['title'] as String? ?? '',
          'quantity': product['quantity'] as int? ?? 0,
          'salePrice': product['salePrice'] as num? ?? 0,
          'listPrice': product['listPrice'] as num? ?? 0,
          'price': product['price'] as num? ?? 0,
          'images': jsonEncode(product['images'] ?? []),
          'lastUpdated': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // Ürünleri yükle
  Future<List<Map<String, dynamic>>> loadProducts() async {
    final db = await database;
    final maps = await db.query(_tableName);

    return maps.map((map) {
      return {
        'barcode': map['barcode'],
        'productMainId': map['productMainId'],
        'stockCode': map['stockCode'],
        'title': map['title'],
        'quantity': map['quantity'],
        'salePrice': map['salePrice'],
        'listPrice': map['listPrice'],
        'price': map['price'],
        'images': jsonDecode(map['images'] as String),
      };
    }).toList();
  }

  // Belirli bir ürünü güncelle
  Future<void> updateProduct(String barcode, Map<String, dynamic> updates) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final updateData = <String, dynamic>{
      'lastUpdated': now,
    };

    if (updates.containsKey('quantity')) {
      updateData['quantity'] = updates['quantity'];
    }
    if (updates.containsKey('salePrice')) {
      updateData['salePrice'] = updates['salePrice'];
    }
    if (updates.containsKey('listPrice')) {
      updateData['listPrice'] = updates['listPrice'];
    }
    if (updates.containsKey('price')) {
      updateData['price'] = updates['price'];
    }

    await db.update(
      _tableName,
      updateData,
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
  }

  // Veritabanını temizle
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(_tableName);
  }

  // Son güncelleme zamanını al
  Future<DateTime?> getLastUpdateTime() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(lastUpdated) as lastUpdated FROM $_tableName',
    );
    
    if (result.isNotEmpty && result.first['lastUpdated'] != null) {
      final timestamp = result.first['lastUpdated'] as int;
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    
    return null;
  }

  // Veritabanını kapat
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
