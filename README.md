# PercApps

A container project that builds and packages all standalone apps for the Percussa SSP and XMX.

The SSP and XMX use different binary formats and hardware layouts, so each platform gets its own image. Resources are split accordingly: `resources/common`, `resources/ssp`, and `resources/xmx`.

### Subprojects

| Project | Dependencies | Description |
|---|---|---|
| PercCmd | — | Boot-time launcher; lets user select a standalone app via buttons, falls back to SYNTHOR |
| Plugins | — | All plugins for use in Synthor or TraxHost |
| TraxHost | PercCmd, Plugins | Standalone plugin host, configured for the Trax plugin by default |
| er-301 | PercCmd | Port of the ER-301 Sound Computer to Percussa hardware |

---

## Using

### 1. Clone with all submodules

```bash
git submodule update --init --recursive
```

### 2. Configure

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
```

This also fetches git tags from the er-301 remote so the firmware version string is embedded in the binary.

### 3. Build

```bash
# Everything (both platforms)
cmake --build build

# Single platform
cmake --build build --target ssp
cmake --build build --target xmx
```

### 4. Collect image

Gathers all build artifacts for a platform into `build/image/ssp/` or `build/image/xmx/`, strips all ELF binaries, copies resources, and produces a zip file. The full path to the zip is printed at the end of the step.

```bash
cmake --build build --target image_SSP
cmake --build build --target image_XMX
```

Output:
```
==> Image ready: /path/to/build/tbapps_ssp.zip
==> Image ready: /path/to/build/tbapps_xmx.zip
```

### 5. Sanity check

Verifies every ELF binary in the image is the correct architecture (SSP = ARM 32-bit, XMX = AArch64).

```bash
cmake --build build --target check_SSP
cmake --build build --target check_XMX
```

### Image layout

```
build/image/ssp/          build/image/xmx/
  PercCmd                   PercCmd
  TraxHost                  TraxHost
  plugins/                  plugins/
    *.so                      *.so
  er301/                    er301/
    er301.elf                 er301.elf
    rear/                     rear/
      core-*.pkg                core-*.pkg
    xroot/                    xroot/
  <resources/common>        <resources/common>
  <resources/ssp>           <resources/xmx>
```

### All build targets

| Target | Description |
|---|---|
| `ssp` | Build all subprojects for SSP |
| `xmx` | Build all subprojects for XMX |
| `PercCmd_SSP` / `_XMX` | Build PercCmd |
| `Plugins_SSP` / `_XMX` | Build Plugins |
| `TraxHost_SSP` / `_XMX` | Build TraxHost |
| `er301_SSP` / `_XMX` | Build er-301 (all steps) |
| `er301_fftw_SSP` / `_XMX` | er-301: cross-build FFTW only |
| `er301_percussa_SSP` / `_XMX` | er-301: make percussa only |
| `er301_core_SSP` / `_XMX` | er-301: make core only |
| `image_SSP` / `image_XMX` | Collect and strip image |
| `check_SSP` / `check_XMX` | Verify image architecture |

---

## Troubleshooting

### Submodules are empty after clone

Run `git submodule update --init --recursive` from the repo root. If nested submodules (e.g. inside Plugins or er-301) are still empty, check `.gitmodules` in that subproject.

### A build step fails partway through

Each subproject step is a named target. Re-run just the failing step rather than the full build:

```bash
cmake --build build --target er301_percussa_SSP
cmake --build build --target Plugins_XMX
```

Build logs for cmake-based projects (PercCmd, Plugins, TraxHost) are written to `build/logs/`:

```
build/logs/TraxHost_SSP-build-out.log
build/logs/TraxHost_SSP-configure-out.log
```

er-301 build output goes directly to the terminal.

### er-301 firmware version is empty

The version string is derived from a git tag matching `v*.*.*-*` in the er-301 submodule. If it is missing, fetch tags:

```bash
git -C external/er-301 fetch --tags
git -C external/er-301 describe --match "v*.*.*-*" --tags --abbrev=0
```

Then re-run `cmake -B build` to pick up the tag.

### er-301 build output is going into external/

The `build_dir` make variable must be passed to the er-301 make commands. This is handled automatically by CMakeLists.txt — if you are invoking make manually, pass it explicitly:

```bash
make percussa TOOLCHAIN_FILE=scripts/toolchains/ssp.mk build_dir=/path/to/build/er301_SSP
```

### Architecture check fails

`cmake --build build --target check_SSP` will print the `file` output for any mismatched ELF. Common causes:
- A host-native `.so` accidentally included (e.g. a cmake test artifact)
- Wrong toolchain used for a subproject

### Strip tool not found

The strip tools default to Homebrew paths. Override at configure time if yours differ:

```bash
cmake -B build \
  -DSTRIP_SSP=/path/to/arm-linux-gnueabihf-strip \
  -DSTRIP_XMX=/path/to/aarch64-elf-strip
