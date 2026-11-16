# GmsCompat port

GrapheneOS and LineageOS 24.0 both sit on AOSP `android-17.0.0_r1`, so GrapheneOS's commits are cherry-picked from its `17` branches onto LineageOS's `lineage-24.0` repos. The result is sandboxed Google Play: GmsCore, GSF and the Play Store installed as ordinary apps, running through GrapheneOS's compatibility layer.

Ported on 2026-11-15. The GrapheneOS head of each repo at that time is in [`ported.json`](../ported.json).

## How the commit list was found

The first survey (2026-11-07) listed GmsCompat commits in 10 repos, with three prerequisites in `frameworks/base`. That was too few. The final list came from three checks:

1. **Commit messages and diffs.** Every GrapheneOS repo was searched for commits that mention GmsCompat in the message, or that add or remove a line mentioning it. This found 10 more repos (AppSearch, Bluetooth, ConfigInfrastructure, Connectivity, Nfc, StatsD, Wifi, DownloadProvider, TelephonyProvider and `system/tools/aidl`).
2. **Line dependencies.** For each wanted commit, every line it changes (with 3 lines of context) was traced with `git blame` in its parent. A line written by an earlier GrapheneOS commit makes that commit a dependency. This was repeated until no new commits appeared.
3. **Class references.** Each class that GrapheneOS adds and our tree lacks was searched for by name in the ported files. This found classes that new files use but never edit (`AppSwitch`, `BinderWrapper`).
4. **Permission and constant references.** Each `Manifest.permission.X` in ported code was checked against the framework manifest, and each constant used on GrapheneOS classes (`PackageId`, `GosPackageStateFlag`, ...) was checked against the class.

Rules:
- `fixup!` commits are squashed into their target. The target's message records the fixup's source hash.
- A commit that a later commit reverts and then re-adds is taken only in its final form.
- Original authorship is kept (`cherry-pick -x`). A commit we changed beyond conflict resolution gets a note and a `Co-authored-by` line.

## frameworks/base

The core commit (`ce631ecf96`, rebased by GrapheneOS onto 17) sits on top of GrapheneOS's own framework infrastructure, so that infrastructure comes too. These commits only add infrastructure: classes, hooks and per-app state. The user-facing features built on it (for example, INTERNET as a runtime permission, Storage Scopes or Contact Scopes) are separate commits and are **not** ported. Their switches stay off.

Infrastructure, in branch order:

```
9fd2f0313a define resource ID ranges for GrapheneOS framework resources
445380e2c8 add constants for some system package names
4e2e1b45a7 extsettings: add a set of helper classes for defining system settings
1e64c97aba add system package check methods to PackageUtils
927469654d define package name of first-party app source
164035d8d4 add helpers for system_server extensions
34c2ff0be8 add hooks for modifying PackageManagerService behavior
9fc43452ce AppBindArgs: infrastructure for passing extra args to app process init
8ce7f37101 add helper class for launching non-standard Settings intents
38e9327d88 infrastructure for custom handling of known packages
e87c93a265 SettingsProvider: add support for further restriction of setting access
92237d7768 gosps: support for per-app GrapheneOS-specific persistent state
2e27682d05 PackageHooks: infrastructure for per-package hooks in system_server
14dde7bb88 infrastructure for spoofing self permission checks
c35f173a11 infrastructure for special runtime permissions
c3783c2c35 infrastructure for the Storage Scopes feature
72ac3c694d integrate Google's EuiccSupportPixel package
8f7cfe0154 integrate Google's eUICC LPA package (EuiccGoogle)
948523d852 add config for Pixel Camera Services
52a143cb64 support redirecting ContentProvider calls to another provider
df9421c779 infrastructure for the Contact Scopes feature
16b06e231c make Google's text-to-speech app force-queryable
87a50879a2 add config for Pixel Health app
1ebdc7328b PackageExt: Method to check for presence of an AppInfoExt flag
e1ef271515 re-enable the system keyboard at boot if it's disabled
9e0261c42d SourceStampVerifier: add an option to require a specific source stamp
35c592d840 add a method to check for Play Store APK source stamp
8c65822a38 bypass pairip for apps that are verified by the Play Store source stamp
4e8c036fae add base class for complex per-app switches
d33693e15e add BinderWrapper
8ac1559169 define READ_DEVICE_SERIAL_NUMBER permission for Build.getSerial() access
32d6f90a8e aauto: define a restricted version of the MANAGE_USB permission
e3475a6f9a aauto: add definition of restricted BLUETOOTH_PRIVILEGED permission
a5d3c64a85 aauto: add definition of restricted WIFI_PRIVILEGED permission
179e246d84 aauto: add definition of restricted READ_PRIVILEGED_PHONE_STATE permission
9098eca590 aauto: define ASSOCIATE_COMPANION_DEVICES_RESTRICTED permission
```

