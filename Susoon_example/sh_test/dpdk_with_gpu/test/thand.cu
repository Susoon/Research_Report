//#include "thand.h"
#include <cuda.h>
#include <cuda_runtime_api.h>
#include <stdio.h>
#include <pthread.h>

#define CYCLE 1024 * 1024 * 1024
#define THREAD 1

int * count;

__global__ void Check_gpu(int * count)
{
#if 1
		__syncthreads();
	while(*count < CYCLE)
	{
		//printf("\n\n\n\n\n\n");
		//printf("____________GPU function is called______________\n");
		__syncthreads();
		atomicAdd(count, 1);
		//printf("\n\n\n\n\n\n");
	}
	printf("_______________Out of GPU fct loop________________\n");
#else
		printf("____________GPU function is called______________\n");
#endif
}

extern "C"
void Check(void)
{
	printf("Check!!\n");
	Check_gpu<<<1,512>>>(count);
	cudaDeviceSynchronize();
	printf("End Check!!!!!!!!!\n");
}

extern "C"
void cudasynch(void)
{
	cudaDeviceSynchronize();
}

#if THREAD
void* get_cnt(void * data)
{
	int prev = 0;
	printf("In get_cnt!!!!!!!!!!!!!!!\n");
	while(1)
	{
		int ret = 0;
		cudaMemcpy(&ret, count, sizeof(int), cudaMemcpyDeviceToHost);
		if(prev != ret)
		{
			printf("In CPU : count = %d\n", ret);
			prev = ret;
		}
	}
}

#else

void get_cnt(void)
{
	int j = 0;
	printf("In get_cnt!!!!!!!!!!!!!!!\n");
	while(j < 100)
	{
		int ret = 0, tmp;
		cudaMemcpy(&ret, count, sizeof(int), cudaMemcpyDeviceToHost);
		printf("In CPU : count = %d\n", ret);
		j++;
	}
}

#endif

int main(void)
{
	pthread_t thread;

	cudaMalloc((void**)&count, sizeof(int));
	cudaMemset(count, 0, sizeof(int));

	printf("___1____\n");
#if THREAD
	pthread_create(&thread, NULL, get_cnt, NULL);
	Check();
	printf("___2____\n");
#else
	Check();
	get_cnt();
	printf("___2____\n");
#endif
	cudaDeviceSynchronize();
	printf("___3____\n");
	return 0;
}
