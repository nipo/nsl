# NSL CI image: GHDL + Python 3.13 + GBS + NSL GBS plugin.
#
# Built and pushed by .github/workflows/ci-image.yml. Consumed by
# .github/workflows/tests.yml via `container:`.
#
# Tag scheme:
#   ghcr.io/<owner>/nsl-ci:latest      -- newest build
#   ghcr.io/<owner>/nsl-ci:sha-<sha>   -- one per commit, for pinning

# GHDL upstream provides ready-made images keyed on (distro, backend, version).
# mcode is the right pick for short-running unit tests: it skips LLVM code
# generation entirely (no -O2 compile pass), so the per-test elaborate cost
# is dominated by parsing rather than code emission. Per-cycle simulation is
# slower than LLVM, but the NSL suite simulates only a few hundred ms of
# wall-clock-equivalent time per test, where LLVM's faster runtime never
# recoups its compile-time tax.
#
# mcode is x86-64 only. Both GitHub-hosted runners and the act-on-Mac
# emulation path target linux/amd64, so this is fine for our use.
FROM ghdl/ghdl:6.0.0-mcode-ubuntu-24.04

# Python 3.13 is needed for gbs and the NSL plugin. Ubuntu 24.04 ships 3.12,
# so pull 3.13 from deadsnakes. NodeJS is needed because `container:`-jobs in
# GitHub Actions run JavaScript actions (e.g. actions/checkout,
# actions/upload-artifact) inside the container; the runner expects Node 20+
# in PATH. Use the upstream NodeSource repo since Ubuntu's universe is on 18.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        ca-certificates \
        curl \
        git \
        && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get install -y --no-install-recommends \
        python3.13 \
        python3.13-venv \
        && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Make python3.13 the default `python` and bootstrap pip.
RUN ln -sf /usr/bin/python3.13 /usr/local/bin/python && \
    python -m ensurepip --upgrade && \
    python -m pip install --no-cache-dir --upgrade pip

# Pinnable via build-arg so a Dockerfile change isn't required to bump gbs.
ARG GBS_REF=master
RUN python -m pip install --no-cache-dir \
        "git+https://github.com/nipo/gbs.git@${GBS_REF}"

# NSL plugin from the checked-out source tree. The image rebuilds whenever
# build/gbs/** changes (see .github/workflows/ci-image.yml triggers), so the
# baked-in plugin tracks the repo.
COPY build/gbs/ /opt/nsl-plugin/
RUN python -m pip install --no-cache-dir /opt/nsl-plugin

# Default gbs tool config: ghdl on PATH (provided by the base image), with the
# same warning suppressions and runtime flags the local dev environment uses.
RUN mkdir -p /root/.config && \
    printf '%s\n' \
        'tools:' \
        '  - name: ghdl' \
        '    variant: system' \
        '    config:' \
        '      executable: ghdl' \
        '      analyze_args:   ["-Wno-hide"]' \
        '      elaborate_args: ["-Wno-hide"]' \
        '      run_args:       ["--ieee-asserts=disable"]' \
        > /root/.config/gbs.yaml

WORKDIR /work
