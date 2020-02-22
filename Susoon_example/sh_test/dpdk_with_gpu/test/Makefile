CUDA ?= /usr/local/cuda-10.2
CUDA_LIBPATH := -L$(CUDA)/lib64 -L$(CUDA)/lib -L/usr/lib64/nvidia -L/usr/lib/nvidia
CUDA_INC := -I$(CUDA)/include 

SMV = 30

all: check

check: thand.cu
	nvcc --gpu-architecture=sm_$(SMV) -o $@ $^ $(CUDA_LIBPATH) $(CUDA_INC) -lcudart -lcuda 

clean:
	rm check
