import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';

import '../util/log_service.dart';
import 'api_exception.dart';

/// Simulates the Rescu backend. Treat this class as a remote server:
/// it has realistic latency, can fail, and its responses are JSON maps.
///
/// Do NOT "fix" bugs by editing this file — assume you cannot change the
/// backend. (You may read it to understand the API contract.)
class FakeApiService extends GetxService {
  static const int pageSize = 20;

  /// The market this simulated backend serves operates on Asia/Bangkok time
  /// (UTC+7). All instants in API responses are ISO-8601 UTC, like a real API.
  static const int _marketUtcOffsetHours = 7;

  final _rng = Random();
  late final List<Map<String, dynamic>> _stores;
  late final List<Map<String, dynamic>> _deals;
  late final List<Map<String, dynamic>> _orders;
  final Map<String, Map<String, dynamic>> _reservations = {};
  int _mutationCounter = 0;
  int _reservationSeq = 0;

  Future<FakeApiService> init() async {
    final storesRaw = jsonDecode(
            await rootBundle.loadString('assets/data/stores.json'))
        as List<dynamic>;
    final dealsRaw =
        jsonDecode(await rootBundle.loadString('assets/data/deals.json'))
            as List<dynamic>;
    final ordersRaw =
        jsonDecode(await rootBundle.loadString('assets/data/orders.json'))
            as List<dynamic>;

    _stores = storesRaw
        .map((s) => _enrichStore(s as Map<String, dynamic>))
        .toList();
    final storesById = {for (final s in _stores) s['id'] as int: s};
    _deals = dealsRaw
        .map((d) =>
            _enrichDeal(d as Map<String, dynamic>, storesById))
        .toList();
    _orders = ordersRaw
        .map((o) => _enrichOrder(o as Map<String, dynamic>))
        .toList();

    LogService.log(
        'FakeApiService ready: ${_stores.length} stores, ${_deals.length} deals');
    return this;
  }

  // ---------------------------------------------------------------------------
  // Public API ("endpoints")
  // ---------------------------------------------------------------------------

  /// GET /deals?page=N — paginated deal feed.
  Future<Map<String, dynamic>> getDeals({int page = 1}) async {
    await _latency(min: 250, max: 950);
    LogService.log('GET /deals?page=$page');
    final start = (page - 1) * pageSize;
    final items = _deals.skip(start).take(pageSize).toList();
    return {
      'items': items,
      'page': page,
      'totalPages': (_deals.length / pageSize).ceil(),
    };
  }

  /// GET /deals/flash — all deals currently in a flash sale.
  Future<List<Map<String, dynamic>>> getFlashDeals() async {
    await _latency(min: 200, max: 600);
    LogService.log('GET /deals/flash');
    return _deals.where((d) => d['flashSaleEndsAt'] != null).toList();
  }

  /// GET /deals/:id
  Future<Map<String, dynamic>> getDealById(int id) async {
    await _latency(min: 200, max: 700);
    LogService.log('GET /deals/$id');
    final deal = _deals.firstWhereOrNull((d) => d['id'] == id);
    if (deal == null) {
      throw const ApiException('Deal not found', statusCode: 404);
    }
    return deal;
  }

  /// GET /deals/search?q=... — like most real backends, broad queries are
  /// slower than specific ones.
  Future<List<Map<String, dynamic>>> searchDeals(String query) async {
    final broadness = max(0, 1200 - query.trim().length * 280);
    final ms = 180 + broadness + _rng.nextInt(300);
    await Future.delayed(Duration(milliseconds: ms));
    LogService.log('GET /deals/search?q=$query (${ms}ms)');
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _deals.where((d) {
      final name = (d['name'] as String).toLowerCase();
      final store = (d['storeName'] as String).toLowerCase();
      final tags = (d['tags'] as List).join(' ').toLowerCase();
      return name.contains(q) || store.contains(q) || tags.contains(q);
    }).toList();
  }

  /// GET /stores
  Future<List<Map<String, dynamic>>> getStores() async {
    await _latency(min: 300, max: 800);
    LogService.log('GET /stores');
    return _stores;
  }

  /// GET /orders
  Future<List<Map<String, dynamic>>> getOrders() async {
    await _latency(min: 250, max: 800);
    LogService.log('GET /orders');
    return _orders;
  }

  /// POST /reservations — places a 5 minute hold on stock.
  /// Fails intermittently (stock contention), like production does.
  Future<Map<String, dynamic>> reserveDeal(int dealId,
      {int quantity = 1}) async {
    await _latency(min: 350, max: 1100);
    _mutationCounter++;
    LogService.log('POST /reservations dealId=$dealId qty=$quantity');
    if (_mutationCounter % 5 == 3) {
      throw const ApiException(
          'Could not reserve: someone grabbed the last one. Try again.',
          statusCode: 409);
    }
    final deal = _deals.firstWhereOrNull((d) => d['id'] == dealId);
    if (deal == null) {
      throw const ApiException('Deal not found', statusCode: 404);
    }
    if ((deal['quantityLeft'] as int) < quantity) {
      throw const ApiException('Not enough stock left', statusCode: 409);
    }
    final id = 'res_${++_reservationSeq}';
    final reservation = {
      'id': id,
      'dealId': dealId,
      'quantity': quantity,
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
    };
    _reservations[id] = reservation;
    return reservation;
  }

  /// DELETE /reservations/:id
  Future<void> releaseReservation(String reservationId) async {
    await _latency(min: 200, max: 600);
    LogService.log('DELETE /reservations/$reservationId');
    _reservations.remove(reservationId);
  }

