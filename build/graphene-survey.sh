#!/bin/bash
# Survey GrapheneOS's own commits (on top of AOSP android-17.0.0_r1) per repo.
# History only (blob:none), for planning the port. Output: /lin/graphene/<repo>.log
set -uo pipefail
TAG=android-17.0.0_r1
mkdir -p /lin/graphene && cd /lin/graphene
# GrapheneOS repo  ->  AOSP project path
while read -r gos aosp; do
    [ -z "$gos" ] && continue
    if [ ! -d "$gos" ]; then
        git clone -q --filter=blob:none --no-checkout -b 17 "https://github.com/GrapheneOS/$gos" "$gos" || { echo "CLONE-FAIL $gos"; continue; }
    fi
    git -C "$gos" fetch -q --filter=blob:none "https://android.googlesource.com/$aosp" "refs/tags/$TAG:refs/tags/$TAG" || { echo "TAG-FAIL $gos"; continue; }
    n=$(git -C "$gos" rev-list --count "$TAG..17")
    git -C "$gos" log --no-merges --format='%h %ad %an | %s' --date=short "$TAG..17" > "$gos.log"
    echo "$gos commits_on_top=$n gmscompat=$(grep -ci gmscompat "$gos.log")"
done <<'LIST'
platform_frameworks_base platform/frameworks/base
platform_libcore platform/libcore
platform_art platform/art
platform_bionic platform/bionic
platform_build platform/build
platform_packages_apps_Settings platform/packages/apps/Settings
platform_frameworks_opt_telephony platform/frameworks/opt/telephony
platform_system_sepolicy platform/system/sepolicy
platform_packages_modules_Permission platform/packages/modules/Permission
platform_frameworks_native platform/frameworks/native
LIST
echo SURVEY-DONE
