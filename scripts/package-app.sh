#!/bin/zsh
set -euo pipefail

configuration="${1:-release}"
repository_root="${0:A:h:h}"
bundle="$repository_root/.build/Fine.app"
binary="$repository_root/.build/$configuration/Fine"
resource_bundle="$repository_root/.build/$configuration/Fine_Fine.bundle"

cd "$repository_root"
swift build -c "$configuration"

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary" "$bundle/Contents/MacOS/Fine"
cp "$repository_root/App/Info.plist" "$bundle/Contents/Info.plist"
cp "$repository_root/Assets/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
cp -R "$resource_bundle" "$bundle/Contents/Resources/Fine_Fine.bundle"
codesign --force -s - "$bundle"

echo "$bundle"
