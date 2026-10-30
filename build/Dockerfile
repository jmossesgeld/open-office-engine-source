# The engine toolchain: Ubuntu + emsdk (allotropia's emscripten 3.1.65) + Qt 5.15.2 for WebAssembly.
# LibreOffice core itself is built by in-container.sh into a named volume, not into this image.
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf automake bison build-essential bzip2 ca-certificates ccache cmake curl file flex \
      gettext git gperf libcups2-dev libexpat1-dev libfontconfig-dev libfreetype-dev libkrb5-dev \
      libnss3-dev libssl-dev libtool libxml2-dev libxml2-utils libxslt1-dev locales nasm ninja-build \
      patch perl pkg-config python3 python3-dev python3-setuptools rsync time unzip wget xsltproc \
      xz-utils zip zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && (userdel -r ubuntu 2>/dev/null || true) \
    && useradd -m -u 1000 -s /bin/bash builder \
    && mkdir -p /opt/emsdk /opt/qt5 /src /work /cache /out \
    && chown builder:builder /opt/emsdk /opt/qt5 /src /work /cache /out
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

USER builder

ARG EMSDK_REPO
ARG EMSDK_REF
ARG EMSCRIPTEN_VERSION
RUN git clone "$EMSDK_REPO" /opt/emsdk \
    && git -C /opt/emsdk checkout -q "$EMSDK_REF" \
    && /opt/emsdk/emsdk install "$EMSCRIPTEN_VERSION" \
    && /opt/emsdk/emsdk activate "$EMSCRIPTEN_VERSION"

COPY --chown=builder:builder patches/emscripten/ /src/patches/emscripten/
RUN cd /opt/emsdk/upstream/emscripten \
    && for p in /src/patches/emscripten/*.patch; do patch -p1 --forward < "$p"; done \
    && rm -f cache/sysroot/lib/wasm32-emscripten/libhtml5*.a cache/sysroot/lib/wasm32-emscripten/*/libhtml5*.a \
    && ls cache/sysroot/lib/wasm32-emscripten 2>/dev/null | head -5 || true

ARG QTBASE_REPO
ARG QTBASE_COMMIT
RUN git init -q /src/qtbase \
    && git -C /src/qtbase remote add origin "$QTBASE_REPO" \
    && git -C /src/qtbase fetch -q --depth 1 origin "$QTBASE_COMMIT" \
    && git -C /src/qtbase checkout -q FETCH_HEAD
COPY --chown=builder:builder patches/qtbase/ /src/patches/qtbase/
RUN cd /src/qtbase \
    && for p in /src/patches/qtbase/*.patch; do [ -e "$p" ] && git apply "$p"; done; \
    . /opt/emsdk/emsdk_env.sh \
    && ./configure -opensource -confirm-license -xplatform wasm-emscripten -feature-thread \
         -prefix /opt/qt5 -nomake tests -nomake examples -no-pch \
         'QMAKE_CFLAGS+=-sSUPPORT_LONGJMP=wasm' 'QMAKE_CXXFLAGS+=-sSUPPORT_LONGJMP=wasm' \
    && make -j"$(nproc)" \
    && make install

WORKDIR /work
