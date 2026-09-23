import 'package:get/get.dart';

import '../service/analytics_service.dart';

/// Logs a screen_view analytics event whenever a page is opened.
class ScreenViewMiddleware extends GetMiddleware {
  @override
  GetPage? onPageCalled(GetPage? page) {
    if (page != null) {
      Get.find<AnalyticsService>()
          .logEvent('screen_view', {'screen': page.name});
    }
    return page;
  }
}
