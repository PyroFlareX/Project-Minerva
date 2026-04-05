FROM ghcr.io/cross-rs/aarch64-unknown-linux-musl:edge

# Pull fontconfig (and its deps) from Alpine's aarch64 repo and install them
# into the musl cross-compilation sysroot so pkg-config can find them at
# build time.  The binary still dlopen()s the real fontconfig on the device.

ENV ALPINE_REPO=https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64
ENV SYSROOT=/usr/aarch64-linux-musl

RUN apt-get update -q && apt-get install -yq --no-install-recommends wget ca-certificates

# Extract each APK (Alpine tar.gz) into the sysroot.
# --warning=no-unknown-keyword silences the APK signature header noise.
RUN for pkg in \
      expat-2.6.4-r0 \
      expat-dev-2.6.4-r0 \
      libpng-1.6.44-r0 \
      libpng-dev-1.6.44-r0 \
      bzip2-libs-1.0.8-r6 \
      bzip2-dev-1.0.8-r6 \
      brotli-libs-1.1.0-r2 \
      freetype-2.13.3-r0 \
      freetype-dev-2.13.3-r0 \
      fontconfig-2.15.0-r1 \
      fontconfig-dev-2.15.0-r1 \
    ; do \
      wget -q "${ALPINE_REPO}/${pkg}.apk" -O /tmp/pkg.apk && \
      tar --warning=no-unknown-keyword -xzf /tmp/pkg.apk -C "${SYSROOT}" \
          --exclude='.PKGINFO' --exclude='.SIGN.*' 2>/dev/null || true; \
    done && \
    rm -f /tmp/pkg.apk

# Tell pkg-config where to find the target .pc files
ENV PKG_CONFIG_ALLOW_CROSS=1
ENV PKG_CONFIG_SYSROOT_DIR=${SYSROOT}
ENV PKG_CONFIG_PATH=${SYSROOT}/usr/lib/pkgconfig:${SYSROOT}/usr/share/pkgconfig