  /// POST /checkout — items is a list of {dealId, quantity, reservationId?}.
  /// Rejects expired/unknown reservation ids. Fails intermittently.
  Future<Map<String, dynamic>> checkout(
      List<Map<String, dynamic>> items) async {
    await _latency(min: 500, max: 1400);
    _mutationCounter++;
    LogService.log('POST /checkout items=${items.length}');
    if (_mutationCounter % 5 == 3) {
      throw const ApiException(
          'Payment gateway timeout. Your card was not charged.',
          statusCode: 502);
    }
    for (final item in items) {
      final resId = item['reservationId'] as String?;
      if (resId != null) {
        final res = _reservations[resId];
        if (res == null) {
          throw const ApiException('Unknown reservation', statusCode: 410);
        }
        final expires = DateTime.parse(res['expiresAt'] as String);
        if (DateTime.now().toUtc().isAfter(expires)) {
          throw const ApiException(
              'Reservation expired — stock was released', statusCode: 410);
        }
      }
    }
    num total = 0;
    for (final item in items) {
      final deal =
          _deals.firstWhereOrNull((d) => d['id'] == item['dealId']);
      if (deal == null) continue;
      total += (deal['price'] as num) * (item['quantity'] as int? ?? 1);
      deal['quantityLeft'] =
          max(0, (deal['quantityLeft'] as int) - (item['quantity'] as int? ?? 1));
    }
    final order = {
      'id': 9100 + _mutationCounter,
      'dealId': items.isEmpty ? 0 : items.first['dealId'],
      'dealName': 'Order #${9100 + _mutationCounter}',
      'storeName': 'Multiple stores',
      'imageUrl': 'https://picsum.photos/seed/order$_mutationCounter/1600/1200',
      'status': 'CONFIRMED',
      'quantity': items.fold<int>(0, (a, b) => a + (b['quantity'] as int? ?? 1)),
      'total': total,
      'currencyCode': 'THB',
      'pickupStart': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 30))
          .toIso8601String(),
      'pickupEnd': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 150))
          .toIso8601String(),
    };
    _orders.insert(0, order);
    return order;
  }

  /// POST /analytics/batch — accepts a batch of analytics events.
  Future<void> sendAnalyticsBatch(List<Map<String, dynamic>> events) async {
    await _latency(min: 150, max: 500);
    LogService.log('POST /analytics/batch events=${events.length}');
  }

  // ---------------------------------------------------------------------------
  // Internals ("server-side" data synthesis)
  // ---------------------------------------------------------------------------

  Future<void> _latency({required int min, required int max}) =>
      Future.delayed(Duration(milliseconds: min + _rng.nextInt(max - min)));

  /// Builds today's pickup window for a store from its local opening hours and
  /// returns UTC instants. Overnight windows (e.g. 22:00–01:00) end on the
  /// next calendar day. Windows that already fully ended roll to tomorrow.
  Map<String, String> _pickupWindowFor(Map<String, dynamic> store) {
    final nowUtc = DateTime.now().toUtc();
    final nowMarket = nowUtc.add(const Duration(hours: _marketUtcOffsetHours));

    DateTime marketToUtc(DateTime marketWallClock) =>
        marketWallClock.subtract(const Duration(hours: _marketUtcOffsetHours));

    var startMarket = DateTime.utc(nowMarket.year, nowMarket.month,
        nowMarket.day, store['pickupStartHour'] as int,
        store['pickupStartMinute'] as int);
    var endMarket = DateTime.utc(nowMarket.year, nowMarket.month, nowMarket.day,
        store['pickupEndHour'] as int, store['pickupEndMinute'] as int);
    if (!endMarket.isAfter(startMarket)) {
      endMarket = endMarket.add(const Duration(days: 1)); // overnight window
    }
    if (marketToUtc(endMarket).isBefore(nowUtc)) {
      // Window fully over for today -> serve tomorrow's window.
      startMarket = startMarket.add(const Duration(days: 1));
      endMarket = endMarket.add(const Duration(days: 1));
    }
    return {
      'start': marketToUtc(startMarket).toIso8601String(),
      'end': marketToUtc(endMarket).toIso8601String(),
    };
  }

  Map<String, dynamic> _enrichStore(Map<String, dynamic> raw) {
    return {
      ...raw,
      'imageUrl': 'https://picsum.photos/seed/${raw['imageSeed']}/1600/1200',
      'pickupWindow': _pickupWindowFor(raw),
    };
  }

  Map<String, dynamic> _enrichDeal(
      Map<String, dynamic> raw, Map<int, Map<String, dynamic>> storesById) {
    final store = storesById[raw['storeId'] as int]!;
    final flashMinutes = raw['flashSaleMinutes'] as int?;
    return {
      ...raw,
      'imageUrl': 'https://picsum.photos/seed/${raw['imageSeed']}/1600/1200',
      'storeName': store['name'],
      'storeAddress': store['address'],
      'currencyCode': store['currencyCode'],
      'lat': store['lat'],
      'lng': store['lng'],
      'pickupWindow': store['pickupWindow'],
      'flashSaleEndsAt': flashMinutes == null
          ? null
          : DateTime.now()
              .toUtc()
              .add(Duration(minutes: flashMinutes))
              .toIso8601String(),
    };
  }

  Map<String, dynamic> _enrichOrder(Map<String, dynamic> raw) {
    final start = DateTime.now()
        .toUtc()
        .add(Duration(minutes: raw['pickupInMinutes'] as int));
    return {
      ...raw,
      'imageUrl': 'https://picsum.photos/seed/${raw['imageSeed']}/1600/1200',
      'pickupStart': start.toIso8601String(),
      'pickupEnd': start.add(const Duration(hours: 2)).toIso8601String(),
    };
  }
}
