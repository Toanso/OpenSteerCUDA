#include "SteerForWander.h"
#include <cuda_runtime.h>
#include "OpenSteer/VehicleData.h"
#include "CUDAKernelOptions.cu"
#include <iostream>

using namespace OpenSteer;
using namespace std;

__global__ void
steerForWander2DKernel(VehicleData *vehicleData, float *random, float dt, float3 *steeringVectors, float2 *wanderData, float weight, kernel_options options);

OpenSteer::SteerForWander::SteerForWander(float weight, kernel_options options)
{
    d_randomNumbers = NULL;
    d_wanderData = NULL;
    randomizedVector = NULL;
    threadsPerBlock = 128;
    this->weight = weight;
    this->options = options;
}

OpenSteer::SteerForWander::~SteerForWander() {}

void OpenSteer::SteerForWander::init()
{
    // random number generator
    randomizedVector = new RandomizedVector(2*getNumberOfAgents());
    
    // device memory for wander data
    mem_size_wander = getNumberOfAgents()*sizeof(float2);
    cudaError_t retval = cudaMalloc((void **)&d_wanderData, mem_size_wander);
    if (retval != cudaSuccess)
        cout << "Error while allocating d_wanderData memory: " << cudaGetErrorString(retval) << endl;
    
    // d_wanderData memset
    cudaMemset(d_wanderData, 0, mem_size_wander);
    
    // device memory for random numbers
    mem_size_random = randomizedVector->size() * sizeof(float);
    retval = cudaMalloc((void **)&d_randomNumbers, mem_size_random);
    if (retval != cudaSuccess)
        cout << "Error while allocating d_randomNumbers memory: " << cudaGetErrorString(retval) << endl;
        
}

void OpenSteer::SteerForWander::run()
{
    // renew random numbers
    randomizedVector->renew();
    cudaMemcpy(d_randomNumbers, randomizedVector->getVector(), mem_size_random, cudaMemcpyHostToDevice);
    
    steerForWander2DKernel<<<gridDim(), blockDim()>>>(getVehicleData(), d_randomNumbers, getElapsedTime(), getSteeringVectors(), d_wanderData, weight, options);
}

void OpenSteer::SteerForWander::close()
{
    if (d_wanderData != NULL) {
        cudaFree(d_wanderData);
        d_wanderData = NULL;        
    }
    
    if (d_randomNumbers != NULL) {
        cudaFree(d_randomNumbers);
        d_randomNumbers = NULL;
    }
    
    if (randomizedVector != NULL) {
        delete randomizedVector;
        randomizedVector = NULL;        
    }
}
