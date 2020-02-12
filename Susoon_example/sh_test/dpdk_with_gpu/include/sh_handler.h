#ifndef __SH_HANDLER_H_
#define __SH_HANDLER_H_

#include <stdio.h>
#include <stdlib.h>
#include <memory.h>
#include <cuda_runtime_api.h>
#include <cuda.h>
#include <unistd.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>
#include <asm/types.h>

#define ASSERT(x)													\
	do														\
	{														\
		if (!(x))												\
		{													\
			fprintf(stdout, "\033[1;31mAssertion \"%s\" failed at %s:%d\033[0m\n", #x, __FILE__, __LINE__); \
			/*exit(EXIT_FAILURE);*/										\
		}													\
	} while (0)

#define ASSERTRT(stmt)					\
	do 						\
	{ 						\
		cudaError_t result = (stmt); 		\
		ASSERT(cudaSuccess == result);     	\
	} while (0)

#define GPU_PAGE_SHIFT 16
#define GPU_PAGE_SIZE (1UL << GPU_PAGE_SHIFT)
#define GPU_PAGE_MASK (~(GPU_PAGE_SIZE - 1))

#define START_RED printf("\033[1;31m");
#define START_GRN printf("\033[1;32m");
#define START_YLW printf("\033[1;33m");
#define START_BLU printf("\033[1;34m");
#define END printf("\033[0m"); 


__global__ void print_gpu(unsigned char* d_pkt_buf);
__global__ void print_pinned_buffer(unsigned char* d_pkt_buf);
__global__ void read_loop(unsigned char* d_pkt_buf);

#endif
