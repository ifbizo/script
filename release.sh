#!/bin/bash

user_error() {
  echo user error, please replace user and try again >&2
  exit 1
}

[[ $# -eq 1 ]] || user_error
[[ -n $BUILD_NUMBER ]] || user_error

KEY_DIR=keys/$1
OUT=out/release-$1-$BUILD_NUMBER

source device/common/clear-factory-images-variables.sh

get_radio_image() {
  grep -Po "require version-$1=\K.+" vendor/$2/vendor-board-info.txt | tr '[:upper:]' '[:lower:]'
}

if [[ $1 == marlin || $1 == sailfish || $1 == taimen || $1 == walleye || $1 == blueline || $1 == crosshatch || $1 == sargo ]]; then
  BOOTLOADER=$(get_radio_image bootloader google_devices/$1)
  RADIO=$(get_radio_image baseband google_devices/$1)
  PREFIX=aosp_
elif [[ $1 == hikey || $1 == hikey960 ]]; then
  :
else
  user_error
fi

BUILD=$BUILD_NUMBER
VERSION=$(grep -Po "export BUILD_ID=\K.+" build/core/build_id.mk | tr '[:upper:]' '[:lower:]')
DEVICE=$1
PRODUCT=$1

mkdir -p $OUT || exit 1

TARGET_FILES=$DEVICE-target_files-$BUILD.zip

if [[ $DEVICE != hikey* ]]; then
  if [[ $DEVICE == marlin || $DEVICE == sailfish ]]; then
    VERITY_SWITCHES=(--replace_verity_public_key "$KEY_DIR/verity_key.pub" --replace_verity_private_key "$KEY_DIR/verity"
                     --replace_verity_keyid "$KEY_DIR/verity.x509.pem")
  elif [[ $DEVICE == blueline || $DEVICE == crosshatch || $DEVICE == sargo ]]; then
    VERITY_SWITCHES=(--avb_vbmeta_key "$KEY_DIR/avb.pem" --avb_vbmeta_algorithm SHA256_RSA2048
                     --avb_system_key "$KEY_DIR/avb.pem" --avb_system_algorithm SHA256_RSA2048)
    AVB_PKMD="$PWD/$KEY_DIR/avb_pkmd.bin"
  else
    VERITY_SWITCHES=(--avb_vbmeta_key "$KEY_DIR/avb.pem" --avb_vbmeta_algorithm SHA256_RSA2048)
    AVB_PKMD="$PWD/$KEY_DIR/avb_pkmd.bin"
  fi
fi

build/tools/releasetools/sign_target_files_apks -o -d "$KEY_DIR" "${VERITY_SWITCHES[@]}" \
  out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$PREFIX$DEVICE-target_files-$BUILD_NUMBER.zip \
  $OUT/$TARGET_FILES || exit 1

if [[ $DEVICE != hikey* ]]; then
  build/tools/releasetools/ota_from_target_files --block -k "$KEY_DIR/releasekey" "${EXTRA_OTA[@]}" $OUT/$TARGET_FILES \
    $OUT/$DEVICE-ota_update-$BUILD.zip || exit 1
fi

build/tools/releasetools/img_from_target_files $OUT/$TARGET_FILES \
  $OUT/$DEVICE-img-$BUILD.zip || exit 1

cd $OUT || exit 1

if [[ $DEVICE == hikey* ]]; then
  source ../../device/linaro/hikey/factory-images/generate-factory-images-$DEVICE.sh
else
  source ../../device/common/generate-factory-images-common.sh
fi

mv $DEVICE-$VERSION-factory-*.zip $DEVICE-factory-$BUILD_NUMBER.zip
