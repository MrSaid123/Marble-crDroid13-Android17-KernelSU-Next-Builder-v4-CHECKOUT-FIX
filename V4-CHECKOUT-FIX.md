# Builder v4 — additional checkout path fix

The v3 workflow attempted to clone the separate LineageOS Device Tree repository
straight into `kernel-source/arch/arm64/boot/dts/vendor`. The supplied Actions log
shows that destination already exists in the kernel checkout, so `git clone`
failed before the Device Tree validation step.

v4 fixes this by checking the repository out to `external/marble-devicetrees`,
outside `kernel-source`. The Device Tree validator reads files from that path.
The external tree is used for source validation only; this Image-only build does
not overlay it into the kernel tree, compile its DTB/DTBO files, or package them.
The modules repository remains checked out at `kernel-source/modules`.

## Checks performed

- Bash syntax checks for scripts and AnyKernel installer.
- GitHub Actions YAML parses successfully.
- `lineage-24.0-marble` resolver emits `external/marble-devicetrees` as the DT target.
- Marble Device Tree validator passes against the provided LineageOS DT source archive.
- Regression test simulating an existing `kernel-source/arch/arm64/boot/dts/vendor`
  directory confirms the new external checkout path does not collide with or alter it.
- No stale workflow/config/docs reference routes the DT checkout into the kernel's vendor directory.

No kernel build or device flash was performed as part of this fix.
