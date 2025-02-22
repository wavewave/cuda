/*
 * Extra bits for CUDA bindings
 */

#ifndef C_STUBS_H
#define C_STUBS_H

#ifdef __MINGW32__
#include <host_defines.h>
#undef CUDARTAPI
#define CUDARTAPI __stdcall
#endif

#include <cuda.h>
#include <cudaProfiler.h>
#include <cuda_runtime_api.h>

#ifdef __cplusplus
extern "C" {
#endif

cudaError_t
cudaConfigureCallSimple
(
    int gridX,  int gridY,
    int blockX, int blockY, int blockZ,
    size_t sharedMem,
    cudaStream_t stream
);

CUresult
cuTexRefSetAddress2DSimple
(
    CUtexref            tex,
    CUarray_format      format,
    unsigned int        numChannels,
    CUdeviceptr         dptr,
    size_t              width,
    size_t              height,
    size_t              pitch
);

CUresult
cuMemcpy2DHtoD
(
    CUdeviceptr dstDevice, unsigned int dstPitch, unsigned int dstXInBytes, unsigned int dstY,
    void* srcHost,         unsigned int srcPitch, unsigned int srcXInBytes, unsigned int srcY,
    unsigned int widthInBytes,
    unsigned int height
);

CUresult
cuMemcpy2DHtoDAsync
(
    CUdeviceptr dstDevice, unsigned int dstPitch, unsigned int dstXInBytes, unsigned int dstY,
    void* srcHost,         unsigned int srcPitch, unsigned int srcXInBytes, unsigned int srcY,
    unsigned int widthInBytes,
    unsigned int height,
    CUstream hStream
);

CUresult
cuMemcpy2DDtoH
(
    void* dstHost,         unsigned int dstPitch, unsigned int dstXInBytes, unsigned int dstY,
    CUdeviceptr srcDevice, unsigned int srcPitch, unsigned int srcXInBytes, unsigned int srcY,
    unsigned int widthInBytes,
    unsigned int height
);

CUresult
cuMemcpy2DDtoHAsync
(
    void* dstHost,         unsigned int dstPitch, unsigned int dstXInBytes, unsigned int dstY,
    CUdeviceptr srcDevice, unsigned int srcPitch, unsigned int srcXInBytes, unsigned int srcY,
    unsigned int widthInBytes,
    unsigned int height,
    CUstream hStream
);

CUresult
cuMemcpy2DDtoD
(
    CUdeviceptr dstDevice, unsigned int dstPitch, unsigned int dstXInBytes, unsigned int dstY,
    CUdeviceptr srcDevice, unsigned int srcPitch, unsigned int srcXInBytes, unsigned int srcY,
    unsigned int widthInBytes,
    unsigned int height
);

CUresult
cuMemcpy2DDtoDAsync
(
    CUdeviceptr dstDevice, unsigned int dstPitch, unsigned int dstXInBytes, unsigned int dstY,
    CUdeviceptr srcDevice, unsigned int srcPitch, unsigned int srcXInBytes, unsigned int srcY,
    unsigned int widthInBytes,
    unsigned int height,
    CUstream hStream
);


/*
 * Need to re-export some symbols as they are now generated by #defines, which
 * c2hs does not like in the function binding hooks.
 */
#if CUDA_VERSION >= 3020
#undef cuDeviceTotalMem
#undef cuCtxCreate
#undef cuModuleGetGlobal
#undef cuMemGetInfo
#undef cuMemAlloc
#undef cuMemAllocPitch
#undef cuMemFree
#undef cuMemGetAddressRange
#undef cuMemAllocHost
#undef cuMemHostGetDevicePointer
#undef cuMemcpyHtoD
#undef cuMemcpyDtoH
#undef cuMemcpyDtoD
#undef cuMemcpyDtoA
#undef cuMemcpyAtoD
#undef cuMemcpyHtoA
#undef cuMemcpyAtoH
#undef cuMemcpyAtoA
#undef cuMemcpyHtoAAsync
#undef cuMemcpyAtoHAsync
// #undef cuMemcpy2D
#undef cuMemcpy2DUnaligned
#undef cuMemcpy3D
#undef cuMemcpyHtoDAsync
#undef cuMemcpyDtoHAsync
#undef cuMemcpyDtoDAsync
// #undef cuMemcpy2DAsync
#undef cuMemcpy3DAsync
#undef cuMemsetD8
#undef cuMemsetD16
#undef cuMemsetD32
#undef cuMemsetD2D8
#undef cuMemsetD2D16
#undef cuMemsetD2D32
#undef cuArrayCreate
#undef cuArrayGetDescriptor
#undef cuArray3DCreate
#undef cuArray3DGetDescriptor
#undef cuTexRefSetAddress
// #undef cuTexRefSetAddress2D
#undef cuTexRefGetAddress
#undef cuGraphicsResourceGetMappedPointer

CUresult CUDAAPI cuDeviceTotalMem(size_t *bytes, CUdevice dev);
CUresult CUDAAPI cuCtxCreate(CUcontext *pctx, unsigned int flags, CUdevice dev);
CUresult CUDAAPI cuModuleGetGlobal(CUdeviceptr *dptr, size_t *bytes, CUmodule hmod, const char *name);
CUresult CUDAAPI cuMemGetInfo(size_t *free, size_t *total);
CUresult CUDAAPI cuMemAlloc(CUdeviceptr *dptr, size_t bytesize);
// CUresult CUDAAPI cuMemAllocPitch(CUdeviceptr *dptr, unsigned int *pPitch, unsigned int WidthInBytes, unsigned int Height, unsigned int ElementSizeBytes);
CUresult CUDAAPI cuMemFree(CUdeviceptr dptr);
CUresult CUDAAPI cuMemGetAddressRange(CUdeviceptr *pbase, size_t *psize, CUdeviceptr dptr);
// CUresult CUDAAPI cuMemAllocHost(void **pp, unsigned int bytesize);
CUresult CUDAAPI cuMemHostGetDevicePointer(CUdeviceptr *pdptr, void *p, unsigned int Flags);
CUresult CUDAAPI cuMemcpyHtoD(CUdeviceptr dstDevice, const void *srcHost, size_t ByteCount);
CUresult CUDAAPI cuMemcpyDtoH(void *dstHost, CUdeviceptr srcDevice, size_t ByteCount);
CUresult CUDAAPI cuMemcpyDtoD(CUdeviceptr dstDevice, CUdeviceptr srcDevice, size_t ByteCount);
// CUresult CUDAAPI cuMemcpyDtoA(CUarray dstArray, unsigned int dstOffset, CUdeviceptr srcDevice, unsigned int ByteCount);
// CUresult CUDAAPI cuMemcpyAtoD(CUdeviceptr dstDevice, CUarray srcArray, unsigned int srcOffset, unsigned int ByteCount);
// CUresult CUDAAPI cuMemcpyHtoA(CUarray dstArray, unsigned int dstOffset, const void *srcHost, unsigned int ByteCount);
// CUresult CUDAAPI cuMemcpyAtoH(void *dstHost, CUarray srcArray, unsigned int srcOffset, unsigned int ByteCount);
// CUresult CUDAAPI cuMemcpyAtoA(CUarray dstArray, unsigned int dstOffset, CUarray srcArray, unsigned int srcOffset, unsigned int ByteCount);
// CUresult CUDAAPI cuMemcpyHtoAAsync(CUarray dstArray, unsigned int dstOffset, const void *srcHost, unsigned int ByteCount, CUstream hStream);
// CUresult CUDAAPI cuMemcpyAtoHAsync(void *dstHost, CUarray srcArray, unsigned int srcOffset, unsigned int ByteCount, CUstream hStream);
// CUresult CUDAAPI cuMemcpy2D(const CUDA_MEMCPY2D *pCopy);
// CUresult CUDAAPI cuMemcpy2DUnaligned(const CUDA_MEMCPY2D *pCopy);
// CUresult CUDAAPI cuMemcpy3D(const CUDA_MEMCPY3D *pCopy);
CUresult CUDAAPI cuMemcpyHtoDAsync(CUdeviceptr dstDevice, const void *srcHost, size_t ByteCount, CUstream hStream);
CUresult CUDAAPI cuMemcpyDtoHAsync(void *dstHost, CUdeviceptr srcDevice, size_t ByteCount, CUstream hStream);
CUresult CUDAAPI cuMemcpyDtoDAsync(CUdeviceptr dstDevice, CUdeviceptr srcDevice, size_t ByteCount, CUstream hStream);
// CUresult CUDAAPI cuMemcpy2DAsync(const CUDA_MEMCPY2D *pCopy, CUstream hStream);
// CUresult CUDAAPI cuMemcpy3DAsync(const CUDA_MEMCPY3D *pCopy, CUstream hStream);
CUresult CUDAAPI cuMemsetD8(CUdeviceptr dstDevice, unsigned char uc, size_t N);
CUresult CUDAAPI cuMemsetD16(CUdeviceptr dstDevice, unsigned short us, size_t N);
CUresult CUDAAPI cuMemsetD32(CUdeviceptr dstDevice, unsigned int ui, size_t N);
// CUresult CUDAAPI cuMemsetD2D8(CUdeviceptr dstDevice, unsigned int dstPitch, unsigned char uc, unsigned int Width, unsigned int Height);
// CUresult CUDAAPI cuMemsetD2D16(CUdeviceptr dstDevice, unsigned int dstPitch, unsigned short us, unsigned int Width, unsigned int Height);
// CUresult CUDAAPI cuMemsetD2D32(CUdeviceptr dstDevice, unsigned int dstPitch, unsigned int ui, unsigned int Width, unsigned int Height);
// CUresult CUDAAPI cuArrayCreate(CUarray *pHandle, const CUDA_ARRAY_DESCRIPTOR *pAllocateArray);
// CUresult CUDAAPI cuArrayGetDescriptor(CUDA_ARRAY_DESCRIPTOR *pArrayDescriptor, CUarray hArray);
// CUresult CUDAAPI cuArray3DCreate(CUarray *pHandle, const CUDA_ARRAY3D_DESCRIPTOR *pAllocateArray);
// CUresult CUDAAPI cuArray3DGetDescriptor(CUDA_ARRAY3D_DESCRIPTOR *pArrayDescriptor, CUarray hArray);
CUresult CUDAAPI cuTexRefSetAddress(size_t *ByteOffset, CUtexref hTexRef, CUdeviceptr dptr, size_t bytes);
// CUresult CUDAAPI cuTexRefSetAddress2D(CUtexref hTexRef, const CUDA_ARRAY_DESCRIPTOR *desc, CUdeviceptr dptr, unsigned int Pitch);
// CUresult CUDAAPI cuTexRefGetAddress(CUdeviceptr *pdptr, CUtexref hTexRef);
// CUresult CUDAAPI cuGraphicsResourceGetMappedPointer(CUdeviceptr *pDevPtr, unsigned int *pSize, CUgraphicsResource resource);
#endif

#if CUDA_VERSION >= 4000
#undef cuCtxDestroy
#undef cuCtxPopCurrent
#undef cuCtxPushCurrent
#undef cuStreamDestroy
#undef cuEventDestroy

CUresult CUDAAPI cuCtxDestroy(CUcontext ctx);
CUresult CUDAAPI cuCtxPopCurrent(CUcontext *pctx);
CUresult CUDAAPI cuCtxPushCurrent(CUcontext ctx);
CUresult CUDAAPI cuStreamDestroy(CUstream hStream);
CUresult CUDAAPI cuEventDestroy(CUevent hEvent);
#endif

#if CUDA_VERSION >= 6050
#undef cuMemHostRegister
#undef cuLinkCreate
#undef cuLinkAddData
#undef cuLinkAddFile

CUresult CUDAAPI cuMemHostRegister(void *p, size_t bytesize, unsigned int Flags);
CUresult CUDAAPI cuLinkCreate(unsigned int numOptions, CUjit_option *options, void **optionValues, CUlinkState *stateOut);
CUresult CUDAAPI cuLinkAddData(CUlinkState state, CUjitInputType type, void *data, size_t size, const char *name, unsigned int numOptions, CUjit_option *options, void **optionValues);
CUresult CUDAAPI cuLinkAddFile(CUlinkState state, CUjitInputType type, const char *path, unsigned int numOptions, CUjit_option *options, void **optionValues);
#endif

#ifdef __cplusplus
}
#endif
#endif
