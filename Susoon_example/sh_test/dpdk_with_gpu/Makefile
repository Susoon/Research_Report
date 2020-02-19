include $(RTE_SDK)/mk/rte.vars.mk

SRC_DIR := $(shell pwd)/src
INC_DIR := $(shell pwd)/include
LIB_DIR := $(shell pwd)/lib
INC = -I$(shell pwd)/include

APP = dpdk.o
SRCS-y := $(SRC_DIR)/dpdk.c

CUDA ?= /usr/local/cuda-10.2
CUDA_LIBPATH := -L$(CUDA)/lib64 -L$(CUDA)/lib -L/usr/lib64/nvidia -L/usr/lib/nvidia
CUDA_INC := -I$(CUDA)/include 

SMV = 30
PKGCONF = pkg-config

ifeq ($(shell pkg-config --exists libdpdk && echo 0),0)

PC_FILE := $(shell $(PKGCONF) --path libdpdk 2>/dev/null)
CFLAGS = -O3 $(shell $(PKGCONF) --cflags libdpdk)
LDFLAGS_SHARED = $(shell $(PKGCONF) --libs libdpdk)

all: dpdk_gpu_test

#all compile
dpdk_gpu_test: sh_handler.o dpdk.o main.o
	g++ -o $@ -m64 -pthread\
 -I/home/susoon/work/dpdk-stable-18.11.2/lib/librte_eal/linux/eal/include\
  -march=native -DRTE_MACHINE_CPUFLAG_SSE -DRTE_MACHINE_CPUFLAG_SSE2\
 -DRTE_MACHINE_CPUFLAG_SSE3 -DRTE_MACHINE_CPUFLAG_SSSE3 -DRTE_MACHINE_CPUFLAG_SSE4_1\
 -DRTE_MACHINE_CPUFLAG_SSE4_2 -DRTE_MACHINE_CPUFLAG_AES\
 -DRTE_MACHINE_CPUFLAG_PCLMULQDQ -DRTE_MACHINE_CPUFLAG_AVX\
 -DRTE_MACHINE_CPUFLAG_RDRAND -DRTE_MACHINE_CPUFLAG_RDSEED\
 -DRTE_MACHINE_CPUFLAG_FSGSBASE -DRTE_MACHINE_CPUFLAG_F16C\
 -DRTE_MACHINE_CPUFLAG_AVX2\
  -I/home/susoon/work/Research_Report/Susoon_example/sh_test/dpdk_with_gpu/build/include\
 -DRTE_USE_FUNCTION_VERSIONING\
 -I/home/susoon/work/dpdk-stable-18.11.2/x86_64-native-linuxapp-gcc/include\
 -include /home/susoon/work/dpdk-stable-18.11.2/x86_64-native-linuxapp-gcc/include/rte_config.h\
 -D_GNU_SOURCE $^ $(CUDA_LIBPATH) $(CUDA_INC) $(INC)\
 -L/usr/local/cuda/lib64 -lcudart -lcuda\
 -L/home/susoon/work/dpdk-stable-18.11.2/x86_64-native-linuxapp-gcc/lib\
 -Wl,-lrte_flow_classify -Wl,--whole-archive -Wl,-lrte_pipeline\
 -Wl,--no-whole-archive -Wl,--whole-archive -Wl,-lrte_table\
 -Wl,--no-whole-archive -Wl,--whole-archive -Wl,-lrte_port\
 -Wl,--no-whole-archive -Wl,-lrte_pdump -Wl,-lrte_distributor\
 -Wl,-lrte_ip_frag -Wl,-lrte_meter\
 -Wl,-lrte_lpm -Wl,-lrte_acl -Wl,-lrte_jobstats -Wl,-lrte_metrics\
 -Wl,-lrte_bitratestats -Wl,-lrte_latencystats -Wl,-lrte_power\
 -Wl,-lrte_efd -Wl,-lrte_bpf -Wl,--whole-archive\
 -Wl,-lrte_cfgfile -Wl,-lrte_gro -Wl,-lrte_gso -Wl,-lrte_hash\
 -Wl,-lrte_member -Wl,-lrte_vhost -Wl,-lrte_kvargs -Wl,-lrte_mbuf\
 -Wl,-lrte_net -Wl,-lrte_ethdev -Wl,-lrte_bbdev -Wl,-lrte_cryptodev\
 -Wl,-lrte_security -Wl,-lrte_compressdev -Wl,-lrte_eventdev -Wl,-lrte_rawdev\
 -Wl,-lrte_timer -Wl,-lrte_mempool -Wl,-lrte_mempool_ring\
 -Wl,-lrte_ring -Wl,-lrte_pci -Wl,-lrte_eal\
 -Wl,-lrte_cmdline -Wl,-lrte_reorder -Wl,-lrte_sched -Wl,-lrte_kni\
 -Wl,-lrte_common_cpt -Wl,-lrte_common_octeontx\
 -Wl,-lrte_common_dpaax -Wl,-lrte_bus_pci -Wl,-lrte_bus_vdev -Wl,-lrte_bus_dpaa\
 -Wl,-lrte_bus_fslmc -Wl,-lrte_mempool_bucket -Wl,-lrte_mempool_stack\
 -Wl,-lrte_mempool_dpaa -Wl,-lrte_mempool_dpaa2 -Wl,-lrte_pmd_af_packet\
 -Wl,-lrte_pmd_ark -Wl,-lrte_pmd_atlantic -Wl,-lrte_pmd_avp -Wl,-lrte_pmd_axgbe\
 -Wl,-lrte_pmd_bnxt -Wl,-lrte_pmd_bond -Wl,-lrte_pmd_cxgbe -Wl,-lrte_pmd_dpaa\
 -Wl,-lrte_pmd_dpaa2 -Wl,-lrte_pmd_e1000 -Wl,-lrte_pmd_ena -Wl,-lrte_pmd_enetc\
 -Wl,-lrte_pmd_enic -Wl,-lrte_pmd_fm10k -Wl,-lrte_pmd_failsafe\
 -Wl,-lrte_pmd_i40e -Wl,-lrte_pmd_ixgbe -Wl,-lrte_pmd_kni -Wl,-lrte_pmd_lio\
 -Wl,-lrte_pmd_nfp -Wl,-lrte_pmd_null -Wl,-lrte_pmd_qede\
 -Wl,-lrte_pmd_ring -Wl,-lrte_pmd_softnic -Wl,-lrte_pmd_sfc_efx -Wl,-lrte_pmd_tap\
 -Wl,-lrte_pmd_thunderx_nicvf -Wl,-lrte_pmd_vdev_netvsc -Wl,-lrte_pmd_virtio\
 -Wl,-lrte_pmd_vhost -Wl,-lrte_pmd_ifc -Wl,-lrte_pmd_vmxnet3_uio -Wl,-lrte_bus_vmbus\
 -Wl,-lrte_pmd_netvsc -Wl,-lrte_pmd_bbdev_null\
 -Wl,-lrte_pmd_null_crypto\
 -Wl,-lrte_pmd_octeontx_crypto\
 -Wl,-lrte_pmd_crypto_scheduler -Wl,-lrte_pmd_dpaa2_sec -Wl,-lrte_pmd_dpaa_sec\
 -Wl,-lrte_pmd_caam_jr -Wl,-lrte_pmd_virtio_crypto -Wl,-lrte_pmd_octeontx_zip\
 -Wl,-lrte_pmd_qat -Wl,-lrte_pmd_skeleton_event -Wl,-lrte_pmd_sw_event\
 -Wl,-lrte_pmd_dsw_event -Wl,-lrte_pmd_octeontx_ssovf -Wl,-lrte_pmd_dpaa_event\
 -Wl,-lrte_pmd_dpaa2_event -Wl,-lrte_mempool_octeontx -Wl,-lrte_pmd_octeontx\
 -Wl,-lrte_pmd_opdl_event -Wl,-lrte_bus_ifpga\
 -Wl,--no-whole-archive -Wl,-lrt -Wl,-lm -Wl,-lnuma -Wl,-ldl -Wl,-export-dynamic\
 -L/home/susoon/work/Research_Report/Susoon_examples/sh_test/dpdk_with_gpu/build/lib\
 -L/home/susoon/work/dpdk-stable-18.11.2/x86_64-native-linuxapp-gcc/lib\
 -Wl,--as-needed -Wl,-Map=dtest.map -Wl,--cref	
	mv *.o $(LIB_DIR)

