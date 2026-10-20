#!/bin/zsh
# Compilación universal para herramientas de sideloading que vuelven a firmar.
set -euo pipefail

project_root=${0:A:h:h}
output_directory="$project_root/dist/ios-device"
derived_data="$project_root/dist/ios-build"
build_number="${XROLL_BUILD_NUMBER:-2}"

if (( $# != 0 )); then
    print -u2 "Uso: XROLL_BUILD_NUMBER=2 zsh scripts/build-ios-ipa.sh"
    exit 2
fi
if [[ "$build_number" != <-> ]]; then
    print -u2 "XROLL_BUILD_NUMBER debe ser un entero no negativo."
    exit 2
fi

mkdir -p "$output_directory"
xcodebuild -quiet \
    -project "$project_root/xRoll.xcodeproj" \
    -scheme xRoll \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    CURRENT_PROJECT_VERSION="$build_number" \
    build

app="$derived_data/Build/Products/Release-iphoneos/xRoll.app"
stage="$(mktemp -d "${TMPDIR:-/tmp}/xroll-sideload.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
trap 'exit 130' INT TERM
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/xRoll.app"
app="$stage/Payload/xRoll.app"
# El IPA no incorpora perfiles ni certificados locales. La firma ad-hoc será
# sustituida por AltStore, SideStore o Sideloadly al instalarlo.
rm -rf "$app/_CodeSignature" "$app/embedded.mobileprovision"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict "$app"
lipo "$app/xRoll" -verify_arch arm64
ditto -c -k --keepParent "$stage/Payload" "$stage/xRoll-unsigned.ipa"

python3 - "$stage/xRoll-unsigned.ipa" <<'PY'
import json
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    if archive.testzip() is not None:
        raise SystemExit("El IPA contiene una entrada dañada.")
    prefix = "Payload/xRoll.app/"
    info = plistlib.loads(archive.read(prefix + "Info.plist"))
    if info["CFBundleIdentifier"] != "com.alkbit.xroll" or sorted(info["UIDeviceFamily"]) != [1, 2]:
        raise SystemExit("El bundle no es la app universal de iPhone/iPad esperada.")
    names = set(archive.namelist())
    kit_prefix = prefix + "Kits/hiphop_basic/"
    kit = json.loads(archive.read(kit_prefix + "kit.json"))
    if not all(kit_prefix + sound["file"] in names for sound in kit["sounds"]):
        raise SystemExit("Faltan samples declarados por el kit.")
    exercises = sum(name.startswith(prefix + "exercises/") and name.endswith(".mid") for name in names)
    loops = sum(name.startswith(prefix + "Loops/") and name.endswith(".wav") for name in names)
    if exercises == 0 or loops == 0 or prefix + "embedded.mobileprovision" in names:
        raise SystemExit("Recursos o aprovisionamiento inesperados en el IPA.")
    print(f"Verificado: iPhone/iPad, versión {info['CFBundleShortVersionString']} "
          f"({info['CFBundleVersion']}), {len(kit['sounds'])} sonidos, {exercises} MIDI, {loops} loops.")
PY

# Solo reemplaza el artefacto anterior tras validar íntegramente la copia nueva.
mv "$stage/xRoll-unsigned.ipa" "$output_directory/xRoll-unsigned.ipa"
print "IPA para sideloading: $output_directory/xRoll-unsigned.ipa"
shasum -a 256 "$output_directory/xRoll-unsigned.ipa"
