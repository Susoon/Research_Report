//#include "thand.h"
#include <cuda.h>
#include <cuda_runtime_api.h>
#include <stdio.h>

__global__ void Check_gpu(void)
{
#if 0
	while(true)
	{
		//printf("\n\n\n\n\n\n");
		printf("____________GPU function is called______________\n");
		//printf("\n\n\n\n\n\n");
	}
#else
		printf("____________GPU function is called______________\n");
#endif
}

extern "C"
void Check(void)
{
	printf("Check!!\n");
	Check_gpu<<<1,1>>>();
}

extern "C"
void cudasynch(void)
{
	cudaDeviceSynchronize();
}

int main(void)
{
	printf("___1____\n");
	Check_gpu<<<1,1>>>();
	printf("___2____\n");
	cudaDeviceSynchronize();
	printf("___3____\n");
	return 0;
}
