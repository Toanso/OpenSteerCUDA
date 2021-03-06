#ifndef _STEER_TO_FOLLOW_PATH_H_
#define _STEER_TO_FOLLOW_PATH_H_

#include <cutil.h>
#include "OpenSteer/VehicleData.h"
#include "OpenSteer/PathwayData.h"
#include "CUDAFloatUtilities.cu"
#include "CUDAVectorUtilities.cu"
#include "CUDAPathwayUtilities.cu"
#include "CUDAKernelOptions.cu"

#define CHECK_BANK_CONFLICTS 0
#if CHECK_BANK_CONFLICTS
#define V_F(i) (CUT_BANK_CHECKER(((float*)velocity), i))
#define F_F(i) (CUT_BANK_CHECKER(((float*)forward), i))
#define P_F(i) (CUT_BANK_CHECKER(((float*)position), i))
#define S_F(i) (CUT_BANK_CHECKER(((float*)steering), i))
#define V(i) (CUT_BANK_CHECKER(velocity, i))
#define F(i) (CUT_BANK_CHECKER(forward, i))
#define P(i) (CUT_BANK_CHECKER(position, i))
#define S(i) (CUT_BANK_CHECKER(steering, i))
#define SP(i) (CUT_BANK_CHECKER(speed, i))
#else
#define V_F(i) ((float*)velocity)[i]
#define F_F(i) ((float*)forward)[i]
#define P_F(i) ((float*)position)[i]
#define S_F(i) ((float*)steering)[i]
#define V(i) velocity[i]
#define F(i) forward[i]
#define P(i) position[i]
#define S(i) steering[i]
#define SP(i) speed[i]
#endif

// Pathway data
__constant__ PathwayData followPathway;

__device__ void
steerForSeekKernelSingle(float3 position, float3 velocity, float3 seekVector, float3 *steeringVectors, int ignore, float weight, kernel_options options);

__global__ void
steerToFollowPathKernel(VehicleData *vehicleData, float3 *steeringVectors, int *direction, float predictionTime, float weight, kernel_options options)
{    
    int id = (blockIdx.x * blockDim.x + threadIdx.x);
    int blockOffset = (blockDim.x * blockIdx.x * 3);
    
    // shared memory for velocity vector
    __shared__ float3 velocity[TPB];
    
    // shared memory for position vector
    __shared__ float3 position[TPB];
    
    // shared memory for speed
    __shared__ float speed[TPB];
    
    // copy speed data from global memory (coalesced)
    SP(threadIdx.x) = (*vehicleData).speed[id];
    
    // copy velocity data from global memory (coalesced)
    V_F(threadIdx.x) = ((float*)(*vehicleData).forward)[blockOffset + threadIdx.x];
    V_F(threadIdx.x + blockDim.x) = ((float*)(*vehicleData).forward)[blockOffset + threadIdx.x + blockDim.x];
    V_F(threadIdx.x + 2*blockDim.x) = ((float*)(*vehicleData).forward)[blockOffset + threadIdx.x + 2*blockDim.x];
    __syncthreads();
    V(threadIdx.x) = float3Mul(V(threadIdx.x), SP(threadIdx.x));
    
    // copy position data from global memory (coalesced)
    P_F(threadIdx.x) = ((float*)(*vehicleData).position)[blockOffset + threadIdx.x];
    P_F(threadIdx.x + blockDim.x) = ((float*)(*vehicleData).position)[blockOffset + threadIdx.x + blockDim.x];
    P_F(threadIdx.x + 2*blockDim.x) = ((float*)(*vehicleData).position)[blockOffset + threadIdx.x + 2*blockDim.x];
    
    __syncthreads();
    
    // our goal will be offset from our path distance by this amount
    float pathDistanceOffset = direction[id] * predictionTime * SP(threadIdx.x);
    
    // predict our future position
    float3 futurePosition = float3PredictFuturePosition(P(threadIdx.x), V(threadIdx.x), predictionTime);

    // measure distance along path of our current and predicted positions
    float nowPathDistance = mapPointToPathDistance(followPathway.points, followPathway.numElements, P(threadIdx.x));
    float futurePathDistance = mapPointToPathDistance(followPathway.points, followPathway.numElements, futurePosition);
           
    // are we facing in the correction direction?
    int rightway = ((pathDistanceOffset > 0) ?
                    (nowPathDistance < futurePathDistance) :
                    (nowPathDistance > futurePathDistance));
                     

    // find the point on the path nearest the predicted future position
    // XXX need to improve calling sequence, maybe change to return a
    // XXX special path-defined object which includes two Vec3s and a 
    // XXX bool (onPath,tangent (ignored), withinPath)
    float3 tangent;
    float outside;
    float3 onPath = mapPointToPath(followPathway.points, followPathway.numElements, followPathway.radius, futurePosition, &tangent, &outside);
    
    // check if end of path reached and turn direction
    if (float3Distance(P(threadIdx.x), followPathway.points[0]) < followPathway.radius) direction[id] = 1;
    if (float3Distance(P(threadIdx.x), followPathway.points[followPathway.numElements - 1]) < followPathway.radius) direction[id] = -1;
    
    // no steering is required if (a) our future position is inside
    // the path tube and (b) we are facing in the correct direction
    float3 target;
    int ignore;
    if ((outside < 0) && rightway) {
        target = make_float3(0, 0, 0);
        ignore = 1;
    } else {
        // otherwise we need to steer towards a target point obtained
        // by adding pathDistanceOffset to our current path position
        float targetPathDistance = nowPathDistance + pathDistanceOffset;
        target = mapPathDistanceToPoint(followPathway.points, followPathway.numElements, followPathway.isCyclic, targetPathDistance);
        ignore = 0;
    }
    
    steerForSeekKernelSingle(P(threadIdx.x), V(threadIdx.x), target, steeringVectors, ignore, weight, options);
}

__device__ void
steerForSeekKernelSingle(float3 position, float3 velocity, float3 seekVector, float3 *steeringVectors, int ignore, float weight, kernel_options options)
{
    int id = (blockIdx.x * blockDim.x + threadIdx.x);
    int blockOffset = (blockDim.x * blockIdx.x * 3);
    
    // shared memory for steering vectors
    __shared__ float3 steering[TPB];
    
    if (ignore != 1) {
        S(threadIdx.x).x = (seekVector.x - position.x) - velocity.x;
        S(threadIdx.x).y = 0.f;//(seekVector.y - position.y) - velocity.y;
        S(threadIdx.x).z = (seekVector.z - position.z) - velocity.z;        
    } else {
        S(threadIdx.x).x = seekVector.x;
        S(threadIdx.x).y = seekVector.y;
        S(threadIdx.x).z = seekVector.z;
    }
    
    __syncthreads();
    
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
    
    // writing back to global memory (coalesced)
    ((float*)steeringVectors)[blockOffset + threadIdx.x] = S_F(threadIdx.x);
    ((float*)steeringVectors)[blockOffset + threadIdx.x + blockDim.x] = S_F(threadIdx.x + blockDim.x);
    ((float*)steeringVectors)[blockOffset + threadIdx.x + 2*blockDim.x] = S_F(threadIdx.x + 2*blockDim.x);
} 
#endif // _STEER_TO_FOLLOW_PATH_H_