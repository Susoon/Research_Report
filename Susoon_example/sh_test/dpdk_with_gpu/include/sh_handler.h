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
#include <sys/time.h>
#include <fcntl.h>
#include <errno.h>
#include <asm/types.h>
#include <time.h>

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

#define RX_NB 32

#define PKT_SIZE 1514
#define PKT_BATCH (1024 + RX_NB)
// 64 -> 512, 1024 * 32
// 128 -> 256, 1024 * 16
// 256 -> 128, 1024 * 8
// 512 -> 64, 4096
// 1024 -> 32, 2048
// 1514 -> 32, 1514
#define PKT_BATCH_SIZE (PKT_SIZE * PKT_BATCH)

#define ONE_SEC 1000 * 1000 * 1000

#endif