The last six define the restricted permissions that `AndroidAutoHooks` (added by the core commit) grants to Android Auto. They were found by checking that every permission named in ported code is declared in the framework manifest.

Found by the first compile (methods and fields on existing classes, which the checks above don't cover):

```
2bbf28680d add is_dev_build aconfig flag
e8593514a6 add Bundle.toStringDeep()
46f6fc49d3 add APIs for launching LogViewer app
c64747ea31 add option to view application error details in LogViewer app
fb5382f6a6 define READ_LOGS_FULL permission for promptless logcat access
```

and from the second compile, plus a scan of every method that ported code calls against the methods declared in the tree:

```
94220f895f add getter for PackageManagerService.mContext
803788883f add BaseBundle.get{Boolean2,Number}() methods
e1861ba17a include path of ANR stack traces file in ApplicationErrorReport
138e179453 add APIs for requesting coarsened locations
ae04aec5f5 add method for updating and invalidating package state
```

and from the first run on the phone:

```
89c9528313 add support for hooking LocationManager methods
3708efda45 improve compat with apps that try to access network location provider
```

The GmsCompatConfig APK names framework classes and methods to stub. On a non-`user` build (`Build.IS_USER` false, as on our `userdebug`), GmsCompat counts as a dev build and parses the config strictly: one class it can't load rejects the whole config, and GmsCompat can't start. Version 179 names `android.location.HookedLocationManager`, which these two commits add. With them, every class and method that config names resolves in our tree (38 classes, 111 methods; checked by [`build/gmscompat-config-check.py`](../build/gmscompat-config-check.py)). **Recheck this whenever GmsCompatConfig updates**, since a newer config can name more GrapheneOS-only classes.

Fixups of ported commits, squashed into their targets: `2aa96626f5`, `6474689e34`, `c6e63c32c8` (into `38e9327d88`) and `049c528c72` (into `d33693e15e`).

Two local commits:
- `PackageManagerNative` implements `onDeniedSpecialRuntimePermissionOp` as a no-op (with the system-caller check). `c35f173a11` declares it in `IPackageManagerNative`; GrapheneOS's only implementation shows the OTHER_SENSORS denial notification (`814d776c8b`), which isn't ported.
- `StorageScopesAppHooks` no longer redirects requests. `c3783c2c35` rewrites an app's own all-files-access and manage-media requests to `*_PROMPT` actions that only GrapheneOS's PermissionController handles (`a3099f2968`, `c46e45e26c`, the Storage Scopes UI, not ported). So every app asking for all-files access crashed with `ActivityNotFoundException`; Aurora Store did on 2026-11-16. The request now opens the standard Settings page. Revert this when Storage Scopes is ported in phase 3.

The infrastructure commits change behaviour only where their GrapheneOS feature UI would. Before porting more of it, check that every intent it sends has a handler in this build.

`is_dev_build` is a fixed read-only flag with no value set in our release config, so it reads false: GmsCompat's debug-build-only paths are compiled out, as on a GrapheneOS production build.

The GmsCompat app shows GMS crashes through GrapheneOS's LogViewer app, so LogViewer comes along: the app itself (`packages/apps/LogViewer`), the framework API above, `READ_LOGS_FULL`, and build/make `2ae74c3005` + `1a40f526c2` (add LogViewer to the product). `c64747ea31` also adds a "Show details" item to every app crash and ANR dialog, which opens LogViewer. `c64747ea31` conflicted only in resources beside its own; only its own entries were kept.

The Pixel, eUICC and text-to-speech commits only add package configuration that the GmsCompat commits are written against. They do nothing when those packages aren't installed.

GmsCompat itself: `ce631ecf96` "gmscompat: add compatibility layer for unprivileged GMS", then:

```
6f19617ab3 [temporary] gmscompat: add TODO for USE_ICC_AUTH for RCS in Android 17
d6fd0d0e16 gmscompat: retain RPC provider connection for OOM adjustment
06bdd44206 gmscompat: prevent GmsCore from being frozen by the cached app freezer
46b3494c82 gmscompat: switch privSettingsPutStrings() to StringParceledListSlice
53ccd09f4c gmscompat: notify about missing POST_NOTIFICATIONS only for GmsCore
5cbb40309e gmscompat: fix PackageInstaller.installPackageArchived() stub
836955e8b7 gmscompat: improve support for dev-build-only test packages
b75a554f7f gmscompat: switch from RpcProvider to service bindings and broadcasts
ddbee5569c gmscompat: include ServiceConnection ID in debug logs
12764b47b6 gmscompat: improve handling of Play Store install confirmation dialogs
1ead428547 gmscompat: add missing unbindService() in SynchronousServiceBinding
55ef4eca21 gmscompat: don't exit on binder failure of UncaughtExceptionPreHandler
26b3616b59 gmscompat: fix handling of foreground service types
49d3b64d89 gmscompat: add missing declaration of gmscompat process
bc2dc56688 gmscompat: add debug-build option to bypass installer checks for GMS packages
1a2d680b60 gmscompat: fix an IThirdPartyPayService GmsCore crash
```

Two conflicts:
- `Resources.java` (`8f7cfe0154`): LineageOS had dropped an unused import. Only the new import was added.
- `AppsFilterImpl.java` (`ce631ecf96`): LineageOS's microG rule (force-queryable when microG-signed) and GrapheneOS's GMS rule are both kept.

Not ported:
- `ff5058b735` and its revert `785c2d1ccb`. They cancel out.
- `865521d492` (2026-11-09). It fixes a crash caused by GrapheneOS's storage dynamic-code-loading check, which isn't ported.

## Other repos

| Repo | Commits |
|---|---|
| libcore | `12d32f399a` Dynamite modules (+ fixup `ffe148abed`), `cf133d4436` Arrays.asList() hook, `be4788555d` IoBridge.open() hook |
| art | `55a4cbfd1c` DEX from fd (+ fixup `6a459adafb`), `131dd0fe4e` GmsCompatLibrary platform API access |
| bionic | `5d122e2c2d` linker: open zip files by fd path (+ fixup `e93ce48518`) |
| build/make | `7d30fd72b1` add GmsCompat app (to `handheld_system.mk`, which cancunf inherits), `726e8b2575` dev-build `gmscompat_lib` key, `f040dcf2f6` key mapping, `d5bcfdf6d9` add GmsCompat to the generic system image, `2ae74c3005` + `1a40f526c2` add LogViewer |
| frameworks/native | `fdb532ff78` remove error string from doDump() |
| frameworks/opt/telephony | `30d24e9f85` SMS OTP broadcasts to GmsCore (+ fixup `bc47021886`), `1e795b1726` export generatePackageBasedToken() |
| packages/apps/Settings | `3ec0ec5d1f` sandboxed Google Play settings link, `02f0923ca2` system apps that can't be disabled (includes GmsCompat), `c455bb78af` Private Space link, `c1449fc28a` + `c521c7dbf5` per-app switch UI base classes, `995d9becd3` per-app Play Integrity API settings (adapted, see below) |
| packages/modules/AppSearch | `4a8ffaab44` allow the GmsCompat app to use SafeParcel code |
| packages/modules/Bluetooth | `0af0e5005e` shims and stubs, `55cb77f099` getBondState() stub, `f9fac80d5e` BluetoothLeBroadcast stubs |
| packages/modules/ConfigInfrastructure | `c379e021d7` DeviceConfig hooks |
| packages/modules/Connectivity | `a6e7928585` ConnectivityManager hook, `cef6a8694d` NearbyManager stubs, `bd2328135d` queryDetailsForUidTag() stub, `5fa24474a8` NsdManager.registerService() stub |
| packages/modules/Nfc | `2413525579` NfcAdapter.enable() shim |
| packages/modules/Permission | `b67105ff77` restart GMS on permission grant, `5e19d6afd4` don't restart Android Auto. Both adapted: the `OTHER_SENSORS` clause is dropped, because that GrapheneOS permission isn't part of this build |
| packages/modules/StatsD | `dfbb692f4c` IStatsManagerService stubs |
| packages/modules/Wifi | `1e7bc9cea0`, `5003512883` Android Auto Wi-Fi defaults |
| packages/providers/DownloadProvider | `972e149f08` allow harmless COLUMN_NOTIFICATION_CLASS (current form; the 2021 version `9e2afb01` was reverted by `4c37afc0`) |
| packages/providers/TelephonyProvider | `a04451af82` let GmsCore read its clients' OTP SMS |
| system/sepolicy | `10d292a135` disable the unused `gmscore_app` domain (GMS runs as `untrusted_app`) |
| system/tools/aidl | `95b6587ab9` public transaction code constants, `6e43dfbfa7` public Stub.Proxy classes |
| tools/metalava | `1b01bb1a5a` lower the maximum severity of the UNFLAGGED_API lint to INFO. GrapheneOS's system and module APIs (GmsCompat, `android.ext`, GosPackageState, ...) are not `@FlaggedApi`, so API lint fails without it. |
| build/soong (local) | metalava gets a 4 GiB heap (`-J-Xmx4g`). With the JVM default (a quarter of the 7.5 GiB container cap), the API stubs ran out of heap once these APIs were added. |

**Settings is the one repo where the line-dependency closure was not taken.** It names 39 GrapheneOS settings screens (hardened_malloc, duress PIN, USB-C port control, ...), all because those commits share `strings_ext.xml`, the manifest and the same preference lists. They aren't real dependencies, and their framework halves aren't ported. Conflicts were resolved by keeping only each commit's own additions. `995d9becd3` was adapted:
- the preference sits in App info's Advanced category, since there is no "Exploit protection" category;
- its app list page is registered on its own;
- the intro text doesn't refer to GrapheneOS.

## New projects in the local manifest

| Path | GrapheneOS repo | What |
|---|---|---|
| `packages/apps/GmsCompat` | `platform_packages_apps_GmsCompat` | the GmsCompat app and its client library `GmsCompatLib` |
| `packages/apps/AppCompatConfig` | `platform_packages_apps_AppCompatConfig` | the proto that `38e9327d88`'s `AppCompatConf` reads |
| `packages/apps/LogViewer` | `platform_packages_apps_LogViewer` | log and crash-report viewer; GmsCompat's crash notifications open it |
| `external/GmsCompatConfig` | `platform_external_GmsCompatConfig` | prebuilt config APK (`app.grapheneos.gmscompat.config`), signed by GrapheneOS |
| `external/AppCompatConfig` | `platform_external_AppCompatConfig` | prebuilt app-compat config APK, signed by GrapheneOS |

GmsCompat carries one local patch (`patches/packages_apps_GmsCompat/`): its crash notification's "report" action points to this project's issue tracker instead of GrapheneOS's.

The two config APKs contain data only. They keep GrapheneOS's signature (`preprocessed: true`), so the updates GrapheneOS publishes for them would install over ours.

## Signing

`GmsCompatLib` is signed with a dedicated `gmscompat_lib` key. Build commit `726e8b2575` adds a dev-build key, and `f040dcf2f6` maps it in `sign_target_files_apks.py`, so `build/sign.sh` replaces it with `/lin/keys/gmscompat_lib` (generated by `build/keys.sh`).

The sandboxed Play packages are Google's own signed APKs, installed as ordinary apps.

## Interaction with phase 4 (Play Integrity)

The per-app Play Integrity setting (`995d9becd3`) and GmsCompat's usage notifications use GosPackageState flags in the framework. The phase 4 integrity spoofing has to coexist with the GmsCompat hooks in GmsCore: both act in the GMS process.
