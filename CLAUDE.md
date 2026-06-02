# CLAUDE.md — GitCracken

GitKraken patcher (asar-based, main-process injection). Works on GK 7.7+.

---

## How the patcher works

GitKraken ships as an Electron app. Its code lives in `app.asar`. The patcher:

1. **Unpacks** `app.asar` → `app/` directory
2. **Patches** specific files using unified diffs (`.diff`) or regex patches (`.json`)
3. **Repacks** `app/` → `app.asar`

The core files patched are inside `src/main/static/`:

| File | Purpose |
|---|---|
| `startMainProcess.js` | Electron main-process bootstrap — we inject license hook here |
| `clientType.js` | Single-line: `module.exports = 'NORMAL'` — we change to STANDALONE/ENTERPRISE |
| `mode.js` | Single-line: `module.exports = 'production'` — we change for dev/staging |

---

## Patch formats

### `.diff` (old format — exact context lines required)

Used by the original 5cr1pt/KillWolfVlad patches. Fails if GK changes the surrounding code.

```diff
--- src/main/static/startMainProcess.js
+++ src/main/static/startMainProcess.js
@@ -34,6 +49,6 @@
   global.clientType = clientType;
   global.mode = buildMode;
-
+  patchSnapshot();
   require('../main.js');
```

### `.json` (new format — regex based, version-agnostic)

```json
[
  {
    "description": "Human readable name shown in output",
    "file": "src/main/static/startMainProcess.js",
    "skipIfPresent": "string that means patch is already applied",
    "find": "regex pattern (string, compiled with 's' flag)",
    "replace": "replacement (supports $1 capture groups)"
  }
]
```

The patcher tries `.json` first, then `.diff`. Add new patches as `.json`.

---

## Adding support for a new GK version

When a new GK version breaks the `pro` or `standalone` patch:

### 1. Unpack the asar

```bash
node dist/bin/gitcracken.js patcher unpack
# unpacks to the app/ dir alongside the asar
```

Or manually:
```bash
npx @electron/asar extract app.asar app
```

### 2. Inspect the target files

```bash
cat app/src/main/static/startMainProcess.js
cat app/src/main/static/clientType.js
```

### 3. Check what changed

For `startMainProcess.js`, look for:
- Whether `snapshotResult.customRequire` is still used
- Where `require('../main.js')` (or equivalent) is called — inject `patchSnapshot()` just before it
- Whether the `RegistrationHelpers` module is still at `./src/sharedModules/registration/shared/RegistrationHelpers.js`

For `clientType.js`, look for whether it's still a single-line `module.exports = 'NORMAL'`.

### 4. Update the regex pattern in patches/pro.json

The `find` pattern for the injection point in `startMainProcess.js`:
- Old (8.x): the file ends with `require('../main.js');`
- New: might use a different entry point name

Update `find` to match the actual injection point.

### 5. Check licensedFeatures values

From the renderer bundle (`main.bundle.js`), grep for:
```bash
grep -o 'licensedFeatures={[^}]*}' main.bundle.js
```

This shows all valid feature flag values. For enterprise tier, use `['enterprise', 'pro', 'advanced', 'teamsLicense']`.

---

## File structure

```
GitCracken/
├── patches/
│   ├── pro.json          # Main patch: injects Business license features (regex, 9.x+)
│   ├── pro.diff          # Legacy: original pro patch for 7.7–8.2 (context-based)
│   ├── standalone.json   # clientType=STANDALONE + hardcoded license
│   ├── standalone.diff   # Legacy standalone
│   ├── selfhosted.json   # clientType=ENTERPRISE
│   ├── selfhosted.diff   # Legacy selfhosted
│   ├── individual.json   # Individual features via renderer edm intercept
│   ├── individual.diff   # Legacy individual
│   ├── development.json  # mode=development
│   ├── development.diff  # Legacy development
│   ├── staging.json      # mode=staging
│   └── staging.diff      # Legacy staging
├── src/
│   ├── patcher.ts        # Core: unpack/patch/pack asar. Supports both .json and .diff patches.
│   ├── appId.ts          # AppId generation from MAC address
│   ├── platform.ts       # OS detection
│   └── secFile.ts        # Secure file helpers
├── bin/
│   └── gitcracken-patcher.ts   # CLI entry point
└── package.json
```

---

## Pro patch — how the license injection works

`pro.json` patches `startMainProcess.js` to wrap `RegistrationHelpers.decodeBody`.

`decodeBody` is called when GK fetches the user profile from the API server. The wrapper
intercepts the decoded response and replaces `licensedFeatures` with Business-tier values:

```js
function patchSnapshot() {
  var RegistrationHelpers = snapshotResult.customRequire(
    './src/sharedModules/registration/shared/RegistrationHelpers.js'
  );
  var _decodeBody = RegistrationHelpers.decodeBody;
  RegistrationHelpers.decodeBody = function() {
    var body = _decodeBody.apply(this, arguments);
    return Object.assign({}, body, {
      licensedFeatures: ['pro', 'advanced', 'teamsLicense'],
      proAccessState: {}
    });
  };
}
```

**Why this works:** The patched function runs every time GitKraken calls home to validate
the license. The overridden response makes GK think the account has Business features.
This is why re-login is required after patching — it triggers a profile fetch.

**Why this beats renderer patching:** Patching `main.bundle.js` (the webpack renderer bundle)
only affects the UI layer. The main process still validates the license independently.
Patching `startMainProcess.js` hooks the actual license validation before it reaches
the renderer.

---

## Known file paths by GK version

| GK | startMainProcess.js | clientType.js | RegistrationHelpers.js |
|---|---|---|---|
| 7.7–8.2 | `src/main/static/` | `src/main/static/` | `src/sharedModules/registration/shared/` |
| 9.x–11.x | `src/main/static/` | `src/main/static/` | `src/sharedModules/registration/shared/` |
| 12.x | `src/main/static/` | `src/main/static/` | TBD — check with unpack |

---

## licensedFeatures values (GK 12.1.1)

```
enterprise, enterpriseTrial, pro, student, advanced, teamsLicense, trial
```

For full enterprise tier (what the original modded file used): `['enterprise', 'pro', 'advanced', 'teamsLicense']`

The tier selector chain:
- `getIsHostedEnterprise`: requires `enterprise` in features AND `clientType = NORMAL`
- `getIsEnterpriseTier`: `getIsHostedEnterprise || getIsLicensedOnPremiseEnterprise`
- `getIsTeamsTierOrAbove`: `getIsTeamsLicensed || getIsEnterpriseTier`
- `getIsAdvancedTierOrAbove`: `getIsAdvancedLicensed || getIsTeamsTierOrAbove`
- `getIsProTierOrAbove`: `getIsPro || getIsAdvancedTierOrAbove`
