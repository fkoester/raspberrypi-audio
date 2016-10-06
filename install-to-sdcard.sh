#! /bin/bash
## Arguments:
## $1: sd card device

SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

TARGET_DEVICE="${1}"

RASPIAN_BUILD_DATE="2016-05-27"
RASPIAN_RELEASE_DATE="2016-05-31"

IMAGE_PACKAGE="${RASPIAN_BUILD_DATE}-raspbian-jessie-lite.zip"
SHA1_SUM="03b6ea33efc3bb4d475f528421d554fc1ef91944"
RASPBIAN_BASE_IMAGE_URL="http://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-${RASPIAN_RELEASE_DATE}/${IMAGE_PACKAGE}"
DOWNLOAD_DIR="$HOME/Downloads"
WORKING_DIR=/tmp/raspberrypi-audio-streaming
MOUNT_TARGET=${WORKING_DIR}/mount
TARGET_SRC_DIR="/root/raspberrypi-audio-streaming"
MOUNTED_TARGET_SRC_DIR="${MOUNT_TARGET}/root/raspberrypi-audio-streaming"

source ./common.sh

function cleanup {
  sudo umount --recursive ${MOUNT_TARGET} || echo "Failed to unmount target device fs"
  sudo kpartx -d ${TARGET_DEVICE} || die "Could not delete partition mappings"
}

function cleanup_and_die {
  cleanup
  die "${1}"
}

if [ ! -b "${TARGET_DEVICE}" ]; then
  die "Given argument is not a valid block device"
fi
TARGET_DEVICE_BASENAME=$(basename ${TARGET_DEVICE})

rm -rf ${WORKING_DIR} || die "Failed to cleanup working directory"

mkdir -p "${DOWNLOAD_DIR}" || die "Failed to create required directories"
mkdir -p "${WORKING_DIR}" || die "Failed to create required directories"
mkdir -p ${MOUNT_TARGET} || die "Failed to create required directories"

cd "$DOWNLOAD_DIR"

if [ ! -f ${IMAGE_PACKAGE} ]; then
  log_info "Downloading raspbian lite image..."
  curl -L -o ${IMAGE_PACKAGE} ${RASPBIAN_BASE_IMAGE_URL} || die "Failed to download package"
else
  log_info "Found existing raspian lite image, skipping download."
fi

log_info "Checking integrity of downloaded file..."
echo "${SHA1_SUM} ${IMAGE_PACKAGE}" | sha1sum -c - || die "Checksum did not match"

log_info "Check was successful."
log_info "Unpacking file..."
unzip "${IMAGE_PACKAGE}" -d ${WORKING_DIR} || die "Failed to unzip package"
log_info "Unpacking complete."

IMAGE_FILE="${IMAGE_PACKAGE/%zip/img}"

cd "${WORKING_DIR}"
log_info "Copying image to sdcard..."
sudo dd bs=4M if="${IMAGE_FILE}" of="${TARGET_DEVICE}" || die "Failed to copy image to sd card"
sudo sync

log_info "Mounting target filesystems"
sudo kpartx -as ${TARGET_DEVICE} || die "Could not add partition mappings"

sudo mount /dev/mapper/${TARGET_DEVICE_BASENAME}p2 ${MOUNT_TARGET} || cleanup_and_die "Could not mount target device root fs"
sudo mount /dev/mapper/${TARGET_DEVICE_BASENAME}p1 ${MOUNT_TARGET}/boot || cleanup_and_die "Could not mount target device boot fs"

log_info "Performing setup inside target filesystem..."
sudo proot -q qemu-arm -r ${MOUNT_TARGET} \
  -b ${SRC_DIR}:${TARGET_SRC_DIR} \
  -b /etc/resolv.conf \
  -b /dev \
  -b /sys \
  -b /proc \
  -w ${TARGET_SRC_DIR} "./setup.sh" || cleanup_and_die "Setup failed"

log_info "Unmounting and cleaning up..."
cleanup