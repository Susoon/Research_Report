#include "my_handler.h"

#define PKT_BUF_SIZE 4 * 1024 * 1024 //4MB
#define PKT_SIZE 64

unsigned char* d_pkt_buffer;

static int idx;

/*
__device__ uint8_t tmp_pkt[60] = {\
0x00, 0x1b, 0x21, 0xbc, 0x11, 0x52, 0xa0, 0x36, 0x9f, 0x03, 0x13, 0x86, 0x08, 0x00, 0x45, 0x10,\
0x00, 0x2e, 0x00, 0x00, 0x40, 0x00, 0x40, 0x11, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x03, 0x0a, 0x00,\
0x00, 0x04, 0x04, 0xd2, 0x04, 0xd2, 0x00, 0x1a, 0x2c, 0xd6, 0x6f, 0x98, 0x26, 0x35, 0x02, 0xc9,\
0x83, 0xd7, 0x8b, 0xc3, 0xf7, 0xb5, 0x20, 0x8d, 0x48, 0x8d, 0xc0, 0x36};
*/

/* Suhwan pinning buffer 02/06 */
int sh_pin_buffer(void)
{
	int ret = 0;
	int retcode;
	
	struct rte_mbuf *buf[DEFAULT_PKT_BURST];

	retcode = cudaHostAlloc(buf,sizeof(struct rte_mbuf *) * DEFAULT_PKT_BURST, cudaHostAllocDefault);
	if(retcode == cudaErrorMemoryAllocation)
	{
		ret = errno;
		printf("cudaHostAlloc error (errno=%d)\n", ret);
	}

    return ret;
}

__global__ void print_gpu(unsigned char* d_pkt_buf, int size)
{
	int i;
	printf("[GPU]:\n");
	for(i = 0; i < size; i++)
		printf("%02x ", d_pkt_buf[i]);
	printf("\n");
}


extern "C"
void copy_to_gpu(unsigned char* buf, int size)
{
	unsigned char *d_pkt_buf;
	cudaMalloc((void**)&d_pkt_buf, sizeof(unsigned char)*1500);
	printf("____1__________copy_to_gpu____\n");
	cudaMemcpy(d_pkt_buffer+(512*0x1000)+(0x1000*idx), buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);
	print_gpu<<<1,1>>>(d_pkt_buffer+(512*0x1000)+(0x1000*idx), sizeof(unsigned char)*size);
	idx++;
	if(idx == 512)
		idx = 0;
	printf("____2__________copy_to_gpu____\n");
}

extern "C"
void set_gpu_mem_for_dpdk(void)
{
	size_t _pkt_buffer_size = PKT_BUF_SIZE;// 4MB, for rx,tx ring
	size_t pkt_buffer_size = (_pkt_buffer_size + GPU_PAGE_SIZE - 1) & GPU_PAGE_MASK;
	
	ASSERTRT(cudaMalloc((void**)&d_pkt_buffer, pkt_buffer_size));
	ASSERTRT(cudaMemset(d_pkt_buffer, 0, pkt_buffer_size));

	START_GRN
	printf("[Done]____GPU mem set for dpdk__\n");
	END
}
