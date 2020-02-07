SRC_DIR := $(shell pwd)/src
INC_DIR := $(shell pwd)/include
LIB_DIR := $(shell pwd)/lib
INC = -I$(shell pwd)/include


CUDA ?= /usr/local/cuda-10.2
CUDA_LIBPATH := -L$(CUDA)/lib64 -L$(CUDA)/lib -L/usr/lib/nvidia
CUDA_INC := -I$(CUDA)/include

include $(RTE_SDK)/mk/rte.vars.mk

OBJ_FILE := sh_handler.o dpdk.o main.o

PKGCONF = pkg-config

ifeq ($(shell pkg-config --exists libdpdk && echo 0),0)

PC_FILE := $(shell $(PKGCONF) --path libdpdk 2>/dev/null)
CFLAGS=-O3 $(shell $(PKGCONF) --cflags libdpdk)
LDFLAGS_SHARED = $(shell $(PKGCONF) --libs libdpdk)

all: dpdk_gpu_test

dpdk_gpu_test: $(OBJ_FILE)
	g++ -o $@ -pthread $(OBJ_FILE) $(CUDA_LIBPATH) $(CUDA_INC) $(INC) $(CFLAGS) $(LDFLAGS) $(LDFLAGS_SHARED) -lnuma -lcuda -lcudart -ldl
	mv *.o $(LIB_DIR)

sh_handler.o: $(SRC_DIR)/sh_handler.cu
	nvcc $(CUDA_LIBPATH) $(CUDA_INC) --gpu-architecture=sm_60 --device-c $(SRC_DIR)/sh_handler.cu $(INC)

dpdk.o: $(SRC_DIR)/dpdk.c
	gcc $(CUDA_LIBPATH) $(CUDA_INC) $(INC) $(CFLAGS) -c $(SRC_DIR)/dpdk.c -o $@ $(LDFLAGS) $(LDFLAGS_SHARED)

main.o: main.c
	gcc $(CUDA_LIBPATH) $(CUDA_INC) $(INC) $(CFLAGS) -c main.c -o $@ $(LDFLAGS) $(LDFLAGS_SHARED)

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
