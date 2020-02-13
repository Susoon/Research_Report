SRC_DIR := $(shell pwd)/src
INC_DIR := $(shell pwd)/include
LIB_DIR := $(shell pwd)/lib
INC = -I$(shell pwd)/include

CUDA ?= /usr/local/cuda-10.2
CUDA_LIBPATH := -L$(CUDA)/lib64 -L$(CUDA)/lib -L/usr/lib64/nvidia -L/usr/lib/nvidia
CUDA_INC := -I$(CUDA)/include 

SMV = 35

include $(RTE_SDK)/mk/rte.vars.mk

PKGCONF = pkg-config

ifeq ($(shell pkg-config --exists libdpdk && echo 0),0)

PC_FILE := $(shell $(PKGCONF) --path libdpdk 2>/dev/null)
CFLAGS = -O3 $(shell $(PKGCONF) --cflags libdpdk)
LDFLAGS_SHARED = $(shell $(PKGCONF) --libs libdpdk)
18FLAG = -L/home/suhwan/work/dpdk-stable-18.11.2/x86_64-native-linuxapp-gcc/lib

all: dpdk_gpu_test

#all compile
dpdk_gpu_test: sh_handler.o dpdk.o main.o
	g++ -o $@ $^ -m64 $(CUDA_LIBPATH)\
	 	$(CUDA_INC)	$(INC) -pthread\
	 	$(CFLAGS) $(18FLAG)	$(LDFLAGS) $(LDFLAGS_SHARED)\
	 	-lcudart -lcuda	-lcudadevrt -ldl -lnuma 
	mv *.o $(LIB_DIR)

#sh_handler compile
sh_handler.o: $(SRC_DIR)/sh_handler.cu
	nvcc --gpu-architecture=sm_$(SMV) -c $^ $(INC) 

#dlink compile
dlink.o: sh_handler.o
	nvcc --gpu-architecture=sm_$(SMV) -dlink $^ -o $@ 
	

#dpdk compile
dpdk.o: $(SRC_DIR)/dpdk.c
	gcc $(CFLAGS) -c $^ -o $@ $(INC) $(LDFLAGS) $(LDFLAGS_SHARED) $(CUDA_LIBPATH) $(CUDA_INC) -ldl -lpthread -lnuma -lcuda -lcudart

#main compile
main.o: main.c
	gcc -o $@ -c $^ $(INC) $(CUDA_LIBPATH) $(CUDA_INC) $(CFLAGS) $(LDFLAGS) $(LDFLAGS_SHARED) -lcudart -lcuda -lcudadevrt -ldl -pthread -lnuma


clean:
	rm $(LIB_DIR)/*.o *.o dpdk_gpu_test 

else

ifeq ($(RTE_SDK),)
$(error "Please define RTE_SDK environment variable ")
endif

# Default target, detect a build directory, by looking for a path with a .config
RTE_TARGET ?= $(notdir $(abspath $(dir $(firstword $(wildcard $(RTE_SDK)/*/.config)))))

CFLAGS += -O3 $(shell $(PKGCONF) --cflags libdpdk)
#LDFLAGS += $(shell $(PKGCONF) --libs libdpdk)
LDFLAGS = -L/home/suhwan/work/dpdk-stable-18.11.2/lib -lrte_bpf -lrte_flow_classify -lrte_pipeline -lrte_table -lrte_port -lrte_fib -lrte_ipsec -lrte_vhost -lrte_stack -lrte_security -lrte_sched -lrte_reorder -lrte_rib -lrte_rcu -lrte_rawdev -lrte_pdump -lrte_power -lrte_member -lrte_lpm -lrte_latencystats -lrte_kni -lrte_jobstats -lrte_ip_frag -lrte_gso -lrte_gro -lrte_eventdev -lrte_efd -lrte_distributor -lrte_cryptodev -lrte_compressdev -lrte_cfgfile -lrte_bitratestats -lrte_bbdev -lrte_acl -lrte_timer -lrte_hash -lrte_metrics -lrte_cmdline -lrte_pci -lrte_ethdev -lrte_meter -lrte_net -lrte_mbuf -lrte_mempool -lrte_ring -lrte_eal -lrte_kvargs

include $(RTE_SDK)/mk/rte.subdir.mk
include $(RTE_SDK)/mk/rte.extapp.mk
include $(RTE_SDK)/mk/rte.app.mk

endif
