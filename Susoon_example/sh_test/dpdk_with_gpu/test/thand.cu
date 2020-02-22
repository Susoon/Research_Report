//#include "thand.h"
#include <cuda.h>
#include <cuda_runtime_api.h>
#include <stdio.h>
#include <pthread.h>

int * count;

__global__ void Check_gpu(int * count)
{
#if 1
	while(true)
	{
		//printf("\n\n\n\n\n\n");
		//printf("____________GPU function is called______________\n");
		atomicAdd(count, 1);
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
	Check_gpu<<<1,512>>>(count);
}

extern "C"
void cudasynch(void)
{
	cudaDeviceSynchronize();
}

void* get_cnt(void * data)
{
	int j = 0;
	while(j > -1)
	{
		int ret = 0, tmp;
		cudaMemcpy(&ret, count, sizeof(int), cudaMemcpyDeviceToHost);
		printf("In CPU : count = %d\n", ret);
		j++;
	}
}

int main(void)
{
	pthread_t thread;

	cudaMalloc((void**)&count, sizeof(int));
	cudaMemset(count, 0, sizeof(int));
	printf("___1____\n");
	Check();
	printf("___2____\n");
	pthread_create(&thread, NULL, get_cnt, NULL);
	//get_cnt();
	cudaDeviceSynchronize();
	printf("___3____\n");
	return 0;
}
