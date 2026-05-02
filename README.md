# PercApps

a container project for all my standalone apps for percussa ssp/xmx.

this is a release tool, basically collect together various projects, allow to be built
then combine with a setup that combines together and provider user with instructions on how to install etc.

note:
the XMX and SSP are different binary formats, and also have different hardware layouts,
so binaries and configurations cannot generally.

resources fall into therefore 3 categories

ssp specific
xmx specitic
common



sub projects, linked as sub modules into external

PercCmd
Dependancies : None
a small utility application, allow a user to select standalone at boot time via buttons.
it falls back safely to the default SYNTHOR app

Plugins
Dependancies : None
all my plugins for use in Synthor or TraxHost

TraxHost
a standalone host for plugins, by default we configure for Trax plugin
Dependancies : PercCmd, Plugins

Er301
a standalone app emulating the er301, we are only interested in the percussa target
Dependancies : PercCmd



# Using

### 1. Clone with all submodules

```bash
git submodule update --init --recursive
```

### 2. Configure

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
```

### 3. Build

```bash
# Everything (both platforms)
cmake --build build

# Single platform
cmake --build build --target ssp
cmake --build build --target xmx
```

### Build targets

| Target | Description |
|---|---|
| `ssp` | All subprojects for SSP |
| `xmx` | All subprojects for XMX |
| `PercCmd_SSP` / `PercCmd_XMX` | PercCmd only |
| `Plugins_SSP` / `Plugins_XMX` | Plugins only |
| `TraxHost_SSP` / `TraxHost_XMX` | TraxHost only |
| `er301_SSP` / `er301_XMX` | er-301 all steps |
| `er301_fftw_SSP` / `er301_fftw_XMX` | er-301 FFTW dependency only |
| `er301_percussa_SSP` / `er301_percussa_XMX` | er-301 percussa step only |
| `er301_core_SSP` / `er301_core_XMX` | er-301 core step only |

Individual targets are useful for retrying a failed step without rebuilding everything:

```bash
cmake --build build --target er301_percussa_SSP
```