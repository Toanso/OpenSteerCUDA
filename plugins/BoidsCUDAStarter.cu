#include <cuda_runtime.h>
#include "OpenSteer/VehicleData.h"
#include "OpenSteer/NeighborData.h"
#include "CUDAKernelOptions.cu"
#include <stdio.h>
#include <cutil.h>

__global__ void
findNeighborsKernel(VehicleData* vehicleData, int* indices, int* agents, NeighborData* neighbours, float radius);

__global__ void
steerForSeparationKernel(VehicleData *vehicleData, VehicleConst *vehicleConst, float3 *steeringVectors, float maxDistance, float cosMaxAngle, NeighborData* neighborData, float weight, kernel_options options);

__global__ void
steerForAlignmentKernel(VehicleData *vehicleData, VehicleConst *vehicleConst, float3 *steeringVectors, float maxDistance, float cosMaxAngle, NeighborData* neighborData, float weight, kernel_options options);

__global__ void
steerForCohesionKernel(VehicleData *vehicleData, VehicleConst *vehicleConst, float3 *steeringVectors, float maxDistance, float cosMaxAngle, NeighborData* neighborData, float weight, kernel_options options);

__global__ void
updateKernel(VehicleData *vehicleData, VehicleConst *vehicleConst, float3 *steeringVectors, float elapsedTime, kernel_options options);

void debugNeighbors(VehicleData *vehicleData, NeighborData* neighborData, int numOfVehicles);



// device memory objects
static float3* d_steeringVectors = NULL;
static float3* h_steeringVectors = NULL;
static VehicleData* d_vehicleData = NULL;
static VehicleConst* d_vehicleConst = NULL;
static NeighborData* d_neighborData = NULL;
static NeighborData* h_neighborData = NULL;
static int* d_neighborIndices = NULL;
static int* d_neighborAgents = NULL;

