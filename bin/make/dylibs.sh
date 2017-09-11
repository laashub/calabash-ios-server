#!/usr/bin/env bash

set -e

source bin/log.sh
source bin/ditto.sh

function xcode_gte_7 {
 XC_MAJOR=`xcrun xcodebuild -version | awk 'NR==1{print $2}' | awk -v FS="." '{ print $1 }'`
 if [ "${XC_MAJOR}" \> "7" -o "${XC_MAJOR}" = "7" ]; then
   echo "true"
 else
   echo "false"
 fi
}

XC_GTE_7=$(xcode_gte_7)

XC_TARGET=calabash-dylib
XC_PROJECT=calabash.xcodeproj
XC_SCHEME=calabash-dylib
XC_BUILD_CONFIG=Debug

SIM_BUILD_DIR=build/dylib/sim
mkdir -p "${SIM_BUILD_DIR}"

ARM_BUILD_DIR=build/dylib/arm
mkdir -p "${ARM_BUILD_DIR}"

PRODUCTS_DIR=Products/dylib
rm -rf "${PRODUCTS_DIR}"
mkdir -p "${PRODUCTS_DIR}"

SIM_PRODUCTS_DIR="${PRODUCTS_DIR}/sim"
mkdir -p "${SIM_PRODUCTS_DIR}"

ARM_PRODUCTS_DIR="${PRODUCTS_DIR}/arm"
mkdir -p "${ARM_PRODUCTS_DIR}"

FAT_PRODUCTS_DIR="${PRODUCTS_DIR}/fat"
mkdir -p "${FAT_PRODUCTS_DIR}"

INSTALL_DIR=calabash-dylibs
rm -rf "${INSTALL_DIR}"

LIBRARY_NAME=calabash-dylib.dylib

if [ "${XCPRETTY}" = "0" ]; then
  USE_XCPRETTY=
else
  USE_XCPRETTY=`which xcpretty | tr -d '\n'`
fi

if [ ! -z ${USE_XCPRETTY} ]; then
  XC_PIPE='xcpretty -c'
else
  XC_PIPE='cat'
fi

banner "Building Dylib Simulator Library"

SIM_BUILD_PRODUCTS_DIR="${SIM_BUILD_DIR}/Build/Products/${XC_BUILD_CONFIG}-iphonesimulator"
SIM_LIBRARY="${SIM_BUILD_PRODUCTS_DIR}/${LIBRARY_NAME}"
rm -rf "${SIM_LIBRARY}"

# Xcode issues non-fatal warnings re: this directory is missing.
# Xcode will eventually create the directory, but if we create it
# ourselves, we can suppress the warnings.
mkdir -p "${SIM_BUILD_PRODUCTS_DIR}"

xcrun xcodebuild build \
  -project ${XC_PROJECT} \
  -scheme ${XC_SCHEME} \
  -SYMROOT="${SIM_BUILD_DIR}" \
  -derivedDataPath "${SIM_BUILD_DIR}" \
  -configuration "${XC_BUILD_CONFIG}" \
  ARCHS="i386 x86_64" \
  VALID_ARCHS="i386 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  EFFECTIVE_PLATFORM_NAME="-iphonesimulator" \
  -sdk iphonesimulator \
  IPHONEOS_DEPLOYMENT_TARGET=6.0 \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_GENERATE_TEST_COVERAGE_FILES=NO \
  GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO | $XC_PIPE

EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE != 0 ]; then
  error "Building simulator library for framework failed."
  exit $RETVAL
else
  info "Building simulator library for framework succeeded."
fi

ditto_or_exit "${SIM_LIBRARY}" "${SIM_PRODUCTS_DIR}/${LIBRARY_NAME}"

HEADERS="${SIM_BUILD_DIR}/Build/Products/Debug-iphonesimulator/usr/local/include"

banner "Building Dylib ARM Library"

ARM_LIBRARY_XC7="${ARM_BUILD_DIR}/Build/Intermediates/ArchiveIntermediates/calabash-dylib/InstallationBuildProductsLocation/usr/local/lib/${LIBRARY_NAME}"
rm -rf "${ARM_LIBRARY_XC7}"

ARM_LIBRARY_XC6="${ARM_BUILD_DIR}/Build/Products/${XC_BUILD_CONFIG}-iphoneos/${LIBRARY_NAME}"
rm -rf "${ARM_LIBRARY_XC6}"

if [ "${XC_GTE_7}" = "true" ]; then
  XC7_FLAGS="OTHER_CFLAGS=\"-fembed-bitcode\" DEPLOYMENT_POSTPROCESSING=YES ENABLE_BITCODE=YES"
fi

xcrun xcodebuild install \
  -project "${XC_PROJECT}" \
  -scheme "${XC_SCHEME}" \
  -SYMROOT="${ARM_BUILD_DIR}" \
  -derivedDataPath "${ARM_BUILD_DIR}" \
  -configuration "${XC_BUILD_CONFIG}" \
  ARCHS="armv7 armv7s arm64" \
  VALID_ARCHS="armv7 armv7s arm64" \
  ${XC7_FLAGS} -sdk iphoneos \
  IPHONE_DEPLOYMENT_TARGET=6.0 \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_GENERATE_TEST_COVERAGE_FILES=NO \
  GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO | $XC_PIPE

EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE != 0 ]; then
  error "Building ARM library for framework failed."
  exit $RETVAL
else
  info "Building ARM library for framework succeeded."
fi

if [ -e "${ARM_LIBRARY_XC7}" ]; then
  ARM_LIBRARY="${ARM_LIBRARY_XC7}"
