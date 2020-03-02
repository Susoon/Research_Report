#include "dpdk.h"

void * monitor(void * data)
{
//	unsigned long core_mask = 2;

//	pthread_setaffinity_np(pthread_self(), sizeof(core_mask), &core_mask);
	gpu_monitor_loop();
}

int main(int argc, char ** argv)
{
	pthread_t thread;
	
	set_gpu_mem_for_dpdk();
	
	pthread_create(&thread, NULL, monitor, NULL);
	dpdk_handler(argc, argv);
	

	return 0;
}
