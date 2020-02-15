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

SMV = 35
PKGCONF = pkg-config

ifeq ($(shell pkg-config --exists libdpdk && echo 0),0)

PC_FILE := $(shell $(PKGCONF) --path libdpdk 2>/dev/null)
CFLAGS = -O3 $(shell $(PKGCONF) --cflags libdpdk)
LDFLAGS_SHARED = $(shell $(PKGCONF) --libs libdpdk)

all: dpdk_gpu_test

#all compile
dpdk_gpu_test: sh_handler.o dpdk.o main.o
	g++ -o $@ $^ -m64 $(CUDA_LIBPATH)\
	 	$(CUDA_INC)	$(INC) -pthread\
	 	$(CFLAGS)	$(LDFLAGS) $(LDFLAGS_SHARED)\
	 	-lcudart -lcuda	-lcudadevrt -ldl -lnuma 
	mv *.o $(LIB_DIR)

#sh_handler compile
sh_handler.o: $(SRC_DIR)/sh_handler.cu
	nvcc --gpu-architecture=sm_$(SMV) -c $^ $(INC) 

#dlink compile
dlink.o: sh_handler.o
	nvcc --gpu-architecture=sm_$(SMV) -dlink $^ -o $@ 
	

#dpdk compile
$(APP): $(SRC_DIR)/dpdk.c
	gcc $(CFLAGS) -c $^ -o $@ $(INC) $(LDFLAGS) $(LDFLAGS_SHARED) $(CUDA_LIBPATH) $(CUDA_INC)
	#gcc $(CFLAGS) -c $^ -o $@ $(INC) $(LDFLAGS) $(LDFLAGS_SHARED) $(CUDA_LIBPATH) $(CUDA_INC) -ldl -lpthread -lnuma -lcuda -lcudart

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
LDFLAGS += $(shell $(PKGCONF) --libs libdpdk)

include $(RTE_SDK)/mk/rte.subdir.mk
include $(RTE_SDK)/mk/rte.extapp.mk
include $(RTE_SDK)/mk/rte.app.mk

endif
