# GmsCompat port: commit order

GrapheneOS and LineageOS 24.0 both sit on AOSP `android-17.0.0_r1`, so GrapheneOS's commits are cherry-picked from its `17` branches onto LineageOS's `lineage-24.0` repos.

The lists were built on 2026-11-07:
- For `frameworks/base`, by paging the GitHub commits API down to the AOSP base commit `94b4c163b7dfe5ce3607f7bb8456f9573f7de57d` (538 GrapheneOS commits on top).
- For the other repos, from blob-less clones with the AOSP tag fetched alongside ([`build/graphene-survey.sh`](../build/graphene-survey.sh)).

Rules:
- `fixup!` commits are squashed into their target.
- A `Revert` is applied together with what it reverts, so the pair can be dropped as a unit.
- Original authorship is kept.

## frameworks/base

**Prerequisites.** The core commit imports `android.ext.PackageId` (19 times) and `AppInfoExt`/`AppInfoExtFlag`, and adds code under `services/.../pm/ext`:

| Commit | Date | Subject |
|---|---|---|
| `2e27682d05` | 2023-12-18 | PackageHooks: infrastructure for per-package hooks in system_server |
| `38e9327d88` | 2023-12-20 | infrastructure for custom handling of known packages (adds `android/ext/{AppInfoExt,AppInfoExtFlag,PackageId…}`, `pm/ext/PackageExt`) |
| `1ebdc7328b` | 2025-05-27 | PackageExt: Method to check for presence of an AppInfoExt flag |

These carry their own dependencies (for example `KnownSystemPackages` and `SettingsIntents` in `android.ext`). They are resolved while picking: conflicts and missing symbols name the next commit to bring in.

**Core:** `ce631ecf96` (2023-06-06), "gmscompat: add compatibility layer for unprivileged GMS". It touches 126 files (+7780 −44):
- `core/java/com/android/internal/gmscompat/**`
- `android.app`, `android.os`, `android.content(.pm)`
- `server/pm` and `server/pm/ext`
- media and telephony hooks

**Follow-ups, in order:**

```
6f19617ab3 [temporary] gmscompat: add TODO for USE_ICC_AUTH for RCS in Android 17
35c592d840 add a method to check for Play Store APK source stamp
8c65822a38 bypass pairip for apps that are verified by the Play Store source stamp
06bdd44206 gmscompat: prevent GmsCore from being frozen by the cached app freezer
46b3494c82 gmscompat: switch privSettingsPutStrings() to StringParceledListSlice
d6fd0d0e16 gmscompat: retain RPC provider connection for OOM adjustment
ff5058b735 gmscompat: mark all FIDO activities as opaque            } reverted by 785c2d1ccb, so skip both
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

## Other repos

| Repo | Commits |
|---|---|
| libcore | `12d32f399ab` Dynamite modules (+ fixup `ffe148abedb`), `cf133d4436e` Arrays.asList() hook, `be4788555dc` IoBridge.open() hook |
| art | `55a4cbfd1c` DEX from fd (+ fixup `6a459adafb`), `131dd0fe4e` GmsCompatLibrary platform API access |
| bionic | `5d122e2c2` linker: open zip files by fd path (+ fixup `e93ce4851`) |
| build | `7d30fd72b1` add GmsCompat app, `726e8b2575` dev-build `gmscompat_lib` key, `f040dcf2f6` key mapping, `d5bcfdf6d9` add GmsCompat to generic |
| frameworks/opt/telephony | `30d24e9f85` SMS OTP broadcasts to GmsCore (+ fixup `bc47021886`), `1e795b1726` export generatePackageBasedToken() |
| packages/modules/Permission | `b67105ff7` restart GMS on permission grant, `5e19d6afd` don't restart Android Auto |
| frameworks/native | `fdb532ff78` remove error string from doDump() |
| packages/apps/Settings | `3ec0ec5d1f5` sandboxed Google Play settings link, `c455bb78afc` Private Space link, `995d9becd31` per-app Play Integrity API settings |
| system/sepolicy | `10d292a13` disable unused `gmscore_app` domain |
| packages/apps/GmsCompat | the app itself, branch `17` (new project in the local manifest) |

## Signing

GmsCompat's client library is signed with a dedicated `gmscompat_lib` key (`build` commits above). We generate our own: a dev-build key for development, and a release key kept outside the repo.

The sandboxed Play packages are Google's own signed APKs, installed as ordinary apps. GrapheneOS distributes them through its app repository. Whether its App Store client works on a non-GrapheneOS build is untested.

## Interaction with phase 4 (Play Integrity)

GrapheneOS's Settings carries "per-app Play Integrity API settings" (`995d9becd31`). The framework-level integrity spoofing in phase 4 has to coexist with the GmsCompat hooks into GmsCore: both act in the GMS process.
