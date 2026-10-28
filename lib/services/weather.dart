import 'dart:convert';
import 'package:http/http.dart' as http;

class KigaliWeather {
  KigaliWeather(this.temperature, this.wind);
  final double temperature, wind;
}

class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  Future<KigaliWeather> fetch() async {
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=-1.9536&longitude=30.0606&current=temperature_2m,wind_speed_10m&timezone=Africa%2FKigali');
    final response = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw Exception('Weather service unavailable (${response.statusCode})');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>;
    return KigaliWeather((current['temperature_2m'] as num).toDouble(),
        (current['wind_speed_10m'] as num).toDouble());
  }
  void close() => _client.close();
}
