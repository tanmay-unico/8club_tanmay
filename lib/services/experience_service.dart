import 'package:dio/dio.dart';

import '../models/experience.dart';

class ExperienceService {
  ExperienceService(this._dio);

  final Dio _dio;

  Future<List<Experience>> fetchExperiences() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://staging.chamberofsecrets.8club.co/v1/experiences',
      queryParameters: {
        'active': true,
      },
    );

    final payload = response.data?['data'] as Map<String, dynamic>? ?? {};
    final experiencesJson =
        payload['experiences'] as List<dynamic>? ?? <dynamic>[];

    return experiencesJson
        .map((json) => Experience.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

