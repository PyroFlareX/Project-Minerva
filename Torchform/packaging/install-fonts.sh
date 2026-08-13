#!/bin/sh
set -eu

# The files come from the first-party Google Fonts repository.  Keep each
# family in its own directory so the script is idempotent and easy to inspect.
FONT_ROOT=${FONT_ROOT:-"$HOME/.local/share/fonts"}
GOOGLE_FONTS_BASE="https://raw.githubusercontent.com/google/fonts/main/ofl"

usage() {
    printf 'Usage: %s [--check]\n' "$0"
}

if [ "$#" -gt 1 ]; then
    usage >&2
    exit 2
fi
CHECK_ONLY=0
if [ "$#" -eq 1 ]; then
    if [ "$1" = "--check" ]; then
        CHECK_ONLY=1
    else
        usage >&2
        exit 2
    fi
fi

if ! command -v fc-list >/dev/null 2>&1; then
    printf 'error: fc-list is required (install fontconfig first)\n' >&2
    exit 1
fi

font_present() {
    family=$1
    directory=$2

    # A freshly downloaded font may not be in fontconfig's cache yet, so
    # inspect both the cache and the user font directory.
    fc_entries=$(fc-list ":family=$family" 2>/dev/null || true)
    if [ -n "$fc_entries" ]; then
        return 0
    fi

    if [ -d "$FONT_ROOT/$directory" ]; then
        for font_file in \
            "$FONT_ROOT/$directory"/*.ttf \
            "$FONT_ROOT/$directory"/*.otf \
            "$FONT_ROOT/$directory"/*.ttc
        do
            if [ -f "$font_file" ]; then
                return 0
            fi
        done
    fi

    return 1
}

report_family() {
    family=$1
    directory=$2
    if font_present "$family" "$directory"; then
        printf '%s: present\n' "$family"
    else
        printf '%s: missing\n' "$family"
        return 1
    fi
}

report_status() {
    missing=0
    if ! report_family 'Barlow Condensed' 'Barlow Condensed'; then missing=1; fi
    if ! report_family 'Inter' 'Inter'; then missing=1; fi
    if ! report_family 'JetBrains Mono' 'JetBrains Mono'; then missing=1; fi
    if ! report_family 'DM Mono' 'DM Mono'; then missing=1; fi
    return "$missing"
}

if [ "$CHECK_ONLY" -eq 1 ]; then
    report_status
    exit $?
fi

if ! command -v curl >/dev/null 2>&1; then
    printf 'error: curl is required to download fonts\n' >&2
    exit 1
fi

install_font() {
    family=$1
    directory=$2
    slug=$3
    source_file=$4
    destination_file=$5

    if font_present "$family" "$directory"; then
        printf '%s: already present\n' "$family"
        return 0
    fi

    target_dir="$FONT_ROOT/$directory"
    mkdir -p "$target_dir"
    printf 'Downloading %s...\n' "$family"
    temporary_file="$target_dir/.${destination_file}.$$"
    if curl -fL --retry 3 \
        "$GOOGLE_FONTS_BASE/$slug/$source_file" \
        -o "$temporary_file"
    then
        mv "$temporary_file" "$target_dir/$destination_file"
    else
        rm -f "$temporary_file"
        return 1
    fi
}

install_font \
    'Barlow Condensed' 'Barlow Condensed' barlowcondensed \
    'BarlowCondensed-Regular.ttf' 'BarlowCondensed-Regular.ttf'
install_font \
    'Inter' 'Inter' inter \
    'Inter%5Bopsz%2Cwght%5D.ttf' 'Inter-Variable.ttf'
install_font \
    'JetBrains Mono' 'JetBrains Mono' jetbrainsmono \
    'JetBrainsMono%5Bwght%5D.ttf' 'JetBrainsMono-Variable.ttf'
install_font \
    'DM Mono' 'DM Mono' dmmono \
    'DMMono-Regular.ttf' 'DMMono-Regular.ttf'

if ! command -v fc-cache >/dev/null 2>&1; then
    printf 'error: fc-cache is required to refresh the font cache\n' >&2
    exit 1
fi
fc-cache -f "$FONT_ROOT"
report_status
