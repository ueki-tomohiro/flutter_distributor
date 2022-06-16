import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:app_package_maker/app_package_maker.dart';

import 'make_deb_config.dart';

class AppPackageMakerDeb extends AppPackageMaker {
  String get name => 'deb';
  String get platform => 'linux';
  String get packageFormat => 'deb';

  bool get isSupportedOnCurrentPlatform => Platform.isLinux;

  @override
  Future<MakeConfig> loadMakeConfig(
      Directory outputDirectory, Map<String, dynamic>? makeArguments) async {
    final makeConfig =
        await super.loadMakeConfig(outputDirectory, makeArguments);
    return MakeDebConfig.fromJson(
            loadMakeConfigYaml("linux/packaging/deb/make_config.yaml"))
        .copyWith(makeConfig);
  }

  @override
  Future<MakeResult> make(
    Directory appDirectory, {
    required Directory outputDirectory,
    Map<String, dynamic>? makeArguments,
    void Function(List<int> data)? onProcessStdOut,
    void Function(List<int> data)? onProcessStdErr,
  }) async {
    MakeDebConfig makeConfig = await loadMakeConfig(
      outputDirectory,
      makeArguments,
    ) as MakeDebConfig;

    final files = makeConfig.toFilesString();

    Directory packagingDirectory = makeConfig.packagingDirectory;

    /// Need to create following directories
    /// /DEBIAN
    /// /usr/share/$appName
    /// /usr/share/applications
    /// /usr/share/icons/hicolor/128x128/apps
    /// /usr/share/icons/hicolor/256x256/apps

    final debianDir = path.join(packagingDirectory.path, "DEBIAN");
    final applicationsDir =
        path.join(packagingDirectory.path, "usr/share/applications");
    final icon128Dir = path.join(
      packagingDirectory.path,
      "usr/share/icons/hicolor/128x128/apps",
    );
    final icon256Dir = path.join(
      packagingDirectory.path,
      "usr/share/icons/hicolor/256x256/apps",
    );
    final mkdirProcess = Process.runSync("mkdir", [
      "-p",
      debianDir,
      path.join(packagingDirectory.path, "usr/share", makeConfig.appName),
      applicationsDir,
      if (makeConfig.icon != null) ...[icon128Dir, icon256Dir],
    ]);

    if (mkdirProcess.exitCode != 0) throw MakeError();

    if (makeConfig.icon != null) {
      final iconFile = File(makeConfig.icon!);
      if (!iconFile.existsSync())
        throw MakeError("provided icon ${makeConfig.icon} path wasn't found");

      await iconFile
          .copy(path.join(icon128Dir, path.basename(makeConfig.icon!)));
      await iconFile
          .copy(path.join(icon256Dir, path.basename(makeConfig.icon!)));
    }

    // create & write the files got from makeConfig
    final controlFile = File(path.join(debianDir, "control"));
    final postinstFile = File(path.join(debianDir, "postinst"));
    final postrmFile = File(path.join(debianDir, "postrm"));
    final desktopEntryFile =
        File(path.join(applicationsDir, "${makeConfig.appName}.desktop"));

    if (!controlFile.existsSync()) controlFile.createSync();
    if (!postinstFile.existsSync()) postinstFile.createSync();
    if (!postrmFile.existsSync()) postrmFile.createSync();
    if (!desktopEntryFile.existsSync()) desktopEntryFile.createSync();

    await controlFile.writeAsString(files["CONTROL"]!);
    await desktopEntryFile.writeAsString(files["DESKTOP"]!);
    await postinstFile.writeAsString(files["postinst"]!);
    await postrmFile.writeAsString(files["postrm"]!);

    // give execution permission to shell scripts
    Process.runSync('chmod', ["+x", postinstFile.path, postrmFile.path]);

    // copy the application binary to /usr/share/$appName
    Process.runSync('cp', [
      '-fr',
      '${appDirectory.path}/.',
      '${packagingDirectory.path}/usr/share/${makeConfig.appName}/',
    ]);

    Process process = await Process.start('dpkg-deb', [
      '--build',
      '--root-owner-group',
      packagingDirectory.path,
      makeConfig.outputFile.path
    ]);

    process.stdout.listen(onProcessStdOut);
    process.stderr.listen(onProcessStdErr);

    int exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw MakeError();
    }

    packagingDirectory.deleteSync(recursive: true);
    return MakeResult(makeConfig);
  }
}
