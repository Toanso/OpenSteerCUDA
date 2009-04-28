#include "OpenSteer/CUDAPlugIn.h"

using namespace OpenSteer;

typedef std::vector<AbstractCUDAKernel *>::const_iterator kernel_iterator;

OpenSteer::CUDAPlugIn::CUDAPlugIn()
{
    memoryBackend = MemoryBackend::instance();
    this->setNumberOfAgents(0);
    kernels.clear();
    
    // initializing device memory pointers
    d_steeringVectors = NULL;
    mem_size_steering = 0;
    d_vehicleData = NULL;
    mem_size_vehicle_data = 0;
    d_vehicleConst = NULL;
    mem_size_vehicle_const = 0;
}

OpenSteer::CUDAPlugIn::~CUDAPlugIn() {}

void OpenSteer::CUDAPlugIn::close(void)
{
    kernels.clear();
    
    MemoryBackend::reset();
}

bool OpenSteer::CUDAPlugIn::addKernel(AbstractCUDAKernel *kernel)
{
    kernel->setPlugIn(this);
    
    kernels.push_back(kernel);
    return true;
}

bool OpenSteer::CUDAPlugIn::removeKernel(AbstractCUDAKernel *kernel)
{
    // no implementation yet
    return true;
}

void OpenSteer::CUDAPlugIn::initKernels(void)
{
    // alloc memory for steering vectors
    mem_size_steering = sizeof(float3) * this->getNumberOfAgents();
    
    if (d_steeringVectors == NULL) {
        cudaError_t retval = cudaMalloc((void **)&d_steeringVectors, mem_size_steering);
        if (retval != cudaSuccess)
            std::cout << "Error while allocating d_steeringVectors memory: " << cudaGetErrorString(retval) << std::endl;
    }
    
    // alloc memory for vehicle data
    mem_size_vehicle_data = sizeof(VehicleData);
    
    if (d_vehicleData == NULL) {
        cudaError_t retval = cudaMalloc((void **)&d_vehicleData, mem_size_vehicle_data);
        if (retval != cudaSuccess)
            std::cout << "Error while allocating d_vehicleData memory: " << cudaGetErrorString(retval) << std::endl;
    }
    
    // alloc memory for vehicle const
    mem_size_vehicle_const = sizeof(VehicleConst);
    
    if (d_vehicleConst == NULL) {
        cudaError_t retval = cudaMalloc((void **)&d_vehicleConst, mem_size_vehicle_const);
        if (retval != cudaSuccess)
            std::cout << "Error while allocating d_vehicleConst memory: " << cudaGetErrorString(retval) << std::endl;
    }
    
    // init all kernels
    for (kernel_iterator i = kernels.begin(); i != kernels.end(); i++) {
        (*i)->init();
    }
}

void OpenSteer::CUDAPlugIn::closeKernels(void)
{
    for (kernel_iterator i = kernels.begin(); i != kernels.end(); i++) {
        (*i)->close();
    }
    
    // free steering vector memory
    cudaFree(d_steeringVectors);
    cudaFree(d_vehicleData);
    cudaFree(d_vehicleConst);
    
    d_steeringVectors = NULL;
    d_vehicleData = NULL;
    d_vehicleConst = NULL;
}

void OpenSteer::CUDAPlugIn::update(const float currentTime, const float elapsedTime)
{
    cudaMemset(d_steeringVectors, 0, mem_size_steering);
}

void OpenSteer::CUDAPlugIn::setNumberOfAgents(int num)
{
    this->numOfAgents = num;
}

int OpenSteer::CUDAPlugIn::getNumberOfAgents(void)
{
    return this->numOfAgents;
}

float3* OpenSteer::CUDAPlugIn::getSteeringVectors(void)
{
    return d_steeringVectors;
}

VehicleData* OpenSteer::CUDAPlugIn::getVehicleData(void)
{
    return d_vehicleData;
}

VehicleConst* OpenSteer::CUDAPlugIn::getVehicleConst(void)
{
    return d_vehicleConst;
}