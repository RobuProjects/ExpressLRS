#!/usr/bin/env bash
# Build the SimpliFly ExpressLRS firmware (TX module + receiver) and package
# release images. This is the script the shipped binaries are built with.
#
#   simplifly/build_simplifly_release.sh          # SimpliFly 2G4
#
# Output: release/ next to this fork's src/ (override with RELEASE_DIR=...).
# See simplifly/README.md.
set -euo pipefail

FORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ELRS_DIR="$FORK_DIR/src"
RELEASE_DIR="${RELEASE_DIR:-$FORK_DIR/release}"

# SimpliFly board layouts (hardware targets), and the branch they live on.
TARGETS_URL="https://github.com/RobuProjects/Targets.git"
TARGETS_BRANCH="simplifly-target"

# Prefer local user install of PlatformIO if available.
if [[ -x "$HOME/.local/bin/pio" ]]; then
    PIO_BIN="$HOME/.local/bin/pio"
elif command -v pio >/dev/null 2>&1; then
    PIO_BIN="$(command -v pio)"
else
    echo "Error: PlatformIO (pio) not found. Install it first." >&2
    exit 1
fi

# The ELRS build reads board layouts from src/hardware, and clones upstream
# targets there if it is missing - which has no SimpliFly boards. Use the
# SimpliFly targets instead: a link set up by the Simplifly_2G4_ELRS
# superproject (its targets/ submodule), or else a clone of the branch.
HW_DIR="$ELRS_DIR/hardware"
if [[ -L "$HW_DIR" ]]; then
    :
elif [[ -d "$HW_DIR/.git" ]]; then
    branch="$(git -C "$HW_DIR" rev-parse --abbrev-ref HEAD)"
    if [[ "$branch" != "$TARGETS_BRANCH" ]]; then
        echo "Error: $HW_DIR is on branch '$branch', expected '$TARGETS_BRANCH'." >&2
        echo "Move it away so the SimpliFly targets can be cloned:" >&2
        echo "    mv \"$HW_DIR\" /tmp/elrs-hardware-old" >&2
        exit 1
    fi
elif [[ -e "$HW_DIR" ]]; then
    echo "Error: $HW_DIR exists but is not the SimpliFly targets." >&2
    exit 1
else
    git clone --branch "$TARGETS_BRANCH" "$TARGETS_URL" "$HW_DIR"
fi

# Resolve esptool from PlatformIO package cache.
ESPTOOL_PY="$HOME/.platformio/packages/tool-esptoolpy/esptool.py"
if [[ ! -f "$ESPTOOL_PY" ]]; then
    echo "Error: esptool.py not found at $ESPTOOL_PY" >&2
    exit 1
fi

# ── Product families ─────────────────────────────────────────────
# Each family is packaged into release/<out-subdir> and contains its envs.
SIMPLIFLY_2G4_ENVS=(
    "SimpliFly_2G4_RX_via_UART"
    "SimpliFly_2G4_RX_via_WIFI"
    "SimpliFly_2G4_TX_via_UART"
    "SimpliFly_2G4_TX_via_WIFI"
)

# Select which families to build from the command line (default: all).
FAMILIES=("$@")
if [[ ${#FAMILIES[@]} -eq 0 ]]; then
    FAMILIES=("2g4")
fi

# Build + package one family.
#   $1   = output subdir under release/
#   $2   = human-readable title for README
#   $3.. = environment names
build_and_package() {
    local out_subdir="$1"
    local title="$2"
    shift 2
    local envs=("$@")
    local out_dir="$RELEASE_DIR/$out_subdir"

    echo "==================================================================="
    echo "Building family: $title  ->  release/$out_subdir"
    echo "==================================================================="

    pushd "$ELRS_DIR" >/dev/null

    mkdir -p "$out_dir"
    rm -rf "${out_dir:?}"/*

    # Build, merge and collect one environment at a time: PlatformIO wipes
    # the other environments' build folders whenever its project checksum
    # changes (e.g. while libraries install on a fresh clone), so outputs
    # must be taken right after each build.
    for env_name in "${envs[@]}"; do
        echo "- $env_name"
        "$PIO_BIN" run -e "$env_name"

        local src_dir="$ELRS_DIR/.pio/build/$env_name"
        python3 "$ESPTOOL_PY" --chip esp32s3 merge_bin \
            -o "$src_dir/${env_name}_full_flash.bin" \
            --flash_mode qio --flash_freq 80m --flash_size 8MB \
            0x0000 "$src_dir/bootloader.bin" \
            0x8000 "$src_dir/partitions.bin" \
            0xe000 "$src_dir/boot_app0.bin" \
            0x10000 "$src_dir/firmware.bin"

        local dst_dir="$out_dir/$env_name"
        mkdir -p "$dst_dir"

        cp "$src_dir/firmware.bin" "$dst_dir/"
        cp "$src_dir/bootloader.bin" "$dst_dir/"
        cp "$src_dir/partitions.bin" "$dst_dir/"
        cp "$src_dir/boot_app0.bin" "$dst_dir/"
        cp "$src_dir/${env_name}_full_flash.bin" "$dst_dir/"

        {
            echo "env=$env_name"
            echo "flash_mode=qio"
            echo "flash_freq=80m"
            echo "flash_size=8MB"
            echo "bootloader=0x0000"
            echo "partitions=0x8000"
            echo "boot_app0=0xe000"
            echo "firmware=0x10000"
        } > "$dst_dir/flash_layout.txt"
    done

    {
        echo "$title Release Artifacts"
        echo "===================================="
        echo ""
        echo "Environments packaged:"
        for env_name in "${envs[@]}"; do
            echo "- $env_name"
        done
        echo ""
        echo "Each folder contains:"
        echo "- firmware.bin"
        echo "- bootloader.bin"
        echo "- partitions.bin"
        echo "- boot_app0.bin"
        echo "- <env>_full_flash.bin"
        echo "- flash_layout.txt"
        echo ""
        echo "Quick full-image flash (replace ttyUSB0 + file):"
        echo "python3 ~/.platformio/packages/tool-esptoolpy/esptool.py \\"
        echo "  --chip esp32s3 --port /dev/ttyUSB0 --baud 460800 \\"
        echo "  --before default_reset --after hard_reset \\"
        echo "  write_flash 0x0 <env>_full_flash.bin"
    } > "$out_dir/README.txt"

    popd >/dev/null

    # Zip the family folder (top-level entry = <out-subdir>/) so the archive
    # always matches the folder next to it.
    local zip_path="$RELEASE_DIR/${out_subdir}_release.zip"
    rm -f "$zip_path"
    (cd "$RELEASE_DIR" && python3 -m zipfile -c "$zip_path" "$out_subdir")

    echo "Done. Release artifacts are in: $out_dir (and $zip_path)"
}

for family in "${FAMILIES[@]}"; do
    case "$family" in
        2g4)  build_and_package "simplifly_2g4"  "SimpliFly ELRS 2G4"  "${SIMPLIFLY_2G4_ENVS[@]}" ;;
        *) echo "Error: unknown family '$family' (expected '2g4')" >&2; exit 1 ;;
    esac
done

echo "All requested families built."