void runBoidsKernel(VehicleData *h_vehicleData, VehicleConst *h_vehicleConst, int numOfVehicles, int* h_neighborIndices, int numOfNIndices, int* h_neighborAgents, int numOfNAgents, float elapsedTime)
{
    // init GPU
    int gpu_count;
    cudaGetDeviceCount(&gpu_count);
    if (gpu_count < 1) {
        return;
    }
    
    cudaSetDevice(0);
    
    dim3 grid(numOfVehicles/TPB, 1, 1);
    dim3 threads(TPB, 1, 1);
    
    // allocate device memory
    const unsigned int mem_size_vehicle = sizeof(VehicleData);
    if (d_vehicleData == NULL) {
        cudaMalloc((void **)&d_vehicleData, mem_size_vehicle);
        cudaMemcpy(d_vehicleData, h_vehicleData, mem_size_vehicle, cudaMemcpyHostToDevice);
    }
    
    const unsigned int mem_size_vehicle_const = sizeof(VehicleConst);
    if (d_vehicleConst == NULL) {
        cudaMalloc((void **)&d_vehicleConst, mem_size_vehicle_const);
        cudaMemcpy(d_vehicleConst, h_vehicleConst, mem_size_vehicle_const, cudaMemcpyHostToDevice);
    }
    
    const unsigned int mem_size_steering = sizeof(float3) * numOfVehicles;
    
    if (d_steeringVectors == NULL) {
        cudaMalloc((void **)&d_steeringVectors, mem_size_steering);
        h_steeringVectors = (float3*)malloc(mem_size_steering);
    }
    
    unsigned int timer = 0;
    CUT_SAFE_CALL(cutCreateTimer(&timer));
    CUT_SAFE_CALL(cutStartTimer(timer));
    
    cudaMemset(d_steeringVectors, 0, mem_size_steering);
    
    CUT_SAFE_CALL(cutStopTimer(timer));
    printf("Raw processing time (cudaMemset): %f (ms) \n", cutGetTimerValue(timer));
    CUT_SAFE_CALL(cutDeleteTimer(timer));
    CUT_SAFE_CALL(cutCreateTimer(&timer));
    
    const unsigned int mem_size_neighbor_indices = sizeof(int) * numOfNIndices;
    const unsigned int mem_size_neighbor_agents = sizeof(int) * numOfNAgents;
    const unsigned int mem_size_neighbor_data = sizeof(NeighborData) * numOfVehicles;
    
    if (d_neighborData == NULL) {
        const unsigned int mem_size_neighbor_data = sizeof(NeighborData) * numOfVehicles;
        cudaMalloc((void **)&d_neighborData, mem_size_neighbor_data);
        //h_neighborData = (NeighborData*) malloc(mem_size_neighbor_data);
        cudaMalloc((void **)&d_neighborIndices, mem_size_neighbor_indices);
        cudaMalloc((void **)&d_neighborAgents, mem_size_neighbor_agents);
    }

    CUT_SAFE_CALL(cutStartTimer(timer));
    
    // copy neighbor raw data to global memory
    cudaMemcpy(d_neighborIndices, h_neighborIndices, mem_size_neighbor_indices, cudaMemcpyHostToDevice);
    cudaMemcpy(d_neighborAgents, h_neighborAgents, mem_size_neighbor_agents, cudaMemcpyHostToDevice);
    
    CUT_SAFE_CALL(cutStopTimer(timer));
    printf("Raw processing time (cudaMemcpy): %f (ms) \n", cutGetTimerValue(timer));
    CUT_SAFE_CALL(cutDeleteTimer(timer));
    CUT_SAFE_CALL(cutCreateTimer(&timer));
    CUT_SAFE_CALL(cutStartTimer(timer));
    
    // run find neighbor kernel
    findNeighborsKernel<<<numOfVehicles/TPB, TPB>>>(d_vehicleData, d_neighborIndices, d_neighborAgents, d_neighborData, 4.24f);
    //CUT_CHECK_ERROR("findNeighborsKernel execution failed");
    
    CUT_SAFE_CALL(cutStopTimer(timer));
    printf("Raw processing time (findNeighbors): %f (ms) \n", cutGetTimerValue(timer));
    CUT_SAFE_CALL(cutDeleteTimer(timer));
    CUT_SAFE_CALL(cutCreateTimer(&timer));
    CUT_SAFE_CALL(cutStartTimer(timer));
    
    // copy neighbor data back for testing reason
    //cudaMemcpy(h_neighborData, d_neighborData, mem_size_neighbor_data, cudaMemcpyDeviceToHost);
    
    //debugNeighbors(h_vehicleData, h_neighborData, numOfVehicles);

    // run steer for separation kernel
    steerForSeparationKernel<<<grid, threads>>>(d_vehicleData, d_vehicleConst, d_steeringVectors, 5.f, -0.707f, d_neighborData, 5.f, NONE);
    
    
    CUT_SAFE_CALL(cutStopTimer(timer));
    printf("Raw processing time (steerForSeparation): %f (ms) \n", cutGetTimerValue(timer));
    CUT_SAFE_CALL(cutDeleteTimer(timer));
    CUT_SAFE_CALL(cutCreateTimer(&timer));
    CUT_SAFE_CALL(cutStartTimer(timer));
    
    // run steer for alignment kernel
    steerForAlignmentKernel<<<grid, threads>>>(d_vehicleData, d_vehicleConst, d_steeringVectors, 7.5f, 0.7f, d_neighborData, 8.f, NONE);
    
    CUT_SAFE_CALL(cutStopTimer(timer));
    printf("Raw processing time (steerForAlignment): %f (ms) \n", cutGetTimerValue(timer));
    CUT_SAFE_CALL(cutDeleteTimer(timer));
    CUT_SAFE_CALL(cutCreateTimer(&timer));
    CUT_SAFE_CALL(cutStartTimer(timer));
    
    // run steer for cohesion kernel
    steerForCohesionKernel<<<grid, threads>>>(d_vehicleData, d_vehicleConst, d_steeringVectors, 9.f, -0.15f, d_neighborData, 8.f, NONE);
    
    CUT_SAFE_CALL(cutStopTimer(timer));
    printf("Raw processing time (steerForCohesion): %f (ms) \n", cutGetTimerValue(timer));
    CUT_SAFE_CALL(cutDeleteTimer(timer));
    CUT_SAFE_CALL(cutCreateTimer(&timer));
    CUT_SAFE_CALL(cutStartTimer(timer));
    
    // copy steering vectors back to test
    //cudaMemcpy(h_steeringVectors, d_steeringVectors, mem_size_steering, cudaMemcpyDeviceToHost);
    
//    int n;
//    for (n=0; n < numOfVehicles; n++) {
//        printf("(%d): (%f, %f, %f)\n", n, h_steeringVectors[n].x, h_steeringVectors[n].y, h_steeringVectors[n].z);
//    }
    
    // run update kernel
    updateKernel<<<grid, threads>>>(d_vehicleData, d_vehicleConst, d_steeringVectors, elapsedTime, (kernel_options)(LOCAL_SPACE_BANKING | SPHERICAL_WRAP_AROUND));
    
    CUT_SAFE_CALL(cutStopTimer(timer));
    printf("Raw processing time (updateKernel): %f (ms) \n", cutGetTimerValue(timer));
    CUT_SAFE_CALL(cutDeleteTimer(timer));
    CUT_SAFE_CALL(cutCreateTimer(&timer));
    CUT_SAFE_CALL(cutStartTimer(timer));
    
    // copy vehicle data back to host memory
    cudaMemcpy(h_vehicleData, d_vehicleData, mem_size_vehicle, cudaMemcpyDeviceToHost);
    
    CUT_SAFE_CALL(cutStopTimer(timer));
    printf("Raw processing time (memcopy back): %f (ms) \n", cutGetTimerValue(timer));
    CUT_SAFE_CALL(cutDeleteTimer(timer));
}

void endBoids(void)
{
    cudaFree(d_vehicleData);
    cudaFree(d_vehicleConst);
    cudaFree(d_steeringVectors);    
    cudaFree(d_neighborIndices);
    cudaFree(d_neighborAgents);
    cudaFree(d_neighborData);

    d_vehicleData = NULL;
    d_vehicleConst = NULL;
    d_steeringVectors = NULL;
    d_neighborIndices = NULL;
    d_neighborAgents = NULL;
    d_neighborData = NULL;
}

void debugNeighbors(VehicleData *vehicleData, NeighborData* neighborData, int numOfVehicles)
{
    int i;
    
    for (i = 0; i < numOfVehicles; i++) {
        float3 position = (*vehicleData).position[i];
        printf("Checking Vehicle %d: (%f, %f, %f):\n", i, position.x, position.y, position.z);
        
        int numOfNeighbors = neighborData[i].numOfNeighbors;
        printf("  Found %d neighbors:\n", numOfNeighbors);
        
        int n;
        for (n = 0; n < numOfNeighbors; n++) {
            int idOfNeighbor = neighborData[i].idsOfNeighbors[n];
            float3 positionOfNeighbor = (*vehicleData).position[idOfNeighbor];
            printf("    ID: %d Pos: (%f, %f, %f)\n", idOfNeighbor, positionOfNeighbor.x, positionOfNeighbor.y, positionOfNeighbor.z);
        }
    }
}
