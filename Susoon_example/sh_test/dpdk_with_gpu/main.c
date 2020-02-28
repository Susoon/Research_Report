#include "dpdk.h"

void * monitor(void * data)
{
	gpu_monitor_loop();
}

int main(int argc, char ** argv)
{
	pthread_t thread;

	set_gpu_mem_for_dpdk();
	
	//pthread_create(&thread, NULL, monitor, NULL);
	dpdk_handler(argc, argv);
	

	return 0;
}
