// Does data cached in L2 by one kernel survive into the NEXT kernel? (AMD gfx90a / MI210)
// 256 lines, 1 KiB apart (256 KiB, far below the 8 MiB L2), each loaded by a single thread and timed with s_memtime.
//   probe   = mt4g's __forceBypassAllCacheReads load (flat_load_dword glc slc)
//   probeL2 = flat_load_dword glc (skips vL1, may hit L2)
// "flush" streams 256 MiB through L2 so the lines are certainly not cached.
// Result on MI210: every case takes the main-memory latency (~570 cycles) and misses in L2, even right after another
// kernel loaded the same lines, i.e. L2 contents do not carry over to the next kernel.
// Build: hipcc --offload-arch=gfx90a -O2 cross_kernel_l2.cpp -o cross_kernel_l2      Run: ./cross_kernel_l2 <gpu-id>
#include <hip/hip_runtime.h>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <vector>

constexpr int N = 256, STRIDE = 1024 / 4;

__device__ __forceinline__ uint64_t tmr() { uint64_t c; asm volatile("s_memtime %0\n s_waitcnt lgkmcnt(0)" : "=s"(c)); return c; }
__device__ __forceinline__ uint32_t bypassLoad(const uint32_t *p) {
    uint32_t r; asm volatile("flat_load_dword %0, %1 glc slc\n s_waitcnt vmcnt(0)" : "=v"(r) : "v"(p)); return r;
}
__device__ __forceinline__ uint32_t l2Load(const uint32_t *p) {
    uint32_t r; asm volatile("flat_load_dword %0, %1 glc\n s_waitcnt vmcnt(0)" : "=v"(r) : "v"(p)); return r;
}

__global__ void flush(const uint32_t *f, size_t n, uint32_t *s) {
    uint32_t a = 0;
    for (size_t i = (blockIdx.x * blockDim.x + threadIdx.x) * 16; i < n; i += gridDim.x * blockDim.x * 16) a ^= f[i];
    s[blockIdx.x * blockDim.x + threadIdx.x] = a;
}
// Plain loads: allocate the lines in L2.
__global__ void fillNormal(const uint32_t *a, uint32_t *s) { uint32_t x = 0; for (int i = 0; i < N; i++) x ^= a[i * STRIDE]; *s = x; }
template <bool BYPASS> __global__ void probe(const uint32_t *a, uint32_t *t, uint32_t *s) {
    uint32_t x = 0;
    for (int i = 0; i < N; i++) {
        uint64_t b = tmr();
        x ^= BYPASS ? bypassLoad(a + i * STRIDE + (x & 0)) : l2Load(a + i * STRIDE + (x & 0));
        uint64_t e = tmr();
        t[i] = e - b;
    }
    *s = x;
}

int main(int argc, char **argv) {
    (void)hipSetDevice(argc > 1 ? atoi(argv[1]) : 0);
    size_t fn = 256ull << 20; uint32_t *a, *f, *s, *t;
    (void)hipMalloc(&a, N * STRIDE * 4); (void)hipMalloc(&f, fn); (void)hipMalloc(&s, 1 << 22); (void)hipMalloc(&t, N * 4);
    (void)hipMemset(a, 0, N * STRIDE * 4); (void)hipMemset(f, 0, fn); (void)hipDeviceSynchronize();
    auto report = [&](const char *name) {
        (void)hipDeviceSynchronize(); std::vector<uint32_t> h(N); (void)hipMemcpy(h.data(), t, N * 4, hipMemcpyDeviceToHost);
        std::sort(h.begin(), h.end()); printf("%-46s median %u  p10 %u  p90 %u cycles\n", name, h[N / 2], h[N / 10], h[9 * N / 10]);
    };
    auto fl = [&] { flush<<<3328, 256>>>(f, fn / 4, s); (void)hipDeviceSynchronize(); };
    fl();                                       probe<true><<<1, 1>>>(a, t, s);  report("1 bypass load, cold (after flush)");
                                                probe<true><<<1, 1>>>(a, t, s);  report("2 bypass load, same lines again");
    fl(); fillNormal<<<1, 1>>>(a, s); (void)hipDeviceSynchronize();
                                                probe<true><<<1, 1>>>(a, t, s);  report("3 bypass load, after plain loads filled L2");
    fl();                                       probe<true><<<1, 1>>>(a, t, s);  report("4 bypass load, cold again");
    fl();                                       probe<false><<<1, 1>>>(a, t, s); report("5 glc-only load, cold (after flush)");
                                                probe<false><<<1, 1>>>(a, t, s); report("6 glc-only load, same lines again");
}
