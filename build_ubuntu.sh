#!/usr/bin/env bash
# build_ubuntu.sh — Build serialplot .deb package on Ubuntu (native or WSL)
# Run from the repo root:  ./build_ubuntu.sh
# Optional: pass --package to also run cpack and produce a .deb

set -e

PACKAGE=false
BUILD_DIR=""

for arg in "$@"; do
    case $arg in
        --package) PACKAGE=true ;;
        --build-dir=*) BUILD_DIR="${arg#*=}" ;;
    esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default build dir: use WSL native fs if running under WSL (faster than /mnt/...)
if [ -z "$BUILD_DIR" ]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then
        BUILD_DIR="$HOME/serialplot-build-ubuntu"
    else
        BUILD_DIR="$REPO_DIR/build-ubuntu"
    fi
fi

echo "=== Installing build dependencies ==="
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    cmake \
    ninja-build \
    make \
    qt6-base-dev \
    qt6-serialport-dev \
    qt6-svg-dev \
    libqt6opengl6-dev \
    qmake6 \
    dpkg-dev \
    libgl-dev

echo ""
echo "=== Configuring (build dir: $BUILD_DIR) ==="
cmake -S "$REPO_DIR" \
      -B "$BUILD_DIR" \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_QWT=true

echo ""
echo "=== Building Qwt (ExternalProject) ==="
cmake --build "$BUILD_DIR" --target QWT

echo ""
echo "=== Building serialplot ==="
cmake --build "$BUILD_DIR" --parallel

echo ""
echo "=== Build complete ==="
echo "Executable: $BUILD_DIR/serialplot"

if [ "$PACKAGE" = true ]; then
    echo ""
    echo "=== Building .deb package (CPack) ==="
    cd "$BUILD_DIR"
    cpack -G DEB
    DEB=$(ls serialplot*.deb 2>/dev/null | head -1)
    if [ -n "$DEB" ]; then
        # Copy back to repo root so it's accessible from Windows
        cp "$DEB" "$REPO_DIR/"
        echo ""
        echo "Package: $REPO_DIR/$DEB"
    fi
fi
