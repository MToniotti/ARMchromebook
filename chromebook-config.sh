# chromebook-config.sh - Configuration file for chromebook-setup

DEBIAN_ROOTFS_URL="http://releases.linaro.org/debian/images/blend-armhf/16.09/linaro-stretch-alip-20160921-1.tar.gz"
TOOLCHAIN="gcc-linaro-arm-linux-gnueabihf-4.9-2014.07_linux"
TOOLCHAIN_URL="http://releases.linaro.org/archive/14.07/components/toolchain/binaries/\
$TOOLCHAIN.tar.xz"
KERNEL_URL="https://chromium.googlesource.com/chromiumos/third_party/kernel"
VBOOT_URL="https://chromium.googlesource.com/chromiumos/platform/vboot_reference/"
MALI_URL_BASE="https://developer.arm.com/-/media/Files/downloads/mali-drivers/user-space/firefly"
ROOTFS_DIR="$PWD/rootfs"
MALI_DEFAULT="r12p0-04rel0"
ROOT_DEFAULT="/dev/mmcblk1p2"

# Chromebook-specific config.

declare -A chromebook_names=(
    ["XE303C12"]="Samsung Chromebook 1"
    ["XE503C12"]="Samsung Chromebook 2 11.6\""
    ["XE503C32"]="Samsung Chromebook 2 13.3\""
    ["C201PA"]="ASUS Chromebook C201"
)
declare -A chromebook_configs=(
    ["XE303C12"]="chromeos-exynos5"
    ["XE503C12"]="chromeos-exynos5"
    ["XE503C32"]="chromeos-exynos5"
    ["C201PA"]="chromiumos-rockchip"
)
declare -A chromebook_dtbs=(
    ["XE303C12"]="exynos5250-snow-rev4.dtb"
    ["XE503C12"]="exynos5420-peach-pit.dtb"
    ["XE503C32"]="exynos5422-peach-pi.dtb"
    ["C201PA"]="rk3288-speedy-rev1.dtb"
)
declare -A chromebook_gpu=(
    ["XE303C12"]="mali-t60x"
    ["XE503C12"]="mali-t62x"
    ["XE503C32"]="mali-t62x"
    ["C201PA"]="mali-t76x"
)

# GPU driver/kernel-specific config.

declare -a driver_versions=(
    "r12p0_04rel0"
)

declare -A r12p0_04rel0_branches=(
    ["XE303C12"]="chromeos-3.8"
    ["XE503C12"]="chromeos-3.8"
    ["XE503C32"]="chromeos-3.8"
    ["C201PA"]="stabilize-8688.B-chromeos-3.14"
)
declare -A r12p0_04rel0_revs=(
    ["XE303C12"]="74c1be9358d02d760004bf7ff2cabc107aa071f4"
    ["XE503C12"]="74c1be9358d02d760004bf7ff2cabc107aa071f4"
    ["XE503C32"]="74c1be9358d02d760004bf7ff2cabc107aa071f4"
    ["C201PA"]="ab7cac59639460b61532620f1f2143633be1b6b7"
)
declare -A r12p0_04rel0_winsys=(
    ["XE303C12"]="fbdev x11 wayland"
    ["XE503C12"]="fbdev x11 wayland"
    ["XE503C32"]="fbdev x11 wayland"
    ["C201PA"]="fbdev wayland"
)

# Function to retrieve keys/values from associative array using indirection.

get_assoc_keys() {
    eval "echo \${!$1[@]}"
}

get_assoc_vals() {
    eval "echo \${$1[$2]}"
}
