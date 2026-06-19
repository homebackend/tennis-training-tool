/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../constants.dart' as constants;
import '../../tool.dart';

part 'app_initialization_state.dart';

class AppInitializationCubit extends Cubit<AppInitializationStatus> {
  final String baseGitHubUrl =
      'https://api.github.com/repos/${constants.githubOrganization}/${constants.githubRepo}';

  final Map<String, String> _githubHeaders = const {
    'Accept': 'application/vnd.github.v3+json',
  };

  AppInitializationCubit()
    : super(AppInitializationStatus(AppInitializationState.initialization));

  Future<void> initialize() async {
    emit(AppInitializationStatus(AppInitializationState.initialization));
    if (isMobilePlatform() || isDesktopPlatform()) {
      await checkUpdateRequired();
    } else {
      emitInitialized();
    }
  }

  void emitInitialized() {
    emit(AppInitializationStatus(AppInitializationState.initialized));
  }

  Future<void> checkUpdateRequired() async {
    try {
      final currentInfo = await PackageInfo.fromPlatform();
      final List<dynamic> releases = await _fetchGitHubReleases();

      if (releases.isEmpty) {
        emitInitialized();
        return;
      }

      final Map<String, dynamic> latestRelease = releases.first;
      final String rawLatestTag = latestRelease['tag_name'] ?? '';
      final Version latestSemVer = _parseTagToVersion(rawLatestTag);

      final bool isUpdateAvailable = await _evaluatePlatformUpdate(
        currentInfo: currentInfo,
        latestSemVer: latestSemVer,
        rawLatestTag: rawLatestTag,
      );

      if (isUpdateAvailable) {
        final String baseTag = 'v${currentInfo.version}';
        final String fallbackUrl = latestRelease['html_url'] ?? baseGitHubUrl;

        final List<String> results = await Future.wait([
          _generateCommitChangelog(baseTag: baseTag, headTag: rawLatestTag),
          _resolveTargetedDownloadUrl(latestRelease, fallbackUrl),
        ]);

        final String changelog = results[0];
        final String downloadLink = results[1];

        _emitPlatformUpdateState(
          rawLatestTag: rawLatestTag,
          changelog: changelog,
          downloadLink: downloadLink,
        );
      } else {
        emitInitialized();
      }
    } catch (e) {
      log('Update validation exception: $e');
      emit(
        AppInitializationStatus(
          AppInitializationState.updateCheckFailed,
          error: e.toString(),
        ),
      );
    }
  }

  Future<List<dynamic>> _fetchGitHubReleases() async {
    final response = await http.get(
      Uri.parse('$baseGitHubUrl/releases?per_page=10'),
      headers: _githubHeaders,
    );
    if (response.statusCode != 200) {
      throw Exception('GitHub API returned status code ${response.statusCode}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<bool> _evaluatePlatformUpdate({
    required PackageInfo currentInfo,
    required Version latestSemVer,
    required String rawLatestTag,
  }) async {
    if (!isMobilePlatform()) {
      return _evaluateDesktopUpdate(currentInfo, latestSemVer);
    } else {
      return _evaluateAndroidUpdate(currentInfo, latestSemVer, rawLatestTag);
    }
  }

  bool _evaluateDesktopUpdate(PackageInfo currentInfo, Version latestSemVer) {
    final Version currentSemVer = Version.parse(currentInfo.version);
    return currentSemVer < latestSemVer;
  }

  Future<bool> _evaluateAndroidUpdate(
    PackageInfo currentInfo,
    Version latestSemVer,
    String rawLatestTag,
  ) async {
    final Version currentSemVer = Version.parse(currentInfo.version);
    if (latestSemVer <= currentSemVer) return false;

    final int remoteBuildNumber = await _fetchRemoteBuildNumber(rawLatestTag);
    final int currentBuildNumber = int.parse(currentInfo.buildNumber);

    return currentBuildNumber < remoteBuildNumber;
  }

  Future<int> _fetchRemoteBuildNumber(String tag) async {
    final String url =
        'https://raw.githubusercontent.com/${constants.githubOrganization}/${constants.githubRepo}/$tag/pubspec.yaml';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to pull raw pubspec.yaml for tag $tag');
    }

    final RegExp versionRegex = RegExp(
      r'^version:\s*([^\s]+)',
      multiLine: true,
    );
    final Match? match = versionRegex.firstMatch(response.body);

    if (match != null && match.group(1)!.contains('+')) {
      final String remoteBuildStr = match.group(1)!.split('+').last.trim();
      return int.parse(remoteBuildStr);
    }

    throw Exception(
      'No structural version build metadata found in remote pubspec.yaml',
    );
  }

