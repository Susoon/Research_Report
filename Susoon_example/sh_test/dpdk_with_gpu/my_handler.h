#if 0

#include "my_handler.h"
#include "gdnio.h"
#include "packet_man.h"
#include "common.hpp"
#include "mydrv/mydrv.h"
#include "pkts.h"

#endif

#include <stdio.h>
#include <stdlib.h>
#include <fstream>
#include <sstream>
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

int sh_pin_buffer(void);
__global__ void print_gpu(unsigned char* d_pkt_buf, int size);
void copy_to_gpu(unsigned char* buf, int size);
void set_gpu_mem_for_dpdk(void);
