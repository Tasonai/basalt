#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

set -euo pipefail
cd "$(dirname "$0")/.."
install_test_dir=$(mktemp -d)
trap 'command rm -rf "$install_test_dir"' EXIT

# Run the real installation block against disposable bundles. No process is
# stopped and no app under /Applications is read, removed or installed.
sed -n '/^if (( INSTALL )); then$/,$p' build.sh \
    | sed 's|/Applications|$install_test_dir/Applications|g' > "$install_test_dir/install.zsh"
[[ -s "$install_test_dir/install.zsh" ]]
mkdir -p "$install_test_dir/Applications" "$install_test_dir/stage"
print new > "$install_test_dir/stage/content"
INSTALL=1
STAGE="$install_test_dir/stage"
stopped=()
signed=()
stop_process() { stopped+=("$1"); }
sign_installed_bundle() { signed+=("$1"); }

for DEV in 1 0; do
    stopped=()
    signed=()
    for name in Vorss 'Vorssaint Utils' Vorssaint Basalt 'Basalt (Developer)'; do
        mkdir -p "$install_test_dir/Applications/$name.app"
        print original > "$install_test_dir/Applications/$name.app/content"
    done
    if (( DEV )); then
        APP_NAME='Basalt (Developer)'
        EXECUTABLE=BasaltDeveloper
    else
        APP_NAME=Basalt
        EXECUTABLE=Basalt
    fi
    source "$install_test_dir/install.zsh"
    [[ "$(cat "$install_test_dir/Applications/$APP_NAME.app/content")" == new ]]
    [[ "${signed[*]}" == "$install_test_dir/Applications/$APP_NAME.app" ]]
    if (( DEV )); then
        [[ "${stopped[*]}" == BasaltDeveloper ]]
        for name in Vorss 'Vorssaint Utils' Vorssaint Basalt; do
            [[ "$(cat "$install_test_dir/Applications/$name.app/content")" == original ]]
        done
    else
        [[ "${stopped[*]}" == 'Basalt Vorss VorssaintUtils Vorssaint' ]]
        [[ ! -e "$install_test_dir/Applications/Vorss.app" ]]
        [[ ! -e "$install_test_dir/Applications/Vorssaint Utils.app" ]]
        [[ ! -e "$install_test_dir/Applications/Vorssaint.app" ]]
        [[ "$(cat "$install_test_dir/Applications/Basalt (Developer).app/content")" == original ]]
    fi
done
print 'DEVELOPER INSTALL ISOLATION TESTS OK'
