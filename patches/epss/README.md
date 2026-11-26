# Qualcomm EPSS LUT diagnostics patch

`0001-epss-lut-read-only-diagnostics.patch` adds a read-only sysfs attribute to
`drivers/cpufreq/qcom-cpufreq-hw-debug.c`:

`/sys/kernel/qcom-cpufreq-hw/print_cpufreq_lut`

The attribute reads the existing EPSS frequency LUT (`0x100`) and voltage LUT
(`0x200`) for each frequency domain. It reports the raw frequency word and the
12-bit voltage code used by the existing Qualcomm driver when constructing OPPs.

It does **not** write to EPSS registers, change voltage/frequency, modify CPRh,
or alter firmware. This is diagnostic only; it is not a CPU undervolting feature.

Enable it in GitHub Actions with the `Enable read-only EPSS LUT diagnostics`
workflow input. The option defaults to `false`. The patch is intended for the
Marble `lineage-24.0` source layout and will fail before compilation if its
context does not match the selected kernel source.
