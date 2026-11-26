# Builder v4 — safe external Device Tree checkout

## What changed

- External Marble device-tree source is cloned to
  `external/marble-devicetrees`, outside the kernel source tree. The kernel repo
  already owns `arch/arm64/boot/dts/vendor`; the external repo is validated as a
  separate source input and is not overlaid into the kernel tree.
- A pre-build validation checks the Marble/SM7475 overlay sources and Makefile.
- The kernel build target is `Image` (plus modules only when `build_scope=full`).
  It no longer invokes generic `dtbs` or concatenates every upstream DTB/DTBO.
- The release directory is cleared of stale DTB/DTBO payloads before building.
- AnyKernel packaging copies only `Image`.
- The custom AnyKernel `write_boot()` writes only the `boot` partition; it does
  not call the generic helper that can write secondary partitions.
- The flashable-ZIP audit rejects DTB/DTBO and secondary-partition payloads, and
  checks for the boot-only guard in `anykernel.sh`.
- Creating a flashable ZIP is now an explicit workflow opt-in and defaults OFF.
  The default artifact contains `Image` and build logs only.
- The optional EPSS LUT diagnostic patch also defaults OFF; keep it OFF for the
  next build while investigating the previous bootloop.

## Important compatibility note

The `lineage-24.0-marble` preset is still labelled as a compatibility candidate,
not as proven boot-compatible with every crDroid 13 / Android 17 build. A
successful CI build is not a device boot test. Keep `create_flashable_zip` OFF
until the exact installed ROM kernel source/revision has been matched.

## Previous bootloop

The prior artifact contained an incorrectly concatenated generic DTB file.
However, reviewing the bundled AnyKernel3 flow does not prove that the file was
actually written to a device partition. Therefore the bootloop cause remains
unconfirmed; a mismatched kernel Image/configuration and the experimental EPSS
patch are also possible. This release removes the DTB packaging path and makes
all non-boot partition writes unavailable in the custom AnyKernel script.

## Local checks performed

- `bash -n` on all shell scripts and `ak3/anykernel.sh`.
- Workflow YAML parsed with PyYAML.
- Preset resolver confirmed the external DT repository target path and status.
- Checkout target routing keeps `external/*` inputs outside `kernel-source` and
  preserves the kernel tree's existing `arch/arm64/boot/dts/vendor` directory.
- Marble Device Tree validator passed against the user-provided DT source archive.
- Mock AnyKernel package test passed without any DTB/DTBO or secondary partition files.
- Negative audit test rejected a ZIP after a `dtb` file was injected.

No full kernel build was run in this environment, and no new kernel was flashed or
boot-tested on the phone.
