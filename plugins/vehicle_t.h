#ifndef _VEHICE_T_H_
#define _VEHICE_T_H_

#include <cuda_runtime.h>

#define NUM_OF_AGENTS 4096


typedef struct vehicle {    
    float2 position[NUM_OF_AGENTS];
    float2 velocity[NUM_OF_AGENTS];
    
    float2 smoothedAcceleration[NUM_OF_AGENTS];
    float2 side[NUM_OF_AGENTS];
    
} vehicle_t;

#endif // _VEHICE_T_H_