```

---

## Dev Notes

### How the CMake file works

`CMakeLists.txt` is a pure orchestration file — it has no compiler itself (`project(PercApps NONE)`) and delegates all compilation to the subprojects via their own toolchain files.

#### cmake-based subprojects (PercCmd, Plugins, TraxHost)

Each is registered with `ExternalProject_Add`, which runs cmake configure and build in an isolated binary directory. The subproject's own toolchain file is passed via `-DCMAKE_TOOLCHAIN_FILE`.

A custom `build_announce` step (inserted between configure and build) prints the log file path to the terminal before the build starts, since `LOG_BUILD ON` captures output silently. All logs land in `build/logs/`.

TraxHost depends on PercCmd and Plugins via `ExternalProject_Add_StepDependencies`, so the dependency order is enforced within each platform.

#### er-301 (Makefile-based)

er-301 uses its own Make build system. The CMake file drives it with three sequential `add_custom_target` steps per platform:

1. **`er301_fftw_<PLATFORM>`** — runs `scripts/build-fftw-cross.sh` with `DESTDIR` and `BUILD_DIR` redirected into the cmake build tree so nothing lands in `external/`
2. **`er301_percussa_<PLATFORM>`** — runs `make percussa` with `build_dir`, `FFTW_STAGE_ROOT`, and `FIRMWARE_VERSION` passed as make variables
3. **`er301_core_<PLATFORM>`** — runs `make core` with `build_dir`

The `build_dir` override is the key mechanism that redirects all er-301 output from `external/er-301/testing/` into `build/er301_SSP/` or `build/er301_XMX/`.

The er-301 firmware version is resolved at cmake configure time by running `git fetch --tags` and `git describe` in the submodule, then passed to make as `FIRMWARE_VERSION`.

#### Image collection

`image_<PLATFORM>` is a custom target that copies artifacts into `build/image/<platform>/`. Plugins use a cmake `-P` script (`cmake/collect_plugins.cmake`) to glob all `.so` files at build time, since their paths are deeply nested under JUCE artefact directories. The er-301 core `.pkg` is similarly globbed (`cmake/collect_files.cmake`) to avoid hard-coding the version in the path. Resources are copied last — common first, then platform-specific — so platform files can overlay common ones.

After collection, `cmake/strip_image.cmake` runs `file` on every file in the image, strips anything identified as ELF, and reports a count. Strip tool paths are cmake CACHE variables (`STRIP_SSP`, `STRIP_XMX`) so they can be overridden.

The image directory is then zipped into `build/tbapps_ssp.zip` / `build/tbapps_xmx.zip` using `cmake -E chdir` to run the tar from inside the image root, ensuring no `ssp/` or `xmx/` prefix appears inside the archive. The full zip path is echoed to the terminal at the end of the step.

#### Architecture check

`check_<PLATFORM>` runs `cmake/check_arch.cmake` against the collected image, using `file` to inspect each ELF and asserting the expected bit-width and architecture string (SSP: `ELF 32-bit` + `ARM`; XMX: `ELF 64-bit` + `aarch64`). Non-ELF files are skipped. The target fails if any ELF does not match.
