#!/usr/bin/env bash
#
# build-nautilus-typeahead-rpm
#
# Automatically builds GNOME Files with type-ahead
# functionality for Fedora Workstation/Silverblue.

URL="https://github.com/nelsonaloysio/fedora-nautilus-typeahead"

NAME="nautilus"
ARCH="$(rpm -E %_arch)"

USAGE="""Usage:
    $(basename $0) [-h] [-n NAUTILUS_VERSION] [-p PATCH_FILE] [-a ARCH_TYPE]
                   [-q --quiet] [-y|--assumeyes] [--noclean] [--prebuild]

Arguments:
    -h, --help
        Show this help message and exit.
    -n, --nautilus NAUTILUS_VERSION
        Specify Nautilus package version (X-Y.fcZZ). Default: latest available.
    -p, --patch-file PATCH_FILE
        Specify patch file. Must match Nautilus version.
    -a, --arch ARCH_TYPE
        Specify architecture type. Default: same as running system.
    -q, --quiet
        Suppress output of build commands.
    -y, --assumeyes
        Automatically answer yes to dnf install requirements.
    --noclean
        Do not clean build files and folders after building package.
    --prebuild
        Only prepare the spec and source files for building package."""

# Parse arguments.
while [[ $# -gt 0 ]]; do
    ARGS+=("$1")
    case $1 in
        -h|--help)
            echo "$USAGE"
            exit 0
            ;;
        -n|--nautilus)
            VERSION="$2"
            ARGS+=("$2")
            shift 2
            ;;
        -p|--patch-file)
            PATCH_FILE="$2"
            ARGS+=("$2")
            shift 2
            ;;
        -a|--arch)
            ARCH="$2"
            ARGS+=("$2")
            shift 2
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        -y|--assumeyes)
            YES=1
            shift
            ;;
        --noclean)
            NOCLEAN=1
            shift
            ;;
        --prebuild)
            PREBUILD=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done
set -- "${ARGS[@]}"

# Check system architecture, if unspecified.
if [ -z "$ARCH" ]; then
    ARCH="$(rpm -E %_arch)"
    if [ "$ARCH" != i686 -a "$ARCH" != x86_64 -a "$ARCH" != aarch64 ]; then
        echo -e "[!] Unsupported architecture type: $ARCH, must be 'x86_64', 'i686', or 'aarch64'."
        exit 1
    fi
fi

# Check if dnf is installed.
if [ -z "$(command -v dnf)" ]; then
    echo "[!] dnf package manager is required to build nautilus-typeahead with this script."
    exit 1
fi

# Select nautilus version.
if [ -z "$VERSION" ]; then
    VERSION="$(dnf list $NAME.$ARCH --showduplicates | tail -1 | awk '{print $2}')" &&
    echo -e "Auto-selected Nautilus package version: ${VERSION}..."
fi
RELEASE="$(echo $VERSION | cut -d- -f2 | cut -d. -f1)" &&
FEDORA="$(echo $VERSION | cut -d- -f2 | cut -d. -f2  | tr -d 'fc')" &&
VERSION="$(echo $VERSION | cut -f1 -d-)"

# Auto-select patch file.
if [ -z "$PATCH_FILE" ]; then
    PATCH_FILE="$(dirname "$(realpath "$0")")/patch/$VERSION/nautilus-restore-typeahead.patch"
fi

# Verify patch file exists.
if [ -f "$PATCH_FILE" ]; then
    echo "Using patch: '$PATCH_FILE'..."
else
    echo -e "[!] Unable to auto-select patch for this Nautilus version."
    exit 1
fi

# Set package full name.
PACKAGE="${NAME}-typeahead-${VERSION}-${RELEASE}.fc${FEDORA}.typeahead1.${ARCH}"
echo -e "\nBuild package: ${PACKAGE}..."

