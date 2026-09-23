import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../shared_widget/deal_card.dart';
import 'search_deals_controller.dart';

class SearchScreen extends GetView<SearchDealsController> {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          onChanged: controller.onQueryChanged,
          decoration: const InputDecoration(
            hintText: 'Search deals, stores, tags…',
            border: InputBorder.none,
          ),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!controller.hasSearched.value) {
          return Center(
            child: Text('Try "sushi", "bakery" or "vegan"',
                style: TextStyle(color: Colors.grey.shade600)),
          );
        }
        if (controller.results.isEmpty) {
          return Center(
            child: Text('No deals found',
                style: TextStyle(color: Colors.grey.shade600)),
          );
        }
        return ListView.builder(
          itemCount: controller.results.length,
          itemBuilder: (context, index) => DealCard(
            deal: controller.results[index],
            source: 'search',
          ),
        );
      }),
    );
  }
}
