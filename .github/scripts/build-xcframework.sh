#!/usr/bin/env bash

# Build CryptoSwift XCFramework with Library Evolution enabled
# Adapted for GitHub Actions CI - no cloning needed, uses checked-out code

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Cleanup function for temporary directories
cleanup() {
    local exit_code=$?
    if [ -n "${TEMP_DIRS:-}" ]; then
        echo "Cleaning up temporary directories..."
        for temp_dir in $TEMP_DIRS; do
            [ -d "$temp_dir" ] && rm -rf "$temp_dir" || true
        done
    fi
    exit $exit_code
}

# Register cleanup trap
trap cleanup EXIT INT TERM

# Get version from argument (passed from GitHub Actions)
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Error: Version argument is required"
    echo "Usage: $0 <version>"
    exit 1
fi

FRAMEWORK_NAME="${FRAMEWORK_NAME:-CryptoSwift}"
SCHEME_NAME="${SCHEME_NAME:-${FRAMEWORK_NAME}}"
PROJECT_FILE="${PROJECT_FILE:-${FRAMEWORK_NAME}.xcodeproj}"

# Use current directory (already checked out in CI)
REPO_DIR="$(pwd)"
BUILD_DIR="${REPO_DIR}/build"
OUTPUT_DIR="${BUILD_DIR}/${FRAMEWORK_NAME}"
PROJECT_PATH="${REPO_DIR}/${PROJECT_FILE}"

# Track temporary directories for cleanup
TEMP_DIRS=""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 Building ${FRAMEWORK_NAME} XCFramework (Version: ${VERSION})${NC}"
echo "=================================================="
echo "Repository: ${REPO_DIR}"
echo "Output: ${OUTPUT_DIR}"
echo "Framework: ${FRAMEWORK_NAME}"
echo "Scheme: ${SCHEME_NAME}"
echo "=================================================="

# Verify prerequisites
echo -e "${BLUE}🔍 Verifying prerequisites...${NC}"

# Check if Xcode project exists
if [ ! -d "$PROJECT_PATH" ]; then
    echo -e "${RED}❌ Error: Xcode project not found at ${PROJECT_PATH}${NC}"
    exit 1
fi

# Check if required tools are available
command -v xcodebuild >/dev/null 2>&1 || { echo -e "${RED}❌ Error: xcodebuild is not installed${NC}"; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo -e "${RED}❌ Error: xcrun is not installed${NC}"; exit 1; }
command -v swift >/dev/null 2>&1 || { echo -e "${RED}❌ Error: swift is not installed${NC}"; exit 1; }
command -v zip >/dev/null 2>&1 || { echo -e "${RED}❌ Error: zip is not installed${NC}"; exit 1; }

# Verify Xcode version
XCODE_VERSION=$(xcodebuild -version | head -n 1)
echo "Using: $XCODE_VERSION"

# Clean output directory
echo -e "${BLUE}🧹 Cleaning output directory...${NC}"
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Build Settings
BUILD_LIBRARY_FOR_DISTRIBUTION="YES"
OTHER_SWIFT_FLAGS="-Xfrontend -enable-library-evolution"

build_framework() {
    local platform=$1
    local destination=$2
    local scheme_name="${SCHEME_NAME}"
    local derived_data=$(mktemp -d)
    
    # Track for cleanup on error
    TEMP_DIRS="${TEMP_DIRS} ${derived_data}"
    
    echo -e "${GREEN}🔨 Building for ${platform}...${NC}"
    echo "Destination: ${destination}"
    echo "Scheme: ${scheme_name}"
    echo "Derived Data: ${derived_data}"
    
    # Archive
    if ! xcrun xcodebuild archive \
        -project "${PROJECT_PATH}" \
        -scheme "${scheme_name}" \
        -configuration Release \
        -destination "${destination}" \
        -archivePath "${derived_data}/${platform}.xcarchive" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION="${BUILD_LIBRARY_FOR_DISTRIBUTION}" \
        "OTHER_SWIFT_FLAGS=${OTHER_SWIFT_FLAGS}" \
        -quiet; then
        echo -e "${RED}❌ Archive failed for ${platform}${NC}"
        rm -rf "${derived_data}"
        exit 1
    fi
    
    # Export Framework from archive
    local framework_path="${derived_data}/${platform}.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework"
    local framework_path_alt="${derived_data}/${platform}.xcarchive/Products/usr/local/lib/${FRAMEWORK_NAME}.framework"
    
    if [ -d "$framework_path" ]; then
        mkdir -p "${OUTPUT_DIR}/${platform}"
        cp -R "$framework_path" "${OUTPUT_DIR}/${platform}/"
        echo -e "${GREEN}✅ Successfully built ${platform}${NC}"
    elif [ -d "$framework_path_alt" ]; then
        mkdir -p "${OUTPUT_DIR}/${platform}"
        cp -R "$framework_path_alt" "${OUTPUT_DIR}/${platform}/"
        echo -e "${GREEN}✅ Successfully built ${platform}${NC}"
    else
        echo -e "${RED}❌ Build failed for ${platform}${NC}"
        echo "Expected framework at: ${framework_path} or ${framework_path_alt}"
        echo "Archive contents:"
        ls -la "${derived_data}/${platform}.xcarchive/Products/Library/Frameworks/" 2>/dev/null || true
        ls -la "${derived_data}/${platform}.xcarchive/Products/usr/local/lib/" 2>/dev/null || true
        rm -rf "${derived_data}"
        exit 1
    fi
    
    # Cleanup successful build
    rm -rf "${derived_data}"
    TEMP_DIRS=$(echo "$TEMP_DIRS" | sed "s|${derived_data}||" | tr -s ' ')
}