# Create RPM build directories.
echo -e "\nCreate RPM build directories..."
for directory in {BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
do
    [ ! -e ${HOME}/rpmbuild/$directory ] &&
    mkdir -p ${HOME}/rpmbuild/$directory
done

# Install requirements.
echo -e "\nInstall requirements..."
sudo dnf install $([ "$YES" = 1 ] && echo '-y') \
    appstream-devel \
    desktop-file-utils \
    'dnf-command(download)' \
    gcc \
    gi-docgen \
    git \
    gnome-autoar-devel \
    gnome-desktop4-devel \
    gstreamer1-plugins-base-devel \
    libadwaita-devel \
    libappstream-glib \
    libgexiv2-devel \
    libportal-gtk3-devel \
    libportal-gtk4-devel \
    meson \
    pkgconfig \
    rpm-build \
    rpmrebuild \
    wget \
    $( [ "$FEDORA" -lt 43 ] && echo "tracker-devel" ) \
    $( [ "$FEDORA" -ge 43 ] && echo "localsearch" ) \
    $( [ "$FEDORA" -ge 43 ] && echo "pkgconfig(tracker-sparql-3.0)" ) \
    $( [ "$FEDORA" -ge 43 ] && echo "gettext" ) \
    $( [ "$FEDORA" -ge 44 ] && echo "pkgconfig" ) \
    $( [ "$FEDORA" -ge 44 ] && echo "pkgconfig(blueprint-compiler)" ) \
    $( [ "$FEDORA" -ge 44 ] && echo "pkgconfig(glycin-gtk4-2)" )

# Prepare build directory.
cwd="$(pwd)"
mkdir -p build/${PACKAGE}
cd build/${PACKAGE}

# Download and extract RPM source files.
mkdir -p ${NAME}-${VERSION}
cd ${NAME}-${VERSION}
# if [ ! -f ${NAME}-${VERSION}-${RELEASE}.fc${FEDORA}.src.rpm ]; then
echo -e "\nDownload RPM source..."
dnf download --source ${NAME}-${VERSION}-${RELEASE}.fc${FEDORA}.${ARCH}
# fi
echo -e "\nExtract RPM files..."
rpm2cpio ${NAME}-${VERSION}-${RELEASE}.fc${FEDORA}.src.rpm |
cpio --extract -dvm

# Copy patch file to build directory.
cp "$PATCH_FILE" .

# Enable type-ahead functionality by default.
# https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=nautilus-typeahead
awk -i inplace \
    '/type-ahead-search/{c++;} c==1 && /true/{sub("true", "false"); c++;} 1' \
    nautilus-restore-typeahead.patch

# Edit package spec file.
sed -i 's/Name: .* nautilus/Name: nautilus-typeahead/' nautilus.spec
sed -i 's/%{name}/nautilus/g' nautilus.spec
sed -i 's/Source0/Patch: nautilus-restore-typeahead.patch\nSource0/' nautilus.spec
sed -i 's/Source0/Provides: nautilus = %{version}-%{release}\nSource0/' nautilus.spec
sed -i 's/Source0/Provides: nautilus%{?_isa} = %{version}-%{release}\nSource0/' nautilus.spec
sed -i 's/Source0/Obsoletes: nautilus < %{version}-%{release}\nSource0/' nautilus.spec
sed -i 's/Requires: .*nautilus/Requires: nautilus-typeahead/' nautilus.spec
sed -i 's/%package extensions/%package extensions\nProvides: nautilus-extensions = %{version}-%{release}/' nautilus.spec
sed -i 's/%package extensions/%package extensions\nProvides: nautilus-extensions%{?_isa} = %{version}-%{release}/' nautilus.spec
sed -i 's/%package extensions/%package extensions\nObsoletes: nautilus-extensions < %{version}-%{release}/' nautilus.spec
sed -i 's/%package devel/%package devel\nProvides: nautilus-devel = %{version}/' nautilus.spec
sed -i 's/^Release:\s*\(.*\)/Release: \1.typeahead1/' nautilus.spec
mv -f nautilus.spec ${HOME}/rpmbuild/SPECS/nautilus-typeahead.spec

# Copy source files to RPM build directory.
ls -1 | xargs -I {} cp -f {} ${HOME}/rpmbuild/SOURCES/
cd ../../..

# Exit after pre-build if specified.
if [ -n "$PREBUILD" ]; then
    echo -e "\nPre-build complete."
    echo "Spec and source files located in '${HOME}/rpmbuild/{SPECS,SOURCES}'."
    echo -e "\nRun the following command to build the RPM package:"
    echo "$ rpmbuild -ba ${HOME}/rpmbuild/SPECS/nautilus-typeahead.spec"
    exit 0
fi

# Build RPM files.
echo -e "\nBuild RPM file..."
rpmbuild -ba \
    $([ -n "$QUIET" ] && echo --quiet ) \
    $([ -n "$NOCLEAN" ] && echo --noclean ) \
    ${HOME}/rpmbuild/SPECS/nautilus-typeahead.spec

# Copy built files if successful, otherwise print error message and exit.
if [ -f "${HOME}/rpmbuild/RPMS/${ARCH}/${PACKAGE}.rpm" ]; then
    echo -e "Sucessfully built '${PACKAGE}.rpm'.\nCopying to build directory..."
    find "${HOME}/rpmbuild/RPMS" "${HOME}/rpmbuild/SRPMS" \
    \( -type f -name "${NAME}-typeahead-*${VERSION}-${RELEASE}.fc${FEDORA}.typeahead1.${ARCH}*.rpm" \
        -print -exec cp -t "build/${PACKAGE}" {} + \) \
    -o \
    \( -type f -name "${NAME}-typeahead-*${VERSION}-${RELEASE}.fc${FEDORA}.typeahead1.src.rpm" \
        -print -exec cp {} "build/${PACKAGE}" \; \)
    echo -e "\nRPM files copied to 'build/${PACKAGE}'."
else
    echo -e "\nFailed to build '${PACKAGE}.rpm'.\n
    Please submit an issue with the log of execution if desired to:
    > ${URL}/issues"
    exit 1
fi

# Clean up build files and folders.
if [ -z "$NOCLEAN" ]; then
    echo -e "\nCleaning up build files and folders..."
    find "${HOME}/rpmbuild" \
        \( -name '*nautilus-typeahead*' \
        -o -name 'default-terminal.patch' \
        -o -name 'nautilus-restore-typeahead.patch' \
        -o -name "nautilus-${VERSION}.tar.xz" \
        -o -name "nautilus-${VERSION}-${RELEASE}.fc${FEDORA}.src.rpm" \) \
        -print -exec rm -rf {} + &&
    # Remove source files from build directory.
    rm -rf "${cwd}/build/${PACKAGE}/nautilus-${VERSION}" &&
    echo "${cwd}/build/${PACKAGE}/nautilus-${VERSION}" &&
    # Delete rpmbuild directory if empty after cleanup.
    [ -z "$(find "${HOME}/rpmbuild" -mindepth 1 ! -type d -print -quit)" ] &&
    find "${HOME}/rpmbuild" -type d -empty -print -delete
fi

# Suggest cleaning up dependencies.
echo -e "\nInstalled dependencies may be removed with:"
echo "$ dnf history undo \$(dnf history list --reverse | tail -n1 | cut -f1 -d\|)"
