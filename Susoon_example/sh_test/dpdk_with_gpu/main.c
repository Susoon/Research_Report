#include "dpdk.h"

int main(int argc, char ** argv)
{
//	read_handler();
	set_gpu_mem_for_dpdk();
	dpdk_handler(argc, argv);

	return 0;
}
