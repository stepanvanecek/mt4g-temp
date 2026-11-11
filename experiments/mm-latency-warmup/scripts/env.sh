# milan1 (MI210) build/run environment for the main-memory latency experiment.
# Harmless on other hosts (it only prepends paths); set up hipcc/CUDA/cmake/python there yourself.
# ROCm 7.2.4 at /opt/rocm includes the HIP/HSA CMake packages (no overlay needed since 2026-10-10).
export PKG_CONFIG_PATH=/opt/amdgpu/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
export PATH=$HOME/opt/mt4g-venv/bin:$PATH                 # cmake + python3.12/matplotlib
