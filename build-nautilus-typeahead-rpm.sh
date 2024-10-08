#!/usr/bin/env bash

# build-nautilus-typeahead-rpm

# Automatically builds GNOME Files with type-ahead
# functionality for Fedora Workstation/Silverblue.

URL="https://github.com/nelsonaloysio/fedora-nautilus-typeahead"

NAME="nautilus"
ARCH="$(rpm -E %_arch)"
FLAGS="--prefix=/usr --buildtype=release -Ddocs=false -Dpackagekit=false"

USAGE="""Usage:
    $(basename $0) [-h] [-n NAUTILUS_VERSION] [[-p PATCH_URL] [-a ARCH_TYPE]
                   [--flags FLAGS] [--noclean] [--copr]

Arguments:
    -h, --help
        Show this help message and exit.
    -n, --nautilus NAUTILUS_VERSION
        Specify Nautilus package version (X-Y.fcZZ). Default: latest available.
    -p, --patch-url PATCH_URL
        Specify patch URL to obtain. Must match Nautilus version.
    -a, --arch ARCH_TYPE
        Specify architecture type. Default: same as running system.
    --flags FLAGS
        Specify Nautilus build flags. Replaces default flags.
        Default: '$FLAGS'.
    --noclean
        Do not clean build files and folders after building package.
    --copr
        Generate additional release files to be uploaded to Copr."""

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
        -p|--patch-url)
            URL_PATCH="$2"
            ARGS+=("$2")
            shift 2
            ;;
        -a|--arch)
            ARCH="$2"
            ARGS+=("$2")
            shift 2
            ;;
        --flags)
            FLAGS="$2"
            ARGS+=("$2")
            shift 2
            ;;
        --noclean)
            NOCLEAN=1
            shift
            ;;
        --copr)
            COPR=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done
set -- "${ARGS[@]}"

# Check system architecture.
[ "$ARCH" != i686 -a "$ARCH" != x86_64 ] &&
echo -e "[!] Unsupported architecture type: $ARCH, must be 'x86_64' or 'i686'." &&
exit 1

# Check if dnf is installed.
if [ -z "$(command -v dnf)" ]; then
    echo "[!] dnf package manager is required to build nautilus-typeahead with this script."
    exit 1
fi

# Select nautilus version.
if [ -z "$VERSION" ]; then
    VERSION="$(dnf list $NAME.$ARCH --showduplicates | tail -1 | awk '{print $2}')" &&
    RELEASE="$(echo $VERSION | cut -d- -f2 | cut -d. -f1)" &&
    FEDORA="$(echo $VERSION | cut -d- -f2 | cut -d. -f2  | tr -d 'fc')" &&
    VERSION="$(echo $VERSION | cut -f1 -d-)" &&
    echo -e "Auto-selected Nautilus package version: ${VERSION}-${RELEASE}.fc${FEDORA}..."
fi

# Select patch version.
if [ -z "$URL_PATCH" ]; then
    if [ "$VERSION" = 46.2 ]; then
        URL_PATCH="https://github.com/lubomir-brindza/nautilus-typeahead/archive/refs/tags/46.0-0ubuntu2ppa1.zip"
    elif [ "$VERSION" = 46.1 ]; then
        URL_PATCH="https://github.com/lubomir-brindza/nautilus-typeahead/archive/refs/tags/46-beta-0ubuntu3ppa2.tar.gz"
    elif [ "$VERSION" = 45.2.1 ]; then
        URL_PATCH="https://aur.archlinux.org/cgit/aur.git/snapshot/aur-524d92c42ea768e5e4ab965511287152ed885d22.tar.gz"
    else
        echo -e "[!] Unable to auto-select patch for this Nautilus version."
        exit 1
    fi
fi

# Set package identifier.
PACKAGE="${NAME}-typeahead-${VERSION}-${RELEASE}.fc${FEDORA}.${ARCH}"
echo -e "\nBuild package: ${PACKAGE}..."

# Create RPM build directories.
echo -e "\nCreate RPM build directories..."
for directory in {BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
do
    [ ! -d ${HOME}/rpmbuild/$directory ] &&
    [ ! -L ${HOME}/rpmbuild/$directory ] &&
    mkdir -p ${HOME}/rpmbuild/$directory
done

# Install requirements.
echo -e "\nInstall requirements..."
sudo dnf install \
    appstream-devel \
    desktop-file-utils \
    'dnf-command(download)' \
    gcc \
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
    tracker-devel \
    wget

# Create new folder and change directory.
echo -e "\nCreate new folder and change directory..."
rm -rf build/${PACKAGE} &&
mkdir -p build/${PACKAGE} &&
cd build/${PACKAGE}

# Download and extract nautilus.
echo -e "\nDownload and extract nautilus..."
wget "https://github.com/GNOME/nautilus/archive/refs/tags/${VERSION}.tar.gz" -O nautilus.tar.gz
tar -xzvf nautilus.tar.gz

# Download and extract nautilus-typeahead patch.
echo -e "\nDownload and extract nautilus-typeahead patch..."
case "$(basename $URL_PATCH | sed 's:.*\.::')" in
    zip)
        wget "$URL_PATCH" -O nautilus-restore-typeahead.zip
        unzip -d . -j \
              nautilus-restore-typeahead.zip \
              'nautilus-typeahead-46.0-0ubuntu2ppa1/nautilus-restore-typeahead.patch'
        ;;
    gz)
        wget "$URL_PATCH" -O nautilus-restore-typeahead.tar.gz
        tar -xzvf \
            nautilus-restore-typeahead.tar.gz \
            --strip 1 \
            '*nautilus-restore-typeahead.patch'
        ;;
