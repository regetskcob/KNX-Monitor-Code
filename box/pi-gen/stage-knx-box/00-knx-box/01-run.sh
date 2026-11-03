#!/bin/bash -e
# Install the box bundle (build-image.sh puts it under files/bundle) in the chroot.
rm -rf "${ROOTFS_DIR}/tmp/knx-box"
cp -a files/bundle "${ROOTFS_DIR}/tmp/knx-box"
on_chroot <<CHROOT
/tmp/knx-box/setup.sh --image
rm -rf /tmp/knx-box
# No password login for the maintenance account; SSH with key only.
usermod -p '*' "${FIRST_USER_NAME}"
CHROOT
