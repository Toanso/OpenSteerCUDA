#ifndef _STEER_FOR_WANDER_KERNEL_CU_
#define _STEER_FOR_WANDER_KERNEL_CU_

#include <cutil.h>
#include "OpenSteer/VehicleData.h"
#include "CUDAFloatUtilities.cu"
#include "CUDAVectorUtilities.cu"
#include "CUDAKernelOptions.cu"

#define CHECK_BANK_CONFLICTS 0
#if CHECK_BANK_CONFLICTS
#define S_F(i) (CUT_BANK_CHECKER(((float*)steering), i))
#define S(i) (CUT_BANK_CHECKER(steering, i))
#define SI_F(i) (CUT_BANK_CHECKER(((float*)side), i))
#define SI(i) (CUT_BANK_CHECKER(side, i))
#define U_F(i) (CUT_BANK_CHECKER(((float*)up), i))
#define U(i) (CUT_BANK_CHECKER(up, i))
#else
#define S_F(i) ((float*)steering)[i]
#define S(i) steering[i]
#define SI_F(i) ((float*)side)[i]
#define SI(i) side[i]
#define U_F(i) ((float*)up)[i]
#define U(i) up[i]
#endif

__device__ float
scalarRandomWalk(float initial, float walkspeed, float min, float max, float random);

__global__ void
steerForWander2DKernel(VehicleData *vehicleData, float *random, float dt, float3 *steeringVectors, float2 *wanderData, float weight, kernel_options options)
{
    int id = (blockIdx.x * blockDim.x + threadIdx.x);
    int blockOffset2 = (blockDim.x * blockIdx.x);
    int blockOffset3 = (blockDim.x * blockIdx.x * 3);
    
    // shared memory for side vector
    __shared__ float3 side[TPB];
    
    // shared memory for up vector
    __shared__ float3 up[TPB];
    
    // shared memory for steering vectors
    __shared__ float3 steering[TPB];
    
    // copy side vector from global memory (coalesced)
    SI_F(threadIdx.x) = ((float*)(*vehicleData).side)[blockOffset3 + threadIdx.x];
    SI_F(threadIdx.x + blockDim.x) = ((float*)(*vehicleData).side)[blockOffset3 + threadIdx.x + blockDim.x];
    SI_F(threadIdx.x + 2*blockDim.x) = ((float*)(*vehicleData).side)[blockOffset3 + threadIdx.x + 2*blockDim.x];
    
    // copy up vector from global memory (coalesced)
    U_F(threadIdx.x) = ((float*)(*vehicleData).up)[blockOffset3 + threadIdx.x];
    U_F(threadIdx.x + blockDim.x) = ((float*)(*vehicleData).up)[blockOffset3 + threadIdx.x + blockDim.x];
    U_F(threadIdx.x + 2*blockDim.x) = ((float*)(*vehicleData).up)[blockOffset3 + threadIdx.x + 2*blockDim.x];
    
    __syncthreads();
    
    float speed = 12 * dt;
    
    float wanderSide = scalarRandomWalk(wanderData[id].x, speed, -1, +1, random[id]);
    float wanderUp = scalarRandomWalk(wanderData[id].y, speed, -1, +1, random[id+blockOffset2]);
    
    wanderData[id].x = wanderSide;
    wanderData[id].y = wanderUp;
    
    SI(threadIdx.x) = float3Mul(SI(threadIdx.x), wanderSide);
    U(threadIdx.x) = float3Mul(U(threadIdx.x), wanderUp);
    
    S(threadIdx.x).x = SI(threadIdx.x).x + U(threadIdx.x).x;
    S(threadIdx.x).y = 0.f; // SI(threadIdx.x).y + U(threadIdx.x).y;
    S(threadIdx.x).z = SI(threadIdx.x).z + U(threadIdx.x).z;
    
    // multiply by weight
    S(threadIdx.x) = float3Mul(S(threadIdx.x), weight);
    
    if ((options & IGNORE_UNLESS_ZERO) != 0
        && (steeringVectors[id].x != 0.f
         || steeringVectors[id].y != 0.f
         || steeringVectors[id].z != 0.f))
    {
        S(threadIdx.x) = steeringVectors[id];
    } else {
        S(threadIdx.x) = float3Add(S(threadIdx.x), steeringVectors[id]);
    }
    
    __syncthreads();

    // copy steering vector back to global memory (coalesced)
    ((float*)steeringVectors)[blockOffset3 + threadIdx.x] =  S_F(threadIdx.x);
    ((float*)steeringVectors)[blockOffset3 + threadIdx.x + blockDim.x] = S_F(threadIdx.x + blockDim.x);
    ((float*)steeringVectors)[blockOffset3 + threadIdx.x + 2*blockDim.x] = S_F(threadIdx.x + 2*blockDim.x);
}

__device__ float
scalarRandomWalk(float initial, float walkspeed, float min, float max, float random)
{
    float wander = initial + (((random * 2) - 1) * walkspeed);
    return clip(wander, min, max);
}

#endif // _STEER_FOR_FLEE_KERNEL_CU_