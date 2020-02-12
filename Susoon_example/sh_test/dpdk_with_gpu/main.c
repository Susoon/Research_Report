#include "dpdk.h"

extern void read_handler(void);

int main(int argc, char ** argv)
{
	//read_handler();
	dpdk_handler(argc, argv);

	return 0;
}
