/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

const String appName = 'Tennis Training Tool';
const String appIcon = 'assets/app_logo.png';
const String githubOrganization = String.fromEnvironment(
  'GH_OWNER',
  defaultValue: 'homebackend',
);
const String githubRepo = String.fromEnvironment(
  'GH_REPO',
  defaultValue: 'tennis-training-tool',
);
const String upgradeFileName = 'app-release.apk';
