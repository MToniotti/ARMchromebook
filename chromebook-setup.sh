#!/bin/bash

set -e

source chromebook-config.sh

print_usage_exit()
{
    local arg_ret="${1-1}"

    echo "
ARM Mali Chromebook developer tool.

Environment variables:

  CROSS_COMPILE

    Standard variable to use a cross-compiler toolchain.  If it is not
    already defined before calling this script, it will be set by
    default in this script to match the toolchain downloaded using the
    get_toolchain command.

Usage:

  $0 COMMAND [ARGS] OPTIONS

  Only COMMAND and ARGS are positional arguments; the OPTIONS can be
  placed anywhere and in any order.  The definition of ARGS varies
  with each COMMAND.

Options:

  The following options are common to all commands.  Only --storage
  and --variant are compulsory, the --mali option has a default value
  to use the latest driver available.

  --storage=PATH
    Path to the Chromebook storage device i.e. the SD card.
"
echo "  --variant=VARIANT
    Chromebook variant, needs to be one of the following:"

for chromebook_variant in "${!chromebook_names[@]}"
do
    echo "      $chromebook_variant (${chromebook_names[$chromebook_variant]})"
done

echo "
  --mali=MALI_VERSION
    Mali driver version identifier, by default $MALI_DEFAULT.
    Supported driver versions are:"

for driver_version in "${driver_versions[@]}"
do
    echo "      $driver_version, supporting:" | tr _ -

    for chromebook_variant in $(get_assoc_keys "$driver_version"_branches)
    do
        echo "        $chromebook_variant (${chromebook_names[$chromebook_variant]})"
    done
    echo
done

echo "Available commands:

  help
    Print this help message.

  do_everything
    Do everything in one command with default settings.

  format_storage
    Format the storage device to be used as a bootable SD card or USB
    stick on the Chromebook.  The device passed to the --storage
    option is used.

  setup_rootfs [ARCHIVE]
    Install the rootfs on the storage device specified with --storage.
    The root partition will first be mounted in a local rootfs
    directory, then the rootfs archive will be extracted onto it.  If
    ARCHIVE is not provided then the default one will be automatically
    downloaded and used.  The partition will then remain mounted in
    order to run other commands.  The standard rootfs URL is:
        $DEBIAN_ROOTFS_URL

  get_mali
    Downloads the Mali user-side driver archives. The name of
    the binary archives is determined automatically with the combined
    --mali and --variant options.

  install_mali
    Install the Mali user-side drivers onto the rootfs.  The name of
    the binary archives is determined automatically with the combined
    --mali and --variant options.

  get_toolchain
    Download and extract the cross-compiler toolchain needed to build
    the bootloader and Linux kernel.  It is fixed to this version:
        $TOOLCHAIN_URL

    In order to use an alternative toolchain, the CROSS_COMPILE
    environment variable can be set before calling this script to
    point at the toolchain of your choice.

  get_kernel [URL]
    Get the kernel source code matching the Mali driver version
    selected with --mali or the latest by default into a branch of the
    same name and automatically apply any extra patches as required.
    The optional URL argument is to specify an alternative Git
    repository, the default one being:
        $KERNEL_URL

  build_kernel
    Compile the Linux kernel and install the modules on the rootfs.

  get_vboot [URL]
    Get the vboot source code from Git, the default URL is:
        $VBOOT_URL

  build_vboot [ROOT]
    Build vboot and install it along with the kernel main image on the
    boot partition of the storage device.  The optional ROOT argument
    is the root device to pass to the kernel, by default the standard
    one for SD cards:
        $ROOT_DEFAULT

For example, to do everything for the Samsung Chromebook 1:

  $0 do_everything --variant=XE303C12 --storage=/dev/sdX
"

    exit $arg_ret
}

opts=$(getopt -o "s:" -l "storage:,variant:,mali:" -- "$@")
eval set -- "$opts"

while true; do
    case "$1" in
        --storage)
            CB_SETUP_STORAGE="$2"
            shift 2
            ;;
        --variant)
            CB_SETUP_VARIANT="$2"
            shift 2
            ;;
        --mali)
            CB_SETUP_MALI="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Internal error"
            exit 1
            ;;
    esac
done

