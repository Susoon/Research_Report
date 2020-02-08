SRC_DIR := $(shell pwd)/src
INC_DIR := $(shell pwd)/include
LIB_DIR := $(shell pwd)/lib
INC = -I$(shell pwd)/include


CUDA ?= /usr/local/cuda-10.2
CUDA_LIBPATH := -L$(CUDA)/lib64 -L$(CUDA)/lib -L/usr/lib/nvidia
CUDA_INC := -I$(CUDA)/include

include $(RTE_SDK)/mk/rte.vars.mk

OBJ_FILE := main.o sh_handler.o dpdk.o 

PKGCONF = pkg-config

ifeq ($(shell pkg-config --exists libdpdk && echo 0),0)

PC_FILE := $(shell $(PKGCONF) --path libdpdk 2>/dev/null)
CFLAGS=-O3 $(shell $(PKGCONF) --cflags libdpdk)
LDFLAGS_SHARED = $(shell $(PKGCONF) --libs libdpdk)

all: dpdk_gpu_test


#all compile
dpdk_gpu_test: sh_handler.o dpdk.o main.o
	g++ -o $@ main.o sh_handler.o dpdk.o $(INC) $(CUDA_LIBPATH)	 \
		$(CUDA_INC) $(INC) -lcuda -lcudart -pthread		 \
		$(CFLAGS) $(LDFLAGS) $(LDFLAGS_SHARED) -ldl $(INC) -lnuma
	mv *.o $(LIB_DIR)


#sh_handler compile
sh_handler.o: $(SRC_DIR)/sh_handler.cu
	nvcc --gpu-architecture=sm_60 --device-c $^ -o $@ $(INC) $(CUDA_LIBPATH) $(CUDA_INC) -ldl 

#dpdk compile
dpdk.o: $(SRC_DIR)/dpdk.c
	gcc -c $^ -o $@ $(INC) $(CUDA_LIBPATH) $(CUDA_INC) $(CFLAGS) $(LDFLAGS) $(LDFLAGS_SHARED)-lnuma -lcuda -lcudart -ldl

#main compile
main.o: main.c
	gcc -o $@ -c $^ $(INC) $(CUDA_LIBPATH) $(CUDA_INC) -lcudart -lcuda -ldl -pthread $(CFLAGS) $(LDFLAGS) $(LDFLAGS_SHARED) -ldl



clean:
	rm $(LIB_DIR)/*.o *.o dpdk_gpu_test 

else

ifeq ($(RTE_SDK),)
$(error "Please define RTE_SDK environment variable ")
endif

# Default target, detect a build directory, by looking for a path with a .config
RTE_TARGET ?= $(notdir $(abspath $(dir $(firstword $(wildcard $(RTE_SDK)/*/.config)))))


include $(RTE_SDK)/mk/rte.app.mk

include $(RTE_SDK)/mk/rte.subdir.mk

endif
