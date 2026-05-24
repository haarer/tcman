# tcman - Toolchain Manager

Manage cross-compilation toolchains from github.com/haarer/toolchain68k

## Features

- List installed toolchains in `/opt`
- Browse available toolchains from GitHub releases (including release tags)
- Download and install toolchains (optionally pinning to a specific release tag)
- Remove installed toolchains
- Interactive menu or command-line usage

## Supported Toolchains

From [haarer/toolchain68k](https://github.com/haarer/toolchain68k):

| Target | Description |
|--------|-------------|
| `m68k-elf` | Motorola 68000 / CPU32 / ColdFire |
| `arm-none-eabi` | ARM Cortex-M (STM32, etc.) |
| `avr` | Atmel AVR (Arduino, etc.) |

Toolchains include: GCC, Binutils, GDB, and Newlib.

## Installation

Copy to somewhere in your PATH:
```bash
sudo cp tcman.sh /usr/local/bin/tcman
sudo chmod +x /usr/local/bin/tcman
```

## Directory Structure

Toolchains are installed as subdirectories in `/opt`, named according to the `name` field in their `package.json`:

```
/opt/
├── toolchain-m68k-elf-current/
│   ├── bin/
│   ├── include/
│   ├── lib/
│   ├── m68k-elf/
│   ├── share/
│   └── package.json
├── toolchain-arm-none-eabi-current/
└── toolchain-avr-current/
```

Only one version per target can be installed at a time. Installing a newer version replaces the existing one.

## Usage

### Interactive Mode

```bash
tcman
```

### Command Line

```bash
# List installed toolchains
tcman list

# List available from GitHub (shows release tags)
tcman available

# Install a toolchain (requires root)
sudo tcman install m68k-elf
sudo tcman install arm-none-eabi
sudo tcman install avr

# Install a specific release tag (requires root)
sudo tcman install m68k-elf gcc152-update1

# Remove a toolchain (requires root)
sudo tcman remove m68k-elf
```

## Using Toolchains

Add the `bin` directory to your PATH:

```bash
export PATH=$PATH:/opt/toolchain-m68k-elf-current/bin
```

Or use directly:

```bash
/opt/toolchain-m68k-elf-current/bin/m68k-elf-gcc -o firmware.elf main.c
```

## Requirements

- bash
- curl or wget
- tar
- gzip
- root (for install/remove to /opt)
