# AppSetup: first-run installer and updater

AppSetup installs and updates the apps that ship outside the system image. Keeping them out of the image keeps the OTA under GitHub's 2 GiB release-file limit (Titanium Browser alone is 335 MB), and lets each app update on its own schedule.

Source: `apps/AppSetup` in the device tree (device patch 0020). It's a privileged system app (`/system_ext/priv-app`) with `INSTALL_PACKAGES`, signed with our release key.

## Apps and sources

| App | Package | Source | Pinned signing certificate (SHA-256) |
|---|---|---|---|
| Google Play services | `com.google.android.gms` | GrapheneOS app repository | `7ce83c1b71f3d572fed04c8d40c5cb10ff75e6d87d9df6fbd53f0468c2905053` or its rotation `5f2391277b1dbd489000467e4c2fa6af802430080457dce2f618992e9dfb5402` |
| Google Play Store | `com.android.vending` | GrapheneOS app repository | `7ce83c1b71f3d572fed04c8d40c5cb10ff75e6d87d9df6fbd53f0468c2905053` |
| Aurora Store | `com.aurora.store` | Aurora's release feed (the one Aurora self-updates from) | `4c626157ad02bda3401a7263555f68a79663fc3e13a4d4369a12570941aa280f` |
| F-Droid | `org.fdroid.fdroid` | f-droid.org repository | `43238d512c1e5eb2d6569f4a3afbf5523418b82e0a3ed1552770abb9a9c9ccab` |
| Termux | `com.termux` | f-droid.org repository | `228fb2cfe90831c1499ec3ccaf61e96e8e1ce70766b9474672ce427334d41c42` |
| Termux:API | `com.termux.api` | f-droid.org repository | same key as Termux (they share the `com.termux` UID) |
| Titanium Browser | `io.github.jqssun.helium` | GitHub releases, arm64 asset | `095540494d53f48ca051bc86c392c46edb29725da5592bd8af3c3d027b3166bb` |

How the pins were checked (2026-11-16):
- **Aurora:** matches the fingerprint in Aurora's README.
- **F-Droid:** F-Droid's long-published client fingerprint.
- **Titanium:** publishes none. The November 2026 and June 2026 releases carry the same key.
- **Termux:** F-Droid signs both Termux apps with one key, as their shared UID requires. Termux's GitHub builds are deliberately not used: they're signed with `testkey_untrusted.jks`, whose private key and password are in termux-app. A pin on it would protect nothing, and any app signed with it could join Termux's shared UID.
- **Google:** the certificates GrapheneOS's signed index lists for these packages.

GmsCore and the Play Store are Google's unmodified APKs; GrapheneOS's index is just a signed list of them. On Android 15 and later GrapheneOS doesn't install GSF, so neither does AppSetup.

## Trust rules

- **Signing certificate.** A downloaded APK is installed only if every current signer's certificate is pinned for that package. This holds whichever server or mirror served it.
- **GrapheneOS index.** Its signature trailer must verify against GrapheneOS's pinned Ed25519 repository key (the key GrapheneOS's own App Store client pins). It's refused if older than an index already seen, so a replayed old index can't steer installs to old versions.
- **Hashes and sizes.** A part's SHA-256 is checked when the source publishes one (GrapheneOS index, GitHub). Its size must match when known. Every download is size-capped.
- **Network.** HTTPS only, on every redirect hop. Requests send a generic `User-Agent`.
- **Versions.** No downgrades: an archive no newer than what's installed is discarded.
- **Order.** GmsCore is installed before the Play Store, Termux before Termux:API.

## Behaviour

- Opening AppSetup shows a checklist of the apps. **Install selected** installs or updates the checked ones without prompts.
- A daily `JobScheduler` job, on unmetered networks with battery not low, updates the managed apps that are installed. It never reinstalls an app the user removed.
- Aurora and F-Droid also update themselves, and the Play Store updates GmsCore and itself. AppSetup is the only updater for Titanium Browser.
- Sandboxed Google Play variants follow GmsCompat's version requirement (`staticDeps`), so a newer GmsCore that needs a newer GmsCompat waits for the ROM update that brings it.

## Changing a pin

A project rotating its key makes AppSetup refuse its updates. That's the intended failure. Check the new certificate against the project's own announcement, update `Catalog.java` and this table, and ship it in a ROM update.