else
  ARM_LIBRARY="${ARM_LIBRARY_XC6}"
fi

ditto_or_exit "${ARM_LIBRARY}" "${ARM_PRODUCTS_DIR}/${LIBRARY_NAME}"

banner "Installing Dylibs"

FAT_LIBRARY="${FAT_PRODUCTS_DIR}/libCalabashFAT.dylib"

xcrun lipo -create \
  "${SIM_PRODUCTS_DIR}/${LIBRARY_NAME}" \
  "${ARM_PRODUCTS_DIR}/${LIBRARY_NAME}" \
  -o "${FAT_LIBRARY}"

TARGET_LIB="${PWD}/${INSTALL_DIR}/libCalabashFAT.dylib"
info "Installing FAT library to ${TARGET_LIB}"
ditto_or_exit "${FAT_LIBRARY}" "${TARGET_LIB}"

TARGET_LIB="${PWD}/${INSTALL_DIR}/libCalabashSim.dylib"
info "Installing simulator library to ${TARGET_LIB}"
ditto_or_exit "${SIM_PRODUCTS_DIR}/${LIBRARY_NAME}" "${TARGET_LIB}"

TARGET_LIB="${PWD}/${INSTALL_DIR}/libCalabashARM.dylib"
info "Installing ARM library to ${TARGET_LIB}"
ditto_or_exit "${ARM_PRODUCTS_DIR}/${LIBRARY_NAME}" "${TARGET_LIB}"

info "Installing Headers to ${PWD}/${INSTALL_DIR}"
ditto_or_exit "${HEADERS}" "${INSTALL_DIR}/Headers"
ditto_to_zip "${INSTALL_DIR}/Headers" "${INSTALL_DIR}/Headers.zip"

banner "Dylib Code Signing"

CODE_SIGN_DIR="${HOME}/.calabash/calabash-codesign"
RESIGN_TOOL="${CODE_SIGN_DIR}/apple/resign-ios-dylib.rb"
SHA_TOOL="${CODE_SIGN_DIR}/sha256"

CERT="${CODE_SIGN_DIR}/apple/certs/calabash-developer.p12"

echo ${KEYCHAIN_TOOL}

if [ ! -e ${CODE_SIGN_DIR} ]; then
  warn "Skipping dylib codesiging!"
  warn "If you are not a maintainer, you can ignore this warning"
  warn "If you are maintainer, you should be resigning!"
  warn "See: https://github.com/calabash/calabash-codesign"
  exit 0

else

  EXPECTED_SHA=$1
  ACTUAL_SHA=`$SHA_TOOL $CERT`

  if [ "${EXPECTED_SHA}" != "${ACTUAL_SHA}" ]; then
    error "Expected cert checksum: ${EXPECTED_SHA}"
    error "  Actual cert checksum: ${ACTUAL_SHA}"
    error ""
    error "You must update your local code signing tool"
    error "$ cd ~/.calabash/calabash-codesign"
    error "$ git checkout master"
    error "$ git pull"
    exit 1
  fi

  info "Creating the Calabash.keychain"
  (cd "${CODE_SIGN_DIR}" && apple/create-keychain.sh)

  info "Resiging the device dylib"
  $RESIGN_TOOL "${INSTALL_DIR}/libCalabashARM.dylib"

  info "Resiging the FAT dylib"
  $RESIGN_TOOL "${INSTALL_DIR}/libCalabashFAT.dylib"

  xcrun codesign --display --verbose=2\
    ${INSTALL_DIR}/libCalabashARM.dylib
fi

banner "Dylib Info"

VERSION=`xcrun strings "${INSTALL_DIR}/libCalabashSim.dylib" | grep -E 'CALABASH VERSION' | head -1 | grep -oEe '\d+\.\d+\.\d+' | tr -d '\n'`
echo "Built version:  $VERSION"

lipo -info "${INSTALL_DIR}/libCalabashARM.dylib"
lipo -info "${INSTALL_DIR}/libCalabashSim.dylib"
lipo -info "${INSTALL_DIR}/libCalabashFAT.dylib"

if [ "${XC_GTE_7}"  = "true" ]; then

  xcrun otool-classic -arch arm64 -l \
    "${INSTALL_DIR}/libCalabashARM.dylib" | grep -q LLVM
  if [ $? -eq 0 ]; then
    echo "libCalabashARM.dylib contains bitcode for arm64"
  else
    echo "libCalabashARM.dylib does not contain bitcode for arm64"
    exit 1
  fi

  xcrun otool-classic -arch armv7s -l \
    "${INSTALL_DIR}/libCalabashARM.dylib" | grep -q LLVM
  if [ $? -eq 0 ]; then
    echo "libCalabashARM.dylib contains bitcode for armv7s"
  else
    echo "libCalabashARM.dylib does not contain bitcode for armv7s"
    exit 1
  fi

  xcrun otool-classic -arch armv7 -l \
    "${INSTALL_DIR}/libCalabashARM.dylib" | grep -q LLVM
  if [ $? -eq 0 ]; then
    echo "libCalabashARM.dylib contains bitcode for armv7"
  else
    echo "libCalabashARM.dylib does not contain bitcode for armv7"
    exit 1
  fi
fi

# Legacy.  Can be changed once calabash-ios gem is updated.
ditto_or_exit \
  "${INSTALL_DIR}/libCalabashARM.dylib" \
  "${INSTALL_DIR}/libCalabashDyn.dylib"

ditto_or_exit \
  "${INSTALL_DIR}/libCalabashSim.dylib" \
  "${INSTALL_DIR}/libCalabashDynSim.dylib"
