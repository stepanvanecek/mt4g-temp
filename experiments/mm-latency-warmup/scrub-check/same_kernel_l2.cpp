// Can mt4g's "bypass all caches" load (flat_load_dword glc slc) hit in L2 when the line is already there?
// (AMD gfx90a / MI210). One thread, one kernel: pass 1 loads 256 lines (1 KiB apart), pass 2 loads the same lines
// again and is timed. The four kernels combine glc (skips vL1, may hit L2) and glc slc (mt4g's load) in both passes.
// Result on MI210: pass 2 takes ~300 cycles (L2 hit) in every case vs ~570 from main memory, and the L2 counters show
// 256 extra hits, i.e. glc slc skips vL1 but NOT L2 -- within one kernel.
// Build: hipcc --offload-arch=gfx90a -O2 same_kernel_l2.cpp -o same_kernel_l2      Run: ./same_kernel_l2 <gpu-id>
#include <hip/hip_runtime.h>
#include <cstdio>
#include <vector>
#include <algorithm>
#include <cstdlib>
constexpr int N = 256, STRIDE = 1024 / 4;
__device__ __forceinline__ uint64_t tmr(){uint64_t c;asm volatile("s_memtime %0\n s_waitcnt lgkmcnt(0)":"=s"(c));return c;}
template<int M> __device__ __forceinline__ uint32_t ld(const uint32_t*p){uint32_t r;
  if constexpr(M==0) asm volatile("flat_load_dword %0, %1 glc slc\n s_waitcnt vmcnt(0)":"=v"(r):"v"(p));   // mt4g bypass load
  else               asm volatile("flat_load_dword %0, %1 glc\n s_waitcnt vmcnt(0)":"=v"(r):"v"(p));       // L1 bypass, L2 allowed
  return r;}
// pass 1 loads each line once (untimed), pass 2 loads the same lines again (timed) -- all inside ONE kernel
template<int M1,int M2> __global__ void k(const uint32_t*a,uint32_t*t,uint32_t*s){uint32_t x=0;
  for(int i=0;i<N;i++) x^=ld<M1>(a+i*STRIDE+(x&0));
  for(int i=0;i<N;i++){uint64_t b=tmr();x^=ld<M2>(a+i*STRIDE+(x&0));uint64_t e=tmr();t[i]=e-b;}*s=x;}
__global__ void flush(const uint32_t*f,size_t n,uint32_t*s){uint32_t a=0;for(size_t i=(blockIdx.x*blockDim.x+threadIdx.x)*16;i<n;i+=gridDim.x*blockDim.x*16)a^=f[i];s[blockIdx.x*blockDim.x+threadIdx.x]=a;}
int main(int argc,char**argv){(void)hipSetDevice(argc>1?atoi(argv[1]):0);size_t fn=256ull<<20;uint32_t *a,*f,*s,*t;
 (void)hipMalloc(&a,N*STRIDE*4);(void)hipMalloc(&f,fn);(void)hipMalloc(&s,1<<22);(void)hipMalloc(&t,N*4);
 (void)hipMemset(a,0,N*STRIDE*4);(void)hipMemset(f,0,fn);(void)hipDeviceSynchronize();
 auto run=[&](auto kern,const char*name){flush<<<3328,256>>>(f,fn/4,s);kern<<<1,1>>>(a,t,s);(void)hipDeviceSynchronize();
   std::vector<uint32_t>h(N);(void)hipMemcpy(h.data(),t,N*4,hipMemcpyDeviceToHost);std::sort(h.begin(),h.end());
   printf("%-58s median %u  p10 %u  p90 %u cycles\n",name,h[N/2],h[N/10],h[9*N/10]);};
 run(k<1,1>,"A pass1 glc     -> pass2 glc      (L2 hit expected)");
 run(k<1,0>,"B pass1 glc     -> pass2 glc slc  (line is in L2)");
 run(k<0,0>,"C pass1 glc slc -> pass2 glc slc  (mt4g load, twice)");
 run(k<0,1>,"D pass1 glc slc -> pass2 glc      (did slc allocate?)");
}
