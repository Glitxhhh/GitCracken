# GitCracken

GitKraken patcher for non-commercial use. Works on Windows, Linux, macOS.

## Quick start

### Windows — one-liner (no clone needed)

```powershell
iwr -useb https://raw.githubusercontent.com/Glitxhhh/GitCracken/dev/patch.ps1 | iex
```

> If PowerShell blocks scripts, run this first, then retry:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
> ```

### Linux / macOS — one-liner (no clone needed)

```bash
curl -sL https://raw.githubusercontent.com/Glitxhhh/GitCracken/dev/patch.sh | bash
```

### Run from a local clone

```powershell
# Windows
.\patch.ps1
```

```bash
# Linux / macOS
chmod +x patch.sh && ./patch.sh
```

That's it. The script installs dependencies, builds, and patches GitKraken automatically.  
After it finishes — re-launch GitKraken and re-login to activate the license.

---

## Options

```powershell
# Windows — specific feature
.\patch.ps1 -Feature standalone

# Windows — point at a specific asar (if auto-detect fails)
.\patch.ps1 -Asar "C:\Users\You\AppData\Local\gitkraken\app-12.1.1\resources\app.asar"
```

```bash
# Linux/macOS — specific feature
./patch.sh standalone

# Linux/macOS — point at a specific asar
./patch.sh pro /path/to/app.asar
```

## Features

| Feature | What it does |
|---|---|
| `pro` *(default)* | Injects `['enterprise', 'pro', 'advanced', 'teamsLicense']` into the profile response |
| `standalone` | Sets clientType=STANDALONE + hardcodes license in snapshot |
| `selfhosted` | Sets clientType=ENTERPRISE |
| `individual` | Injects individual features into the renderer edm response |
| `development` | Sets run mode to development |
| `staging` | Sets run mode to staging |

## Requirements

- Node.js v16 or later ([nodejs.org](https://nodejs.org))
- yarn or npm (npm ships with Node.js)

## Verified versions

| Version range | Status |
|---|---|
| 2.1.0 – 5.x | ✔ best-effort — direct `RegistrationActions.js` + `enterprise.js` patch |
| 6.5.x | ✔ best-effort — renderer EDM hook (`static/index.js`) |
| 7.0.x – 7.5.x | ✔ best-effort — renderer EDM hook (`render/index.js`) |
| 7.6.1 – 11.x | ✔ regex patches — `startMainProcess.js` + `RegistrationHelpers.decodeBody` |
| 12.0 – 12.4.0 | ✔ regex patches (fixed variable names in `main.bundle.js`) |
| 12.4.1 – ??? | ✔ flexible regex (capture groups, survives minifier reshuffles) |

> **Best-effort** rows apply patches derived from historical diffs that have not been
> re-tested in this fork. If patching fails, pass `-a` to point at your asar and open an issue.

## Troubleshooting

**"Cannot be loaded because running scripts is disabled"** (Windows)  
Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` in PowerShell, then retry.

**"Regex pattern not found"**  
GitKraken changed a file's structure. Unpack the asar manually and check the target file:
```powershell
node dist\bin\gitcracken.js patcher unpack
# inspect the app\ folder that appears next to app.asar
```
Then update the `find` pattern in `patches\pro.json`.

**Still showing Free after patching**  
Delete `%APPDATA%\.gitkraken` (Windows) or `~/.gitkraken` (Linux/macOS), then re-login.

**macOS quarantine block**  
```bash
sudo xattr -rd com.apple.quarantine /Applications/GitKraken.app
```

## Block auto-update

Add to your hosts file to prevent GitKraken from overwriting the patch:
```
0.0.0.0 release.gitkraken.com
```