cmd="$1"
[ -z "$cmd" ] && print_usage_exit
shift

# -----------------------------------------------------------------------------
# Options sanitising

[ -n "$CB_SETUP_STORAGE" ] && [ -b "$CB_SETUP_STORAGE" ] || {
    echo "Incorrect storage device passed to the --storage option."
    print_usage_exit
}

if [ -z "${chromebook_names[$CB_SETUP_VARIANT]}" ]; then
    echo "Unknown Chromebook variant passed to the --variant option."
    print_usage_exit
else
    echo "Configured for ${chromebook_names[$CB_SETUP_VARIANT]}"
fi

[ -z "$CB_SETUP_MALI" ] && CB_SETUP_MALI="$MALI_DEFAULT"
echo "Mali driver version: $CB_SETUP_MALI"

[ -z "$CROSS_COMPILE" ] && export CROSS_COMPILE=\
$PWD/$TOOLCHAIN/bin/arm-linux-gnueabihf-

export ARCH=arm

# -----------------------------------------------------------------------------
# Utility functions

jopt()
{
    echo "-j"$(grep -c processor /proc/cpuinfo)
}

# -----------------------------------------------------------------------------
# Functions to run each command

cmd_help()
{
    print_usage_exit 0
}

cmd_format_storage()
{
    echo "Creating partitions on $CB_SETUP_STORAGE"
    df 2>&1 | grep "$CB_SETUP_STORAGE" || echo -n
    read -p "Continue? [N/y] " yn
    [ "$yn" = "y" ] || {
        echo "Aborted"
        exit 1
    }

    # Unmount any partitions automatically mounted
    sudo umount "$CB_SETUP_STORAGE"? || echo -n

    # Clear the partition table
    sudo sgdisk -Z "$CB_SETUP_STORAGE"

    # Create the boot partition and set it as bootable
    sudo sgdisk -n 1:0:+16M -t 1:7f00 "$CB_SETUP_STORAGE"

    # Set special metadata understood by the Chromebook.  These flags
    # are not standard thus do not have names.  For more details, see
    # the cgpt sources which can be found in vboot_reference repo in
    # the next sections.
    sudo sgdisk -A 1:set:48 -A 1:set:56 "$CB_SETUP_STORAGE"

    # Create and format the root partition
    sudo sgdisk -n 2:0:0 -t 2:7f01 "$CB_SETUP_STORAGE"
    sudo mkfs.ext4 -L mali_root "$CB_SETUP_STORAGE"2

    echo "Done."
}

cmd_setup_rootfs()
{
    local debian_url="${1:-$DEBIAN_ROOTFS_URL}"
    local debian_archive=$(basename $debian_url)

    echo "Mounting rootfs partition in $ROOTFS_DIR"
    local part="$CB_SETUP_STORAGE"2
    mkdir -p "$ROOTFS_DIR"
    sudo umount "$ROOTFS_DIR" || echo -n
    sudo mount "$part" "$ROOTFS_DIR"

    # Download the Debian rootfs archive if it's not already there.
    if [ ! -f "$debian_archive" ]; then
        echo "Rootfs archive not found, downloading from $debian_url"
        wget "$debian_url"
    fi

    # Untar the rootfs archive.
    echo "Extracting files onto the partition"
    sudo tar xf "$debian_archive" -C "$ROOTFS_DIR" binary --strip=1

    echo "Allowing root login without password"
    sudo sed -i -e "s/root:x:0:0/root::0:0/" "$ROOTFS_DIR"/etc/passwd

    echo "Adjusting LD_LIBRARY_PATH for windowing system in root/.bashrc"
    cat data/dot-bashrc-mali | sudo tee -a "$ROOTFS_DIR"/root/.bashrc > /dev/null
    cat data/dot-bashrc-mali | sudo tee -a "$ROOTFS_DIR"/etc/skel/.bashrc > /dev/null

    if [[ $(get_assoc_vals ${CB_SETUP_MALI/"-"/"_"}_winsys $CB_SETUP_VARIANT) =~ "x11" ]]; then
        echo "Creating root/.xinitrc"
        sudo install -o root -g root -m 0644 data/dot-xinitrc \
            "$ROOTFS_DIR"/root/.xinitrc

        echo "Creating usr/share/X11/xorg.conf.d/05-mali.conf"
        sudo install -o root -g root -m 0644 -D data/xorg.conf \
            "$ROOTFS_DIR"/usr/share/X11/xorg.conf.d/05-mali.conf

        echo "Adding X11 install script"
        sudo install -o root -g root -m 0755 data/install-x11.sh \
        "$ROOTFS_DIR"/root/install-x11.sh
    fi

    if [[ $(get_assoc_vals ${CB_SETUP_MALI/"-"/"_"}_winsys $CB_SETUP_VARIANT) =~ "wayland" ]]; then
        echo "Adding Wayland install script"
        sudo install -o root -g root -m  0755 data/install-wayland.sh \
            "$ROOTFS_DIR"/root/install-wayland.sh
    fi

    echo "Adding firmware install script"
    sudo install -o root -g root -m  0755 data/install-fw.sh \
        "$ROOTFS_DIR"/root/install-fw.sh

    echo "Done."
}

