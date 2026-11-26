# POCO F5 (marble) — crDroid 13.1 / Android 17 build profile

This builder profile uses the LineageOS `lineage-24.0` kernel, modules and
Devicetree repositories as the Android 17 baseline for marble:

- `LineageOS/android_kernel_xiaomi_sm8450`
- `LineageOS/android_kernel_xiaomi_sm8450-modules`
- `LineageOS/android_kernel_xiaomi_sm8450-devicetrees` (checked out under
  `external/marble-devicetrees` for validation only; not overlaid or packaged)
- branch: `lineage-24.0`
- base defconfig: `gki_defconfig`
- fragments: `vendor/waipio_GKI.config`, `vendor/xiaomi_GKI.config`,
  `vendor/marble_GKI.config`, `vendor/debugfs.config`
- compiler: Android Clang `clang-r416183b`

The profile is a source-compatible candidate, not a claim that a kernel has
already been built or boot-tested on crDroid 13.1. The official LineageOS
marble build guide lists `lineage-24.0` as a supported branch; crDroid 13.1
for marble is Android 17. The exact kernel revision used by the crDroid
maintainer's November 2026 build has not been independently confirmed here.

## GitHub Actions

Run **Build Marble Kernel** with:

- Kernel source: `lineage-24.0-marble`
- Build: `KernelSU-Next`
- SUSFS: enabled
- Toolchain: `auto`
- LTO: `thin`
- Build scope: `image-only`

The generated AnyKernel3 installer no longer rejects the ROM solely because
its build fingerprint does not identify Pablo/AOSPA. Device matching remains
restricted by AnyKernel3's `marble` / `marblein` device properties.

A successful CI run is still required before flashing. First boot testing is
not implied by successful compilation.


## Kernel-only packaging safety (builder v3)

This builder produces a boot-only AnyKernel package. It does not build, concatenate,
or package generic upstream DTBs/DTBOs, and its AnyKernel write path is restricted
to the `boot` partition. Existing `vendor_boot`, `vendor_kernel_boot`, `vendor_dlkm`,
`system_dlkm`, and `dtbo` partitions are intentionally left untouched.

The `lineage-24.0-marble` source preset remains a compatibility candidate and has
not been verified to boot on every crDroid 13 / Android 17 build. A successful CI
build is not proof of device compatibility. Do not flash a kernel image until its
source revision and configuration have been matched against the currently installed
ROM kernel.


### Safe build workflow

The workflow defaults to an image-only artifact. `create_flashable_zip` is opt-in and
should remain disabled until the selected kernel source revision has been compared
with the kernel shipped by the installed ROM. CI success and a valid AnyKernel archive
do not establish that the image is boot-compatible with a particular crDroid build.

The previous bootloop's cause has not been proven. The earlier archive contained a
concatenation of generic DTBs, but review of the AnyKernel3 staging path does not
prove that this file was actually written to a device partition. A mismatched kernel
image/configuration or the experimental diagnostic patch also remains possible.