#sh_handler compile
sh_handler.o: $(SRC_DIR)/sh_handler.cu
	nvcc --gpu-architecture=sm_$(SMV) -c $^ $(INC) 

#dpdk compile
$(APP): $(SRC_DIR)/dpdk.c
	gcc -Wp,-MD,./.dpdk.o.d.tmp -m64 -pthread\
 -I/home/susoon/work/dpdk-stable-18.11.2/lib/librte_eal/linux/eal/include\
  -march=native -DRTE_MACHINE_CPUFLAG_SSE -DRTE_MACHINE_CPUFLAG_SSE2\
 -DRTE_MACHINE_CPUFLAG_SSE3 -DRTE_MACHINE_CPUFLAG_SSSE3\
 -DRTE_MACHINE_CPUFLAG_SSE4_1 -DRTE_MACHINE_CPUFLAG_SSE4_2\
 -DRTE_MACHINE_CPUFLAG_AES -DRTE_MACHINE_CPUFLAG_PCLMULQDQ\
 -DRTE_MACHINE_CPUFLAG_AVX -DRTE_MACHINE_CPUFLAG_RDRAND\
 -DRTE_MACHINE_CPUFLAG_RDSEED -DRTE_MACHINE_CPUFLAG_FSGSBASE\
 -DRTE_MACHINE_CPUFLAG_F16C -DRTE_MACHINE_CPUFLAG_AVX2\
  -I/home/susoon/work/Research_Report/Susoon_example/sh_test/dpdk_with_gpu/build/include\
 -DRTE_USE_FUNCTION_VERSIONING\
 -I/home/susoon/work/dpdk-stable-18.11.2/x86_64-native-linuxapp-gcc/include\
 -include /home/susoon/work/dpdk-stable-18.11.2/x86_64-native-linuxapp-gcc/include/rte_config.h\
 -D_GNU_SOURCE -o $@ -c $^ $(INC) $(CUDA_LIB_PATH) $(CUDA_INC)

#main compile
main.o: main.c
	gcc -o $@ -c $^ $(INC) $(CUDA_LIBPATH) $(CUDA_INC) $(CFLAGS) $(LDFLAGS) $(LDFLAGS_SHARED) -lcudart -lcuda -lcudadevrt -ldl -pthread -lnuma


clean:
	rm $(LIB_DIR)/*.o dpdk_gpu_test 

else

ifeq ($(RTE_SDK),)
$(error "Please define RTE_SDK environment variable ")
endif

# Default target, detect a build directory, by looking for a path with a .config
RTE_TARGET ?= $(notdir $(abspath $(dir $(firstword $(wildcard $(RTE_SDK)/*/.config)))))

CFLAGS += -O3 $(shell $(PKGCONF) --cflags libdpdk)
LDFLAGS += $(shell $(PKGCONF) --libs libdpdk)

include $(RTE_SDK)/mk/rte.subdir.mk
include $(RTE_SDK)/mk/rte.extapp.mk
include $(RTE_SDK)/mk/rte.app.mk

endif
