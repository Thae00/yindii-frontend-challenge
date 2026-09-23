import 'package:get/get.dart';

import '../binding/cart_binding.dart';
import '../binding/deal_details_binding.dart';
import '../binding/home_binding.dart';
import '../binding/map_binding.dart';
import '../binding/orders_binding.dart';
import '../binding/search_binding.dart';
import '../feature/analytics_debug/analytics_debug_screen.dart';
import '../feature/cart/cart_screen.dart';
import '../feature/deal/deal_details_screen.dart';
import '../feature/home/home_screen.dart';
import '../feature/map/map_screen.dart';
import '../feature/order/orders_screen.dart';
import '../feature/search/search_screen.dart';
import '../middleware/screen_view_middleware.dart';

abstract class Routes {
  static const home = '/home';
  static const deal = '/deal';
  static const search = '/search';
  static const map = '/map';
  static const cart = '/cart';
  static const orders = '/orders';
  static const analyticsDebug = '/debug/analytics';

  /// Deep links look like: rescu://open/deal?id=42&source=push
  static String dealRoute(int id, {String source = 'unknown'}) =>
      '$deal?id=$id&source=$source';

  static final pages = <GetPage<dynamic>>[
    GetPage(
      name: home,
      page: () => const HomeScreen(),
      binding: HomeBinding(),
      middlewares: [ScreenViewMiddleware()],
    ),
    GetPage(
      name: deal,
      page: () => const DealDetailsScreen(),
      binding: DealDetailsBinding(),
      middlewares: [ScreenViewMiddleware()],
    ),
    GetPage(
      name: search,
      page: () => const SearchScreen(),
      binding: SearchBinding(),
      middlewares: [ScreenViewMiddleware()],
    ),
    GetPage(
      name: map,
      page: () => const MapScreen(),
      binding: MapBinding(),
      middlewares: [ScreenViewMiddleware()],
    ),
    GetPage(
      name: cart,
      page: () => const CartScreen(),
      binding: CartBinding(),
      middlewares: [ScreenViewMiddleware()],
    ),
    GetPage(
      name: orders,
      page: () => const OrdersScreen(),
      binding: OrdersBinding(),
      middlewares: [ScreenViewMiddleware()],
    ),
    GetPage(
      name: analyticsDebug,
      page: () => const AnalyticsDebugScreen(),
    ),
  ];
}
