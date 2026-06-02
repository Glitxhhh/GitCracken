import * as os from "os";
import * as path from "path";

import * as asar from "@electron/asar";
import * as diff from "diff";
import * as fs from "fs-extra";
import natsort from "natsort";

import {baseDir} from "../global";
import {CURRENT_PLATFORM, Platforms} from "./platform";

/**
 * Regex-based patch entry (version-agnostic alternative to unified diffs)
 */
export interface IRegexPatch {
  /** Human-readable description */
  description: string;
  /** File path inside the asar, relative to app root */
  file: string;
  /** Regex pattern to find (string form, compiled with 's' flag) */
  find: string;
  /** Replacement string (supports $1 etc. capture groups) */
  replace: string;
  /** If this string is already present in the file, skip the patch */
  skipIfPresent?: string;
  /** If false, log a warning instead of throwing when the pattern is not found (default: true) */
  required?: boolean;
}

/**
 * Patcher options
 */
export interface IPatcherOptions {
  readonly asar?: string;
  readonly dir?: string;
  readonly features: string[];
}

/**
 * Patcher
 */
export class Patcher {
  private static findAsarUnix(...files: string[]): string | undefined {
    return files.find((file) => fs.existsSync(file));
  }

  private static findAsarLinux(): string | undefined {
    return Patcher.findAsarUnix(
      "/opt/gitkraken/resources/app.asar",
      "/usr/share/gitkraken/resources/app.asar",
    );
  }

  private static findAsarWindows(): string | undefined {
    const username = os.userInfo().username;
    const searchRoots = [
      path.join(os.homedir(), "AppData/Local/gitkraken"),
      path.join("C:/ProgramData", username, "gitkraken"),
      path.join(os.homedir(), "AppData/Local/Programs/gitkraken"),
    ];
    for (const root of searchRoots) {
      if (!fs.existsSync(root)) continue;
      const apps = fs
        .readdirSync(root)
        .filter((item) => item.match(/^app-\d+\.\d+\.\d+$/));
      const appDir = apps.sort(natsort({desc: true}))[0];
      if (!appDir) continue;
      const asarPath = path.join(root, appDir, "resources/app.asar");
      if (fs.existsSync(asarPath)) return asarPath;
    }
    return undefined;
  }

  private static findAsarMacOS(): string | undefined {
    return Patcher.findAsarUnix(
      "/Applications/GitKraken.app/Contents/Resources/app.asar",
    );
  }

  private static findAsar(dir?: string): string | undefined {
    if (dir) {
      return path.normalize(dir) + ".asar";
    }
    switch (CURRENT_PLATFORM) {
      case Platforms.linux:
        return Patcher.findAsarLinux();
      case Platforms.windows:
        return Patcher.findAsarWindows();
      case Platforms.macOS:
        return Patcher.findAsarMacOS();
    }
  }

  private static findDir(asarFile: string): string {
    return path.join(
      path.dirname(asarFile),
      path.basename(asarFile, path.extname(asarFile)),
    );
  }

  private readonly _asar: string;
  private readonly _dir: string;
  private readonly _features: string[];

  public constructor(options: IPatcherOptions) {
    const maybeAsar = options.asar || Patcher.findAsar(options.dir);
    if (!maybeAsar) {
      throw new Error("Can't find app.asar!");
    }
    this._asar = maybeAsar;
    this._dir = options.dir || Patcher.findDir(this.asar);
    this._features = options.features;
    if (!this.features.length) {
      throw new Error("Features is empty!");
    }
  }

  public get asar(): string { return this._asar; }
  public get dir(): string { return this._dir; }
  public get features(): string[] { return this._features; }

  public backupAsar(): string {
    const backup = `${this.asar}.${new Date().getTime()}.backup`;
    fs.copySync(this.asar, backup);
    return backup;
  }

  public unpackAsar(): void {
    asar.extractAll(this.asar, this.dir);
  }

  public async packDirAsync(): Promise<void> {
    await asar.createPackage(this.dir, this.asar);
  }

  public removeDir(): void {
    fs.removeSync(this.dir);
  }

  public patchDir(): void {
    for (const feature of this.features) {
      this.patchDirWithFeature(feature);
    }
  }

  private patchDirWithFeature(feature: string): void {
    // Try regex patches first (.json), fall back to unified diffs (.diff)
    const jsonPath = path.join(baseDir, "patches", `${feature}.json`);
    const diffPath = path.join(baseDir, "patches", `${feature}.diff`);

    if (fs.existsSync(jsonPath)) {
      const patches: IRegexPatch[] = fs.readJSONSync(jsonPath);
      for (const patch of patches) {
        this.applyRegexPatch(patch);
      }
    } else if (fs.existsSync(diffPath)) {
      const patches = diff.parsePatch(fs.readFileSync(diffPath, "utf8"));
      for (const patch of patches) {
        this.patchDirWithPatch(patch);
      }
    } else {
      throw new Error(`No patch file found for feature: ${feature}`);
    }
  }

  private applyRegexPatch(patch: IRegexPatch): void {
    const filePath = path.join(this.dir, patch.file);
    if (!fs.existsSync(filePath)) {
      throw new Error(`Patch target not found: ${patch.file}`);
    }
    let source = fs.readFileSync(filePath, "utf8");
    if (patch.skipIfPresent && source.includes(patch.skipIfPresent)) {
      console.log(`  [skip] ${patch.description} (already applied)`);
      return;
    }
    const regex = new RegExp(patch.find, "s");
    if (!regex.test(source)) {
      if (patch.required === false) {
        console.warn(`  [warn] Pattern not found (skipped): ${patch.description}`);
        return;
      }
      throw new Error(
        `Regex pattern not found in ${patch.file}: ${patch.description}\n` +
        `Pattern: ${patch.find}`,
      );
    }
    source = source.replace(regex, patch.replace);
    fs.writeFileSync(filePath, source, "utf8");
    console.log(`  [ok]   ${patch.description}`);
  }

  private patchDirWithPatch(patch: diff.ParsedDiff): void {
    const sourceData = fs.readFileSync(
      path.join(this.dir, patch.oldFileName!),
      "utf8",
    );
    const sourcePatchedData = diff.applyPatch(sourceData, patch);
    if (sourcePatchedData === false) {
      throw new Error(`Can't patch ${patch.oldFileName}`);
    }
    if (patch.oldFileName !== patch.newFileName) {
      fs.unlinkSync(path.join(this.dir, patch.oldFileName!));
    }
    fs.writeFileSync(
      path.join(this.dir, patch.newFileName!),
      sourcePatchedData,
      "utf8",
    );
  }
}
