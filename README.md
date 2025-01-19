# apk-cloner

Utilizes [APKEditor](https://github.com/REAndroid/APKEditor) to clone Android APK files with unique package names and optional ReVanced patching support.

## Features

- Clone APK/APKM files with multiple package name suffixes
- Automatically downloads the latest APKEditor from GitHub
- Automatically handles package name changes in AndroidManifest.xml
- Updates app name to include suffix for easy identification
- Preserves original package permissions and component paths
- Supports ReVanced patching for compatible apps
  - Auto-updates ReVanced tools to latest versions
  - Applies all available app-specific patches
- Handles zipalign and APK signing
- Cleans up temporary files automatically
- Organizes all output files in a dedicated directory

## Requirements

- Java Runtime Environment (JRE)
- Android SDK Build Tools (for `zipalign` and `apksigner`)
- `curl` for downloading tools
- Internet connection for first run (to download APKEditor and ReVanced tools)

The script will automatically:

- Download the latest APKEditor.jar on first run
- Create a debug keystore if one doesn't exist
- Download and update ReVanced tools if enabled (can be disabled with -n flag)
- Create an `output` directory for all generated files

## Usage

```bash
./apkcloner.sh [-n|--no-revanced] <input_file> <suffix1> [suffix2 ...]
```

Options:

- `-n, --no-revanced`: Disable ReVanced support and skip downloading ReVanced tools

### Examples

Clone a single APK:

```bash
./apkcloner.sh input.apk work
# Creates output/input_work_signed.apk
```

Create multiple clones:

```bash
./apkcloner.sh input.apk personal work family
# Creates:
# - output/input_personal_signed.apk
# - output/input_work_signed.apk
# - output/input_family_signed.apk
```

Clone without ReVanced support:

```bash
./apkcloner.sh -n input.apk work
# Creates output/input_work_signed.apk without ReVanced patching
```

### ReVanced Support

The script automatically checks if the input APK is supported by ReVanced. If supported, it will:

1. Download ReVanced tools on first run
2. Apply all available app-specific patches
3. Sign the patched APK

## Output Files

All generated files are placed in the `output` directory:

- `output/<base_name>_<suffix>_signed.apk`: The final signed APK ready for installation
- `output/<base_name>_decompile_xml`: Temporary directory for decompiled resources

## Notes

- The script verifies required tools (`apksigner` and `zipalign`) before starting
- Original APK remains unchanged
- Temporary files are cleaned up automatically
- Debug keystore is created automatically if needed
- All generated files are organized in the `output` directory
