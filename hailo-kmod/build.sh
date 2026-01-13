#!/bin/bash

set -o errexit
set -o pipefail

# Function to fetch kernel headers from balena
fetch_headers() {
    local slug="$1"
    local version="$2"
    local header_path="/usr/src/kernel-headers"

    echo "[BUILD] Fetching kernel headers for ${slug} version ${version}"

    mkdir -p "${header_path}"

    # Determine if this is an ESR version
    local url_base="https://files.balena-cloud.com"
    # ESR version pattern: year.month.patch format (e.g., 2024.10.0)
    if [[ "${version}" =~ ^[1-3][0-9]{3}\.(1|01|4|04|7|07|10)\.[0-9]*(.dev|.prod)?$ ]]; then
        # ESR version format
        local image_path="esr-images"
    else
        # Standard version format
        local image_path="images"
    fi

    # URL encode the version string (replace + with %2B)
    local encoded_version=$(echo "${version}" | sed 's/+/%2B/g')
    local url="${url_base}/${image_path}/${slug}/${encoded_version}/kernel_modules_headers.tar.gz"

    echo "[BUILD] Downloading from: ${url}"

    # Download headers
    if ! wget -q -O /tmp/headers.tar.gz "${url}"; then
        echo "[BUILD] ERROR: Failed to download kernel headers"
        exit 1
    fi

    # Calculate strip depth based on .config file location
    echo "[BUILD] Extracting kernel headers..."
    local strip_depth=$(tar -tzf /tmp/headers.tar.gz | grep "/\.config$" | tr -dc / | wc -c)

    # Extract headers with calculated strip depth
    tar -xzf /tmp/headers.tar.gz -C "${header_path}" --strip-components="${strip_depth}"

    # Clean up download
    rm -f /tmp/headers.tar.gz

    echo "[BUILD] Kernel headers extracted to ${header_path}"
}

# Function to build the Hailo PCIe module
build_module() {
    local src_dir="$1"
    local out_dir="$2"
    local kernel_dir="/usr/src/kernel-headers"

    echo "[BUILD] Building Hailo PCIe module from ${src_dir}"

    # Verify source directory structure
    if [[ ! -f "${src_dir}/Makefile" ]]; then
        echo "[BUILD] ERROR: Makefile not found in ${src_dir}"
        exit 1
    fi

    if [[ ! -f "${src_dir}/Kbuild" ]]; then
        echo "[BUILD] ERROR: Kbuild not found in ${src_dir}"
        exit 1
    fi

    # Prepare kernel build environment
    echo "[BUILD] Preparing kernel build environment..."
    make -C "${kernel_dir}" modules_prepare

    # Build the module using the Hailo Makefile
    echo "[BUILD] Compiling kernel module..."
    make -C "${kernel_dir}" M="${src_dir}" modules

    # Copy the compiled module to output directory
    echo "[BUILD] Copying compiled module to ${out_dir}"
    find "${src_dir}" -name "hailo_pci.ko" -exec cp {} "${out_dir}/" \;

    # Verify the module was built
    if [[ ! -f "${out_dir}/hailo_pci.ko" ]]; then
        echo "[BUILD] ERROR: hailo_pci.ko was not created"
        exit 1
    fi

    echo "[BUILD] Module built successfully: ${out_dir}/hailo_pci.ko"

    # Clean up build artifacts
    make -C "${kernel_dir}" M="${src_dir}" clean || true

    # Clean up kernel headers to reduce image size
    echo "[BUILD] Cleaning up kernel headers..."
    rm -rf "${kernel_dir}"
}

# Main build process
main() {
    local src_dir=""
    local out_dir=""
    local os_version=""
    local slug=""

    # Parse command line arguments
    while getopts "i:o:v:s:" opt; do
        case ${opt} in
            i)
                src_dir="${OPTARG}"
                ;;
            o)
                out_dir="${OPTARG}"
                ;;
            v)
                os_version="${OPTARG}"
                ;;
            s)
                slug="${OPTARG}"
                ;;
            *)
                echo "Usage: $0 -i <source_dir> -o <output_dir> -v <os_version> -s <slug>"
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "${src_dir}" || -z "${out_dir}" || -z "${os_version}" || -z "${slug}" ]]; then
        echo "[BUILD] ERROR: Missing required parameters"
        echo "Usage: $0 -i <source_dir> -o <output_dir> -v <os_version> -s <slug>"
        exit 1
    fi

    echo "[BUILD] ========================================"
    echo "[BUILD] Hailo PCIe Kernel Module Build"
    echo "[BUILD] ========================================"
    echo "[BUILD] Source directory: ${src_dir}"
    echo "[BUILD] Output directory: ${out_dir}"
    echo "[BUILD] OS version: ${os_version}"
    echo "[BUILD] Device slug: ${slug}"
    echo "[BUILD] ========================================"

    # Create output directory
    mkdir -p "${out_dir}"

    # Fetch kernel headers
    fetch_headers "${slug}" "${os_version}"

    # Build the module
    build_module "${src_dir}" "${out_dir}"

    echo "[BUILD] Build process completed successfully"
}

# Execute main function
main "$@"