  Future<String> _resolveTargetedDownloadUrl(
    Map<String, dynamic> latestRelease,
    String fallbackUrl,
  ) async {
    final String? assetsUrl = latestRelease['assets_url'];
    if (assetsUrl == null || assetsUrl.isEmpty) return fallbackUrl;

    try {
      final response = await http.get(
        Uri.parse(assetsUrl),
        headers: _githubHeaders,
      );
      if (response.statusCode != 200) return fallbackUrl;

      final List<dynamic> assetsList = jsonDecode(response.body);
      final String targetAssetName = _determineTargetAssetName();

      for (var asset in assetsList) {
        if (asset['name'] == targetAssetName) {
          return asset['browser_download_url'] ?? fallbackUrl;
        }
      }
    } catch (e) {
      log('Failed resolving direct binary asset download links: $e');
    }

    return fallbackUrl;
  }

  String _determineTargetAssetName() {
    if (isAndroidPlatform()) return 'netr-android.apk';
    if (isWindowsPlatform()) return 'netr-windows-x64.zip';
    if (isLinuxPlatform()) {
      if (isArchLinuxDistribution()) {
        return 'netr-linux-x64.pkg.tar.zst';
      }
      return 'netr-linux-x64.tar.gz';
    }
    return '';
  }

  Future<String> _generateCommitChangelog({
    required String baseTag,
    required String headTag,
  }) async {
    final String compareUrl = '$baseGitHubUrl/compare/$baseTag...$headTag';

    try {
      final response = await http.get(
        Uri.parse(compareUrl),
        headers: _githubHeaders,
      );
      if (response.statusCode != 200) {
        return '### Updates Available\n* Detailed changelog list unretrievable.';
      }

      final Map<String, dynamic> compareData = jsonDecode(response.body);
      final List<dynamic> commits = compareData['commits'] ?? [];

      final StringBuffer buffer = StringBuffer()
        ..writeln('### Changes since version $baseTag:\n');
      if (commits.isEmpty) {
        buffer.writeln('* No direct commit descriptions logged.');
      } else {
        for (var entry in commits.reversed) {
          final Map<String, dynamic> commitMap = entry['commit'] ?? {};
          final String title = (commitMap['message'] ?? '')
              .toString()
              .split('\n')
              .first
              .trim();
          final String author = commitMap['author']?['name'] ?? 'Anonymous';

          if (title.isNotEmpty) buffer.writeln('* $title (by $author)');
        }
      }
      return buffer.toString().trim();
    } catch (_) {
      return '### Updates Available\n* Failed generating commit data streams.';
    }
  }

  void _emitPlatformUpdateState({
    required String rawLatestTag,
    required String changelog,
    required String downloadLink,
  }) {
    AppInitializationState state = isAndroidPlatform()
        ? AppInitializationState.updateApp
        : AppInitializationState.showUpdateDetails;

    log('${state.toString()}: $rawLatestTag/$downloadLink');

    emit(
      AppInitializationStatus(
        state,
        baseUrl: '$baseGitHubUrl/releases?per_page=10',
        downloadUrl: downloadLink,
        latestVersion: rawLatestTag,
        changeLog: changelog,
      ),
    );
  }

  Version _parseTagToVersion(String tag) {
    final String cleanTag = tag.startsWith('v') ? tag.substring(1) : tag;
    return Version.parse(cleanTag);
  }
}
