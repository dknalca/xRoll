#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
project="$project_root/xRoll.xcodeproj"
scheme="xRoll"
export_options="$project_root/iOS/ExportOptions.plist"
ipa_output="$project_root/dist/ios-device/xRoll.ipa"
team_id=$(/usr/libexec/PlistBuddy -c 'Print :teamID' "$export_options")
script_name=${0:t}

usage() {
    print "Uso: $script_name [--udid UDID]"
    print "Compila, firma, exporta e instala xRoll en un iPad conectado por USB."
}

device_udid=""
while (( $# > 0 )); do
    case "$1" in
        --udid)
            (( $# >= 2 )) || { print -u2 "Falta el UDID después de --udid."; exit 2; }
            device_udid="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print -u2 "Opción desconocida: $1"
            usage >&2
            exit 2
            ;;
    esac
done

for tool in xcodebuild idevice_id ideviceinfo ideviceinstaller; do
    command -v "$tool" >/dev/null || {
        print -u2 "Falta '$tool'. Consulta docs/IOS_BUILD.md para instalar las herramientas necesarias."
        exit 1
    }
done

if [[ -z "$device_udid" ]]; then
    device_output="$(idevice_id -l)"
    if [[ -z "$device_output" ]]; then
        print -u2 "No se detectó ningún dispositivo. Conecta y desbloquea el iPad, y acepta «Confiar en este ordenador»."
        exit 1
    fi
    device_ids=("${(@f)device_output}")
    if (( ${#device_ids[@]} != 1 )); then
        print -u2 "Hay varios dispositivos conectados. Indica el iPad con --udid:"
        print -u2 "$device_output"
        exit 2
    fi
    device_udid="${device_ids[1]}"
fi

device_name="$(ideviceinfo -u "$device_udid" -k DeviceName 2>/dev/null)" || {
    print -u2 "No se pudo acceder al dispositivo $device_udid. Desbloquéalo y acepta la confianza USB."
    exit 1
}
device_product_type="$(ideviceinfo -u "$device_udid" -k ProductType 2>/dev/null || true)"
if [[ "$device_product_type" != iPad* ]]; then
    print -u2 "El dispositivo seleccionado no es un iPad ($device_product_type)."
    exit 1
fi
device_version="$(ideviceinfo -u "$device_udid" -k ProductVersion 2>/dev/null || print "versión desconocida")"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/xroll-ipad.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
trap 'exit 130' INT TERM
archive_path="$temporary_directory/xRoll.xcarchive"
export_path="$temporary_directory/export"

print "Dispositivo: $device_name · iPadOS $device_version · $device_udid"
print "Compilando y firmando xRoll para iOS..."
xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_STYLE=Automatic \
    archive

print "Exportando IPA de desarrollo..."
xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options"

ipas=("$export_path"/*.ipa(N))
if (( ${#ipas[@]} != 1 )); then
    print -u2 "La exportación no produjo exactamente un IPA en $export_path."
    exit 1
fi

mkdir -p "${ipa_output:h}"
cp "${ipas[1]}" "$ipa_output"
print "Instalando en $device_name..."
ideviceinstaller -u "$device_udid" -w install "$ipa_output"

print "Listo. IPA guardado en: $ipa_output"
print "Abre xRoll desde la pantalla de inicio del iPad para probarlo."
