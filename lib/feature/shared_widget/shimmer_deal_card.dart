import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerDealCard extends StatelessWidget {
  const ShimmerDealCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.white,
      elevation: 0.5,
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 160, color: Colors.white),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: 180, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 120, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 220, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
