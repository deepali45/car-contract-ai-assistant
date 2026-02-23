// lib/services/contract_analysis_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import 'api_service.dart';
import 'web_download_helper.dart'; // Using conditional import helper

class DocumentContractAnalysisResult {
  final String fileName;
  final String riskLevel;
  final List<String> hiddenFees;
  final List<String> penalties;
  final List<String> unfairClauses;
  final String summary;

  DocumentContractAnalysisResult({
    required this.fileName,
    this.riskLevel = 'N/A',
    this.hiddenFees = const [],
    this.penalties = const [],
    this.unfairClauses = const [],
    this.summary = 'No analysis available.',
  });

  factory DocumentContractAnalysisResult.fromJson(Map<String, dynamic> json) {
    return DocumentContractAnalysisResult(
      fileName: json['file_name'] as String? ?? 'Unknown File',
      riskLevel: json['risk_level'] as String? ?? 'N/A',
      hiddenFees: List<String>.from(json['hidden_fees'] as List? ?? []),
      penalties: List<String>.from(json['penalties'] as List? ?? []),
      unfairClauses: List<String>.from(json['unfair_clauses'] as List? ?? []),
      summary: json['summary'] as String? ?? 'No summary provided.',
    );
  }
}

class ContractAnalysisService {
  final ApiService _apiService;

  ContractAnalysisService(this._apiService);

  Future<DocumentContractAnalysisResult> analyzeContract({
    required String fileName,
    required Uint8List fileBytes,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/analyze_contract');
    
    Future<http.StreamedResponse> sendRequest() async {
      var request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ));
      
      // Ensure headers are set if needed for production
      request.headers.addAll({
        'Accept': 'application/json',
      });

      return await request.send().timeout(AppConfig.timeoutDuration);
    }

    int retryCount = 0;

    while (true) {
      try {
        if (kDebugMode) {
          print('Uploading to $uri (Attempt ${retryCount + 1})');
        }
        
        final response = await sendRequest();

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final responseBody = await response.stream.bytesToString();
          final jsonResponse = json.decode(responseBody);
          return DocumentContractAnalysisResult.fromJson(jsonResponse);
        } else {
          final errorBody = await response.stream.bytesToString();
          throw ApiException('Server error (${response.statusCode}): $errorBody', statusCode: response.statusCode);
        }
      } catch (e) {
        if (retryCount < AppConfig.retryCount && (e is TimeoutException || e is http.ClientException)) {
          retryCount++;
          await Future.delayed(AppConfig.retryDelay);
          continue;
        }
        
        if (e is TimeoutException) {
          throw ApiException('Analysis request timed out. The server might be busy or starting up.');
        }
        throw ApiException('Network error: ${e.toString()}');
      }
    }
  }

  Future<void> downloadAnalysis(DocumentContractAnalysisResult result) async {
    // Encode query parameters properly for the GET request
    final queryParams = {
      'risk_level': result.riskLevel,
      'summary': result.summary,
      'penalties': result.penalties.join('\n'),
    };
    
    final uri = Uri.parse('${AppConfig.baseUrl}/download-analysis').replace(queryParameters: queryParams);

    try {
      if (kDebugMode) {
        print('Triggering PDF download: $uri');
      }
      // Use the web-safe conditional download helper
      downloadFile(uri.toString(), 'Contract_Analysis.pdf');
    } catch (e) {
      throw ApiException('Failed to start download: $e');
    }
  }
}