# Build for platforms
# 1. Build iOS Device
build_framework "ios-arm64" "generic/platform=iOS"

# 2. Build Simulator
build_framework "ios-arm64_x86_64-simulator" "generic/platform=iOS Simulator"

# 3. Create XCFramework
echo -e "${BLUE}📦 Creating XCFramework...${NC}"
XCFRAMEWORK_PATH="${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"

FRAMEWORK_ARGS=()
if [ -d "${OUTPUT_DIR}/ios-arm64/${FRAMEWORK_NAME}.framework" ]; then
    FRAMEWORK_ARGS+=("-framework" "${OUTPUT_DIR}/ios-arm64/${FRAMEWORK_NAME}.framework")
fi
if [ -d "${OUTPUT_DIR}/ios-arm64_x86_64-simulator/${FRAMEWORK_NAME}.framework" ]; then
    FRAMEWORK_ARGS+=("-framework" "${OUTPUT_DIR}/ios-arm64_x86_64-simulator/${FRAMEWORK_NAME}.framework")
fi

if [ ${#FRAMEWORK_ARGS[@]} -eq 0 ]; then
    echo -e "${RED}❌ Error: No frameworks were built${NC}"
    exit 1
fi

if ! xcrun xcodebuild -create-xcframework \
    "${FRAMEWORK_ARGS[@]}" \
    -output "${XCFRAMEWORK_PATH}"; then
    echo -e "${RED}❌ Failed to create XCFramework${NC}"
    exit 1
fi

# Verify XCFramework was created
if [ ! -d "$XCFRAMEWORK_PATH" ]; then
    echo -e "${RED}❌ Error: XCFramework was not created at ${XCFRAMEWORK_PATH}${NC}"
    exit 1
fi

# Validate XCFramework structure
echo -e "${BLUE}🔍 Validating XCFramework structure...${NC}"
if [ ! -f "${XCFRAMEWORK_PATH}/Info.plist" ]; then
    echo -e "${RED}❌ Error: XCFramework Info.plist not found${NC}"
    exit 1
fi

# Check that we have at least one platform slice
# XCFramework structure: CryptoSwift.xcframework/ios-arm64/CryptoSwift.framework
# So we look for .framework directories inside platform directories
PLATFORM_COUNT=$(find "${XCFRAMEWORK_PATH}" -mindepth 2 -maxdepth 2 -type d -name "*.framework" | wc -l | tr -d ' ')
if [ "$PLATFORM_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ Error: XCFramework contains no platform slices${NC}"
    echo "XCFramework structure:"
    ls -la "${XCFRAMEWORK_PATH}" || true
    exit 1
fi
echo -e "${GREEN}✅ XCFramework structure validated (${PLATFORM_COUNT} platform slice(s))${NC}"

# 4. Zip & Checksum
echo -e "${BLUE}📦 Creating zip archive...${NC}"
cd "${OUTPUT_DIR}"
ZIP_FILE="${FRAMEWORK_NAME}.xcframework.zip"

if ! zip -r "${ZIP_FILE}" "${FRAMEWORK_NAME}.xcframework" -q; then
    echo -e "${RED}❌ Failed to create zip file${NC}"
    exit 1
fi

# Verify zip was created
if [ ! -f "$ZIP_FILE" ]; then
    echo -e "${RED}❌ Error: Zip file was not created${NC}"
    exit 1
fi

# Compute checksum
echo -e "${BLUE}🔐 Computing checksum...${NC}"
if ! CHECKSUM=$(swift package compute-checksum "${ZIP_FILE}"); then
    echo -e "${RED}❌ Failed to compute checksum${NC}"
    exit 1
fi

echo "=================================================="
echo -e "${GREEN}✅ SUCCESS!${NC}"
echo "Version: ${VERSION}"
echo "XCFramework: ${XCFRAMEWORK_PATH}"
echo "Zip: ${OUTPUT_DIR}/${ZIP_FILE}"
echo "Checksum: ${CHECKSUM}"
echo "=================================================="

# Save checksum to file for GitHub Actions
echo "${CHECKSUM}" > "${OUTPUT_DIR}/checksum.txt"
