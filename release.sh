#!/usr/bin/env bash
set -e
DIR="$PWD"
BUILDDIR="$DIR/build"
WORKDIR="$BUILDDIR/pkgbuild"
CHROOT="$BUILDDIR/chroot"

export SRCDEST="$BUILDDIR/src"

pkg="$1"
if [[ ! -f "$pkg/PKGBUILD" ]]; then
    echo "Usage: $0 <pkgbase>"
    exit 1
fi

cd "$pkg"
makepkg --printsrcinfo > .SRCINFO

if output=$(git status --porcelain -- .) && [ -n "$output" ]; then
    echo "Working directory of '$pkg' not clean:"
    echo "$output"
    exit 1
fi

pkgver=$(grep pkgver .SRCINFO | awk '{print $3}')
echo "Building '$pkg' $pkgver..."
namcap PKGBUILD

read -p "Continue building (y/n)? " choice
[[ "${choice,,}" == "y" ]]

cd "$DIR"
branch="split/$pkg"
tag="$pkg/$pkgver"

# Prepare package release
git branch -D "$branch" &> /dev/null || :
git subtree split --prefix "$pkg" -b "$branch"
git tag -s "$tag" "$branch"
git branch -D "$branch" &> /dev/null

git worktree remove -f "$WORKDIR" 2> /dev/null || :
git worktree add -f "$WORKDIR" "tags/$pkg/$pkgver"
cd "$WORKDIR"

# Setup chroot if it does not exist yet
if [[ ! -d "$CHROOT" ]]; then
    mkdir -p "$CHROOT"
    mkarchroot "$CHROOT/root" base-devel
fi

# Build package
sudo --preserve-env=SRCDEST makechrootpkg -cur "$CHROOT"

# Check package with namcap
packages=$(makepkg --packagelist)
xargs namcap <<< "$packages"

read -p "Continue uploading (y/n)? " choice
[[ "${choice,,}" == "y" ]]

# Sign packages
xargs -L1 gpg --detach-sign --no-armor <<< "$packages"

# Upload tag and push to AUR
git push origin "$tag"
git push "aur@aur.archlinux.org:$pkg.git" "$tag":master

# Create GitHub release
assets=$(awk '{printf "-a %s -a %s.sig", $0, $0}' <<< "$packages")
hub release create -m "$pkg $pkgver" $assets "$tag"

git worktree remove -f "$WORKDIR" 2> /dev/null || :