cmd_get_mali()
{
    # Suffix used in archive name
    local sx="linux1"

    # Define prefix used in archive name for Mali and Chromebook versions
    local px="${chromebook_gpu[$CB_SETUP_VARIANT]}"

    # Download the Mali binaries for each windowing system
    for wsys in $(get_assoc_vals ${CB_SETUP_MALI/"-"/"_"}_winsys $CB_SETUP_VARIANT); do
        local archive="$px""$CB_SETUP_MALI""$sx""$wsys"
	archive=${archive//-}
        [ -f "$archive".tar.gz ] || {
	    
            echo "Downloading "$archive
            wget -O "$archive".tar.gz "$MALI_URL_BASE"/"$archive"tar.gz
        }
    done
}

cmd_install_mali()
{
    # Suffix used in archive name
    local sx="linux1"

    # Define prefix used in archive name for Mali and Chromebook versions
    local px="${chromebook_gpu[$CB_SETUP_VARIANT]}"

    local mali_dir="$ROOTFS_DIR"/root/mali
    sudo mkdir -p "$mali_dir"

    # Extract the Mali binaries for each windowing system in /root/mali/$wsys
    for wsys in $(get_assoc_vals ${CB_SETUP_MALI/"-"/"_"}_winsys $CB_SETUP_VARIANT); do
        local archive="$px""$CB_SETUP_MALI""$sx""$wsys".tar.gz
        archive=${archive//-}
        [ -f "$archive" ] || {
            echo "Mali driver archive not found: $archive"
            exit 1
        }
        echo "Installing drivers from $archive"
        sudo tar xf "$archive" -C "$mali_dir" "$wsys"
        sudo chown -R root: "$mali_dir"/"$wsys"
    done

    echo "Done."
}

cmd_get_toolchain()
{
    [ -d "$TOOLCHAIN" ] && {
        echo "Toolchain already downloaded: $TOOLCHAIN"
        return 0
    }

    echo "Downloading and extracting toolchain: $url"
    curl -L "$TOOLCHAIN_URL" | tar xJf -

    echo "Done."
}

cmd_get_kernel()
{
    local arg_url="${1-$KERNEL_URL}"

    # Pick a Git revision that matches the provided Mali driver version
    # (SHAs are used when there is no suitable tag available)

    if [ -z "$(get_assoc_vals ${CB_SETUP_MALI/"-"/"_"}_branches $CB_SETUP_VARIANT)" ]; then
        echo "Unknown Mali driver version: $CB_SETUP_MALI"
        exit 1
    else
        local branch=$(get_assoc_vals ${CB_SETUP_MALI/"-"/"_"}_branches $CB_SETUP_VARIANT)
        local rev=$(get_assoc_vals ${CB_SETUP_MALI/"-"/"_"}_revs $CB_SETUP_VARIANT)
    fi

    # Create initial git repository if not already present
    [ -d kernel ] || {
        echo "Getting kernel repository for Mali $CB_SETUP_MALI"
        git clone "$arg_url" kernel
    }

    cd kernel

    # If not already there, create branch with given revision and apply patches
    git branch | grep "$CB_SETUP_MALI-$CB_SETUP_VARIANT" > /dev/null || {

        git checkout "$branch"

        echo "Checking out revision $rev into branch $CB_SETUP_MALI-$CB_SETUP_VARIANT"
        git checkout "$rev" -b "$CB_SETUP_MALI"-"$CB_SETUP_VARIANT"

        local patch_dir="../data/patch-$CB_SETUP_MALI/$branch-$rev"
        [ -d "$patch_dir" ] && {
            echo "Applying patches from $patch_dir"
            git am "$patch_dir"/*
        }
    }

    # Use that branch
    git checkout "$CB_SETUP_MALI-$CB_SETUP_VARIANT"

    cd - > /dev/null

    echo "Done."
}

cmd_build_kernel()
{
    local dtb=${chromebook_dtbs[$CB_SETUP_VARIANT]}

    cd kernel

    # Create .config
    ./chromeos/scripts/prepareconfig ${chromebook_configs[$CB_SETUP_VARIANT]}
    make olddefconfig

    # Build kernel + modules + device tree blob
    make CFLAGS_KERNEL="-w" CFLAGS_MODULE="-w" zImage modules dtbs $(jopt)

    # Make boot image blob
    local kernel_its="/dts-v1/;
    / {
    description = \"Chrome OS kernel image with one or more FDT blobs\";
    #address-cells = <1>;
    images {
        kernel@1{
            description = \"kernel\";
            data = /incbin/(\"arch/arm/boot/zImage\");
            type = \"kernel_noload\";
            arch = \"arm\";
            os = \"linux\";
            compression = \"none\";
            load = <0>;
            entry = <0>;
        };
        fdt@1{
            description = \"$dtb\";
            data = /incbin/(\"arch/arm/boot/dts/$dtb\");
            type = \"flat_dt\";
            arch = \"arm\";
            compression = \"none\";
            hash@1{
                algo = \"sha1\";
            };
        };
    };
    configurations {
        default = \"conf@1\";
        conf@1{
            kernel = \"kernel@1\";
            fdt = \"fdt@1\";
        };
      };
    };"

    echo "$kernel_its" > kernel.its
    mkimage -f kernel.its kernel.itb

    # Install the kernel modules on the rootfs
    sudo make modules_install ARCH=arm INSTALL_MOD_PATH=../rootfs

    cd - > /dev/null

    echo "Done."
}

cmd_get_vboot()
{
    local arg_url="${1-$VBOOT_URL}"

    [ -d vboot ] || {
        echo "Getting initial vboot repository"
        git clone "$arg_url" vboot
    }

    # Only one revision for all variants and no extra patches
    local rev=0f6679e8582219b40e2ab5485992827a92c18bcd
    local local_branch=mali-chromebook-setup

    cd vboot
    git branch | grep "$local_branch" || {
        echo "Checking out vboot revision $rev onto branch $local_branch"
        git checkout $rev -b "$local_branch"
    }

    git checkout "$local_branch"
    cd - > /dev/null

    echo "Done."
}

cmd_build_vboot()
{
    local arg_root="${1-$ROOT_DEFAULT}"

    cd vboot

    # Build the bootloader
    make $(jopt)

    # Install it on the boot partition
    echo "console=tty1 loglevel=4 root=$arg_root rootwait rw rootfstype=ext4 lsm.module_locking=0" > boot_params
    local boot="$CB_SETUP_STORAGE"1
    sudo ./build/utility/vbutil_kernel --pack "$boot" --keyblock tests/devkeys/kernel.keyblock --version 1 --signprivate tests/devkeys/kernel_data_key.vbprivk --config boot_params --vmlinuz ../kernel/kernel.itb --arch arm

    cd - > /dev/null

    echo "Done."
}

cmd_do_everything()
{
    cmd_format_storage
    cmd_setup_rootfs
    cmd_get_mali
    cmd_install_mali
    cmd_get_toolchain
    cmd_get_kernel
    cmd_build_kernel
    cmd_get_vboot
    cmd_build_vboot

    echo "Ejecting storage device..."
    sync
    sudo eject "$CB_SETUP_STORAGE"
    echo "All done."
}

# Run the command if it's valid, otherwise abort
type cmd_$cmd > /dev/null 2>&1 || print_usage_exit
cmd_$cmd $@

exit 0
