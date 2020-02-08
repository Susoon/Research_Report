#include "dpdk.h"
#include "sh_handler.h"

extern int sh_pin_buffer(void);
extern void set_gpu_mem_for_dpdk(void);
extern void read_loop();

int main(int argc, char ** argv)
{
	int err;
	set_gpu_mem_for_dpdk();
	err = sh_pin_buffer();
	read_loop();
	dpdk_handler(argc, argv);

	return 0;
}