esac

# Patch source code.
echo -e "\nPatch source code..."
patch \
    --directory="${NAME}-${VERSION}" \
    --strip=1 < \
    nautilus-restore-typeahead.patch

# Enable type-ahead functionality by default.
# https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=nautilus-typeahead
awk -i inplace \
    '/type-ahead-search/{c++;} c==1 && /true/{sub("true", "false"); c++;} 1' \
    ${NAME}-${VERSION}/data/org.gnome.nautilus.gschema.xml

# Change directory.
echo -e "\nChange directory..."
mkdir -p ${NAME}-${VERSION}/build &&
cd ${NAME}-${VERSION}/build

# Setup and build patched nautilus.
echo -e "\nSetup and build patched nautilus..."
meson setup $FLAGS
ninja

# Download RPM and extract files.
echo -e "\nDownload RPM and extract files..."
cd ../..
dnf download ${NAME}-${VERSION}-${RELEASE}.fc${FEDORA}.${ARCH}
rpm2cpio ${NAME}-${VERSION}-${RELEASE}.fc${FEDORA}.${ARCH}.rpm | cpio -idmv

# Rebuild and edit spec file.
echo -e "\nRebuild and edit spec file..."
rpmrebuild -s \
    ${HOME}/rpmbuild/SPECS/${PACKAGE}.spec \
    ${NAME}-${VERSION}-${RELEASE}.fc${FEDORA}.${ARCH}.rpm
sed -i 's/Name: .* nautilus/Name: nautilus-typeahead/' \
    ${HOME}/rpmbuild/SPECS/${PACKAGE}.spec
# sed -i "s/Provides: .* nautilus =/Obsoletes: .* nautilus =/" \
#     ${HOME}/rpmbuild/SPECS/${PACKAGE}.spec

# Check if files in build folder usr/share/locale exist.
echo -e "\n# Verify if missing files exist..."
grep 'MISSING: %lang' ${HOME}/rpmbuild/SPECS/${PACKAGE}.spec |
while read line; do
    lang=$(echo $line | cut -d\  -f3)
    file=$(echo $line | cut -d\  -f7 | tr -d \")
    if [ -f .${file} ]; then
        echo "Found: $file"
        sed -i \
            "s/# MISSING: $lang/$lang/" \
            ${HOME}/rpmbuild/SPECS/${PACKAGE}.spec
    fi
done

# Copy and replace modified files.
echo -e "\nCopy and replace modified files..."
cp -f \
    ${NAME}-${VERSION}/build/src/nautilus \
    usr/bin/nautilus
cp -f \
    ${NAME}-${VERSION}/data/org.gnome.nautilus.gschema.xml \
    usr/share/glib-2.0/schemas/org.gnome.nautilus.gschema.xml

# Create new folder and store build files.
mkdir -p ${HOME}/rpmbuild/BUILDROOT/${PACKAGE}
cp -r usr ${HOME}/rpmbuild/BUILDROOT/${PACKAGE}

# Build RPM package.
echo -e "\nBuild RPM file..."
rpmbuild \
    -ba ${HOME}/rpmbuild/SPECS/${PACKAGE}.spec \
    $([ -n "$NOCLEAN" -o -n "$COPR" ] && echo --noclean)
cd ../..

# Check if file was built.
[ ! -f "${HOME}/rpmbuild/RPMS/${ARCH}/${PACKAGE}.rpm" ] &&
echo -e """
Failed to build '${PACKAGE}.rpm'.\n
Please submit an issue with the log of execution if desired to:
> ${URL}/issues""" &&
exit 1 ||

# Copy RPM file to current directory.
echo -e "\nCopy RPM file to build directory..."
cp ${HOME}/rpmbuild/RPMS/x86_64/${PACKAGE}.rpm .

# Prepare release files for Copr.
if [ -n "$COPR" ]; then
    echo -e "\nGenerating release files..."
    mkdir -p copr
    cp -f ${HOME}/rpmbuild/SPECS/${PACKAGE}.spec copr/
    rm -f copr/${PACKAGE}.tar.gz
    tar -C ${HOME}/rpmbuild/BUILDROOT/${PACKAGE} \
        -czf copr/${PACKAGE}.tar.gz \
        .
    sed -i \
        "s:%files:%prep\n%setup -q -c\n%install\ncp -a %{_builddir}/%{name}-%{version}/* %{buildroot}/\n\n%files:" \
        copr/${PACKAGE}.spec
    sed -i \
        "s|URL:|Source0: ${URL}/releases/download/${VERSION}/${PACKAGE}.tar.gz\nURL:|" \
        copr/${PACKAGE}.spec
fi

# Clean build files.
if [ -z "$NOCLEAN" ]; then
    echo -e "\nRemove generated files..."
    rm -rf build/${PACKAGE}
    rm -df \
        $(find ${HOME}/rpmbuild -type f | grep ${NAME}-${VERSION}-${RELEASE}) \
        $(find ${HOME}/rpmbuild -type d | grep ${NAME}-${VERSION}-${RELEASE} | sort -r)
fi

# Print success message and suggest cleaning dependencies.
echo -e """
Successfully built '${PACKAGE}.rpm'.\n
Any installed dependencies may now be removed with:
$ dnf history undo \$(dnf history list --reverse | tail -n1 | cut -f1 -d\|)"""
