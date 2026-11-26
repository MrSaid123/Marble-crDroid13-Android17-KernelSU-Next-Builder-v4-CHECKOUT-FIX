properties() { '
kernel.string=Poco F5 | Redmi Note 12 Turbo
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=marble
device.name2=marblein
supported.versions=
supported.patchlevels=
'; }

block=boot;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

. tools/ak3-core.sh;

ui_print " "
ui_print "███████╗ ██████╗ ██╗███████╗"
ui_print "╚══███╔╝██╔═══██╗██║██╔════╝"
ui_print "  ███╔╝ ██║   ██║██║███████╗"
ui_print " ███╔╝  ██║   ██║██║╚════██║"
ui_print "███████╗╚██████╔╝██║███████║"
ui_print "╚══════╝ ╚═════╝ ╚═╝╚══════╝"
ui_print " "
ui_print "        Marble Kernel Builder"
ui_print " "

# AnyKernel3 performs the marble/marblein device check from properties()
# (device.name1/device.name2). Do not gate by ROM branding: crDroid 13.1 is
# supported as a target ROM and does not identify itself as the builder author.

backup_current_boot() {
  backup_dir="/sdcard/marble-kernel-backup";
  slot_name="${SLOT:-noslot}";
  stamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s)";
  backup_img="${backup_dir}/boot-marble-${slot_name}-${stamp}.img";
  backup_txt="${backup_dir}/boot-marble-${slot_name}-${stamp}.txt";

  ui_print "Backing up current boot image...";
  mkdir -p "$backup_dir" || abort "Unable to create ${backup_dir}. Aborting...";

  if [ ! -s "$BOOTIMG" ]; then
    abort "Dumped boot image is missing. Backup failed; aborting for safety.";
  fi;

  cp -f "$BOOTIMG" "$backup_img" || abort "Unable to save boot backup. Aborting...";
  {
    echo "device=marble/marblein";
    echo "slot=${slot_name}";
    echo "source_block=${BLOCK}";
    echo "created=${stamp}";
    echo "backup=${backup_img}";
  } > "$backup_txt" 2>/dev/null || true;

  ui_print "Backup saved:";
  ui_print "  ${backup_img}";
}

# MARBLE_KERNEL_ONLY_FLASH_BEGIN
# Intentionally override AnyKernel3's generic write_boot(), which otherwise
# attempts writes to vendor_boot/vendor_kernel_boot/vendor_dlkm/system_dlkm/dtbo
# when matching payload files are present. This builder ships only Image and
# must update only the boot partition while preserving all device-tree images.
write_boot() {
  for forbidden in dtb dtb.img dtbo dtbo.img vendor_boot vendor_boot.img \
                   vendor_kernel_boot vendor_kernel_boot.img vendor_dlkm vendor_dlkm.img \
                   system_dlkm system_dlkm.img vendor_boot-files vendor_kernel_boot-files \
                   vendor_dlkm-files system_dlkm-files; do
    if [ -e "$AKHOME/$forbidden" ]; then
      abort "Unexpected external-partition payload '$forbidden' in boot-only package. Aborting...";
    fi;
  done;
  ui_print "Kernel-only mode: updating boot; vendor_boot/DTBO/modules are untouched.";
  repack_ramdisk;
  flash_boot;
}
# MARBLE_KERNEL_ONLY_FLASH_END

dump_boot;
backup_current_boot;
write_boot;
