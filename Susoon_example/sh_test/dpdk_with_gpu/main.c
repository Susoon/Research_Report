#include "dpdk.h"

int main(int argc, char ** argv)
{
	set_gpu_mem_for_dpdk();
	gpu_monitor();
	dpdk_handler(argc, argv);

	return 0;
}
