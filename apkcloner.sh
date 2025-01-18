#!/bin/bash

# Setup cleanup trap for Ctrl+C
cleanup() {
  echo -e "\nScript interrupted. Cleaning up..."
  # Restore original manifest if it exists
  if [ -f "${manifest_file}.original" ]; then
    mv "${manifest_file}.original" "$manifest_file"
  fi
  # Restore original strings.xml if it exists
  if [ -f "${strings_file}.original" ]; then
    mv "${strings_file}.original" "$strings_file"
  fi
  # Remove any intermediate files
  rm -f "${base_name}"_*_unsigned.apk "${base_name}"_*_aligned.apk
  exit 1
}
trap cleanup INT

# Check if at least 2 arguments are provided
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <input_file> <suffix1> [suffix2 ...]"
  exit 1
fi

# ReVanced setup
REVANCED_DIR="revanced"
if [ ! -d "$REVANCED_DIR" ]; then
  echo "Setting up ReVanced environment..."
  mkdir -p "$REVANCED_DIR"
  cd "$REVANCED_DIR"

  # Download latest ReVanced tools
  echo "Downloading ReVanced tools..."
  # CLI
  CLI_URL=$(curl -s https://api.github.com/repos/revanced/revanced-cli/releases/latest | grep -o 'https://.*all\.jar"' | sed 's/"$//')
  echo "Downloading CLI from: $CLI_URL"
  curl -L -o revanced-cli.jar "$CLI_URL"

  # Patches
  PATCHES_URL=$(curl -s https://api.github.com/repos/revanced/revanced-patches/releases/latest | grep -o 'https://.*\.rvp"' | sed 's/"$//')
  echo "Downloading patches from: $PATCHES_URL"
  curl -L -o revanced-patches.rvp "$PATCHES_URL"

  # Integrations
  INTEGRATIONS_URL=$(curl -s https://api.github.com/repos/revanced/revanced-integrations/releases/latest | grep -o 'https://.*\.apk"' | sed 's/"$//')
  echo "Downloading integrations from: $INTEGRATIONS_URL"
  curl -L -o revanced-integrations.apk "$INTEGRATIONS_URL"
  cd ..
fi

# Get input file and remove it from arguments
input_file="$1"
shift

# Get base name without extension
base_name="${input_file%.*}"
extension="${input_file##*.}"
decompile_dir="${base_name}_decompile_xml"

# Only perform conversion and decompilation if the directory doesn't exist
if [ ! -d "$decompile_dir" ]; then
  # If file is APKM, convert to APK first
  if [ "$extension" = "apkm" ]; then
    echo "Converting APKM to APK..."
    java -jar APKEditor.jar m -i "$input_file" -o "${base_name}.apk"
    input_file="${base_name}.apk"
  fi

  # After getting input file but before processing
  echo "Checking APK info..."
  java -jar APKEditor.jar info -i "$input_file"

  # Decompile the APK (without -t xml to get everything)
  echo "Decompiling APK..."
  java -jar APKEditor.jar d -i "$input_file"
else
  echo "Using existing decompiled files in ${decompile_dir}"
fi

# Check if AndroidManifest.xml exists
manifest_file="${decompile_dir}/AndroidManifest.xml"
if [ ! -f "$manifest_file" ]; then
  echo "Error: AndroidManifest.xml not found in decompiled files"
  exit 1
fi

# Get original package name
original_package=$(grep 'package="' "$manifest_file" | sed 's/.*package="\([^"]*\)".*/\1/')
if [ -z "$original_package" ]; then
  echo "Error: Could not find package name in AndroidManifest.xml"
  exit 1
fi

# Escape dots in package name for sed
escaped_package=$(echo "$original_package" | sed 's/\./\\./g')

# Check if debug.keystore exists, if not create it
if [ ! -f "debug.keystore" ]; then
  echo "Creating debug keystore..."
  keytool -genkey -v -keystore debug.keystore \
    -alias androiddebugkey \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" \
    -storepass android -keypass android
fi

# Process each package name
for suffix in "$@"; do
  new_package="${original_package}.${suffix}"
  escaped_package=$(echo "$original_package" | sed 's/\./\\./g')
  escaped_new_package=$(echo "$new_package" | sed 's/\./\\./g')
  echo "Creating APK for package: $new_package"

  # Create backup of original manifest
  cp "$manifest_file" "${manifest_file}.original"

  # Change package name in manifest
  sed -i '' "s/package=\"${escaped_package}\"/package=\"${escaped_new_package}\"/" "$manifest_file"

  # Remove permission declarations but keep uses-permission
  sed -i '' "/<permission /d" "$manifest_file"

  # Update custom permission references to use original package's permissions
  sed -i '' "s/android:name=\"${escaped_new_package}\.\([^\"]*\)\"/android:name=\"${escaped_package}.\1\"/g" "$manifest_file"
  sed -i '' "s/android:permission=\"${escaped_new_package}\.\([^\"]*\)\"/android:permission=\"${escaped_package}.\1\"/g" "$manifest_file"

  # Update all provider authorities to be unique
  sed -i '' "s/android:authorities=\"[^\"]*${escaped_package}[^\"]*\"/android:authorities=\"${escaped_new_package}\"/g" "$manifest_file"

  # Preserve original package name for application and component class paths
  sed -i '' "s/android:name=\"${escaped_new_package}\./android:name=\"${escaped_package}./g" "$manifest_file"

  # Change the app name in strings.xml
  strings_file="${decompile_dir}/res/values/strings.xml"
  if [ ! -f "$strings_file" ]; then
    strings_file="${decompile_dir}/resources/package_1/res/values/strings.xml"
  fi
  if [ -f "$strings_file" ]; then
    # Create backup of original strings.xml
    cp "$strings_file" "${strings_file}.original"
    # Change app_name string to include suffix in parentheses
    sed -i '' 's/\(<string name="app_name">[^<]*\)<\/string>/\1 ('"$suffix"')<\/string>/g' "$strings_file"
  fi

  # Build new APK with specified output name
  java -jar APKEditor.jar b -framework-version 34 -i "$decompile_dir" -o "${base_name}_${suffix}_unsigned.apk"

  # Zipalign the APK
  echo "Zipaligning APK..."
  zipalign -v -p 4 "${base_name}_${suffix}_unsigned.apk" "${base_name}_${suffix}_aligned.apk"

  # Check if package is supported by ReVanced and apply patches if supported
  final_apk="${base_name}_${suffix}.apk"
  if [ -f "revanced/revanced-cli.jar" ]; then
    echo "Checking if package $original_package is supported by ReVanced..."
    # List available patches and filter for app-specific ones
    available_patches=$(java -jar "revanced/revanced-cli.jar" list-patches -p "revanced/revanced-patches.rvp" -f "$original_package")
    if [ ! -z "$available_patches" ]; then
      echo "Found app-specific patches for $original_package:"
      echo "$available_patches"
      echo "Applying patches..."

      # Extract patch names and create enable arguments
      declare -a enable_args=()
      echo "Will apply the following patches:"
      current_name=""
      is_enabled=false

      while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*Name:[[:space:]]*(.*) ]]; then
          current_name="${BASH_REMATCH[1]}"
          is_enabled=false
        elif [[ $line =~ ^[[:space:]]*Enabled:[[:space:]]*true ]]; then
          is_enabled=true
          if [ ! -z "$current_name" ]; then
            echo "  - $current_name"
            enable_args+=("--enable" "$current_name")
          fi
        fi
      done <<<"$available_patches"

      if [ ${#enable_args[@]} -eq 0 ]; then
        echo "No enabled patches found for $original_package"
        return
      fi
      echo

      # Create patched version with all app-specific patches
      echo "Running patch command..."
      java -jar "revanced/revanced-cli.jar" \
        patch \
        -p "revanced/revanced-patches.rvp" \
        -o "${base_name}_${suffix}_revanced.apk" \
        --exclusive \
        "${enable_args[@]}" \
        "${base_name}_${suffix}_aligned.apk"

      if [ -f "${base_name}_${suffix}_revanced.apk" ]; then
        echo "Successfully patched APK with ReVanced"
        final_apk="${base_name}_${suffix}_revanced.apk"
      else
        echo "Failed to patch APK with ReVanced, will use unpatched version"
      fi
    else
      echo "No app-specific patches found for $original_package"
    fi
  fi

  # Sign the final APK (either patched or unpatched)
  echo "Signing final APK..."
  apksigner sign --ks debug.keystore \
    --ks-key-alias androiddebugkey \
    --ks-pass pass:android \
    --key-pass pass:android \
    --v1-signing-enabled true \
    --v2-signing-enabled true \
    --v3-signing-enabled true \
    --v4-signing-enabled true \
    --out "${base_name}_${suffix}_signed.apk" \
    "$final_apk"

  # Clean up intermediate files
  rm -f "${base_name}_${suffix}_unsigned.apk" "${base_name}_${suffix}_aligned.apk" \
    "${base_name}_${suffix}_revanced.apk" "$final_apk"
  # Clean up ReVanced temporary directories
  rm -rf "${base_name}_${suffix}_revanced-temporary-files"

  # Verify the signature
  echo "Verifying APK signature..."
  apksigner verify --verbose "${base_name}_${suffix}_signed.apk"

  # Restore original manifest
  mv "${manifest_file}.original" "$manifest_file"

  # Restore original strings.xml
  if [ -f "${strings_file}.original" ]; then
    mv "${strings_file}.original" "$strings_file"
  fi
done

echo "All APKs created successfully"
