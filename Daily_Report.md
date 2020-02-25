# Daily Report for DPDK

## 02/24 현재상황

* gpu에서 infinite loop를 돌려서 그 외의 code에서 gpu에 어떤 명령도 걸 수 없음
* 그래서 gpu에서 loop를 돌리는 게 아니라 cpu에서 loop을 돌고 그 내부에 gpu를 check하는 코드를 넣음



<center> gpu monitoring code </center>

![Alt_text](image/02.24_gpu_monitor_code.JPG)

* gpu_monitor가 packet buffer를 check하고 atomicAdd로 count를 올려주는 함수
* gpu_monitor_loop가 cpu에서 loop를 돌면서 gpu_monitor를 호출해 packet buffer를 check하고 atomicAdd로 count를 올려줌

---

### pps가 낮게 나오는 것 수정 전



<center> execution result </center>

![Alt_text](image/02.24_monitor_in_cpu.JPG)

* 실행 결과를 보면 rx_pkt_cnt가 rx_cur_pkt에 잘 복사되어 값이 나오는 것을 알 수 있다
* 5.8Mpps정도 나오는데 이 값이 복사는 잘 된 거 같지만 값 자체가 유의미한지는 의심된다.
  * 12번째를 보면 갑자기 1.7Mpps가 나온다
  * send하는 쪽은 13.8Mpps정도로 찍어주는데 5.8Mpps밖에 안나오는 건 너무 적다
* 수정함

---

### pps가 낮게 나오는 것 수정 후 & if문 condition 수정 전



<center> gpu test success </center>

![Alt_text](image/02.24_gpu_test_success.JPG)

* macro를 잘못 넣어줘서 생긴 문제여서 macro를 알맞게 넣어줌
* send하는 쪽에서 pps가 12.9Mpps 정도 나옴
* 보내는 만큼 거의 다 받음
* 7번째를 보면 가끔씩 1/3정도로 떨어지는 때가 있음
* 5번에 한번씩 저렇게 떨어짐
* 저게 copy에 대한 overhead인 부분인 거 같음

---

### if문 condition 수정 후 & memcpy 수정 전



<center> execution result </center>

![Alt_text](image/02.24_pps.JPG)

* 13.8Mpps로 send에서 보내준 만큼 나옴
* 원인은 uint64_t인 start와 end의 차가 int인 macro ONE_SEC와 비교되다보니 type conversion을 하는 과정에서 문제가 발생한 것이었음
  * 이와 관련된 test는 다음 장에
  * 수정 후 해결
* copy_to_gpu가 제대로 실행 된다면 13.8Mpps가 나올 수 없음
  * copy overhead때문에
* 추측상 dpdk.c의 buf를 structure에서 unsigned char*로 변환하는 과정에 문제가 있음



<center> buf type conversion </center>

![Alt_text](image/02.24_dpdk_ptr.JPG)

* buf는 structure 배열이고 ptr은 unsigned char 배열인데, 첫번째 줄은 buf의 packet data만 뽑아서 ptr에 대입해주는 명령이다
* 이 과정에서 buf에 저장된 모든 packet들의 data를 contiguous하게 가지는 pointer를 넘겨주는 것이 아니라, buf[0]의 packet data를 가리키는 pointer를 넘겨줌
  * 실제로 모든 packet data를 contiguous하게 저장하지 않음
* 이로 인해 첫번째 packet의 data만 제대로 copy되고 나머지 자리에는 0만 들어감



<center> copy result </center>

![Alt_text](image/02.24_copy_error.JPG)

* 두번째 packet자리가 다 0임을 확인할 수 있다
* 이 부분은 수정 필요





---

### type conversion test

* 다음은 uint64_t의 자료형을 가지는 num64와 int의 자료형을 가지는 num 간의 type conversion을 test한 것이다
* LARGE case는 2^50 + 2^30 + 2^10을 대입한 case이고,
* MID case는 2^30 + 2^10을 대입한 case,
* SMALL case는 2^10을 대입한 case이다



<center> LARGE case without any explicit type conversion </center>

![Alt_text](image/02.24_type_conversion_LARGE.JPG)



<center> MID case without any explicit type conversion </center>

![Alt_text](image/02.24_type_conversion_MID.JPG)



<center> SMALL case without any explicit type conversion </center>

![Alt_text](image/02.24_type_conversion_SMALL.JPG)

* 어떤 explicit type conversion도 없이 implicit type conversion의 결과를 보기위해 한 test의 결과이다





<center> LARGE case with explicit type conversion to int </center>

![Alt_text](image/02.24_type_conversion_LARGE_int.JPG)



<center> MID case with explicit type conversion to int</center>

![Alt_text](image/02.24_type_conversion_MID_int.JPG)



<center> SMALL case with explicit type conversion to int</center>

![Alt_text](image/02.24_type_conversion_SMALL_int.JPG)

* num64를 int로 type conversion해서 나온 결과이다





<center> LARGE case with explicit type conversion to uint64_t</center>

![Alt_text](image/02.24_type_conversion_LARGE_64.JPG)



<center> MID case with explicit type conversion to uint64_t</center>

![Alt_text](image/02.24_type_conversion_MID_64.JPG)



<center> SMALL case with explicit type conversion to uint64_t</center>

![Alt_text](image/02.24_type_conversion_SMALL_64.JPG)

* num을 uint64_t로 type conversion해서 나온 결과이다





<center> LARGE case with inequality</center>

![Alt_text](image/02.24_type_conversion_LARGE_ineq.JPG)



<center> MID case with inequality</center>

![Alt_text](image/02.24_type_conversion_MID_ineq.JPG)



<center> SMALL case with inequality</center>

![Alt_text](image/02.24_type_conversion_SMALL_ineq.JPG)

* 대소비교 test를 진행한 결과이다



* 뺄셈을 test한 결과로는 implicit type conversion은 uint64_t로 된다는 것을 알 수 있다
* 대소비교 test를 진행한 결과로는 int 범위를 넘어가는 값을 대소비교 하게되면 true, false가 잘못된 값이 나올 수 있다는 것이다.

---

### memcpy 수정 후



<center> dump in cpu </center>

![Alt_text](image/02.24_copy_success_in_cpu.JPG)



<center> copy in gpu </center>

![Alt_text](image/02.24_copy_success_in_gpu.JPG)

* gpu와 cpu에서 모두 제대로 packet이 copy 되었음을 알 수 있다



---

### packet size별 pps 확인



* packet size별로 최대 pps가 나오는 최대 batch size를 찾는 test를 진행하고 있다
* 그런데 최대 size로 키워도 속도가 떨어지지 않는다
* 최대 packet size인 1514B로 1514개를 batch로 받아 실행해보았다



<center> Packet size : 1514B, Batch size : 1514 pps </center>

![Alt_text](image/02.24_1514B_1514.JPG)

<center> gpu status </center>

![Alt_text](image/02.24_1514B_1514_gpu_status.JPG)



* GPU memory를 2GB정도 사용하면서 check를 진행하는데 속도가 정상적으로 나왔다
  * send(pkt-gen) : 8.1Mpps, receive(dpdk) : 8.1Mpps
* copy가 정상적으로 되고 있음에도 속도가 너무 잘 나온다
* copy가 진짜 정상적으로 진행되고 있는지 확인이 필요함
  * packet 받은걸 fprintf로 어딘가에 저장해서, gpu에서 copy한 packet들과 비교하는 코드를 짜서 packet 받고 비교해봐야할듯



## 02/22 현재상황

* 여전히 gpu_monitoring_loop 때문에 다른 gpu코드가 작동을 못함
* 그래서 test를 위한 코드를 따로 짜서 확인해봄



<center> thand.cu file </center>

![Alt_text](image/02.22_thand.JPG)

![Alt_text](image/02.22_thand2.JPG)

* thand.cu 파일의 코드 전문
* dpdk나 다른 기능을 빼고 gpu에서의 infinite loop와 loop내의 atomicAdd를 통한 값 변화, cpu에서 이 변한 값을 가져와 출력하는 infinite loop만 넣은 상태
* pthread로 multithread를 돌려봤지만 제대로 실행되지  않음



<center> execution </center>

![Alt_text](image/02.22_test_gpu_infinite_loop_test.JPG)

* 이런 형태로 count 값이 전혀 전달받지 못함
* cpu에서 값을 받지 못해 계속 0만 출력
* synch문제로 cudaMemcpy가 실행되지 않는 듯함



<center> dpdk_gpu_test execution </center>

![Alt_test](image/02.22_gpu_infinite_loop_test.JPG)

* dpdk_gpu_test 파일을 실행시켜 나온 결과
* 5번째까지는 packet을 gpu에 넣기 전이라 0으로 memcpy되지만 6번째에 84180992라는 값은 이전까지 count된 rx packet 수가 그 전까지 cpu에게 전달이 안 되다가 한번에 전달되어 출력된 수로 추측됨
* 이 말은 저때까지는 copy_to_gpu 내의 memcpy와 get_rx_cnt의 memcpy가 제대로 실행이 되며 gpu_monitoring_loop내의 loop도 제대로 실행이 되었다는 뜻
* 그 이후로는 30초 정도 멈춰있다가 cudaMemcpyLaunchTimeout이 발생
* gpu에 과부하가 걸리는 건지 잘 모르겠음
* packet 전송 속도를 0.001%로 해서 초당 200개 미만의 packet을 보내면 조금 더 오랫동안(20~30번 정도?) packet을 count하다가 같은 증상을 보임



## 02/21 현재상황

* gpu에서 gpu_monitoring_loop을 돌리면 다른 gpu코드가 작동을 못함
* synch 문제인 거 같음



<center> gpu monitoring loop </center>
![Alt_text](image/02.21_gpu_monitoring_loop.JPG)

* code를 위의 사진처럼 수정함
* #if 0으로 수정해 놓은 부분은 loop를 뺐을때 작동을 어떻게 하는지 보기 위함
* 찬규형의 monitoring loop을 참고함
* 두번째 #if 0 밑에 if(rx_pkt_buf[mem_index] != 0)부분이 packet buffer의 변화를 확인하는 부분
* 각 thread가 buffer에서 맡은 부분을 확인하고 밑의 atomicAdd로 packet 수를 count함
* 이를 dpdk.c가 받아감
* dpdk.c에서 thread를 하나 따로 파서 이를 확인하는 loop를 돌게 해야할 거 같음





## 02/20 현재상황

* gpu에서 시간을 재면서 packet 수를 check한 게 아니라서 다시 코드를 짬



<center> gpu monitoring loop </center>
![Alt_text](image/02.20_gpu_monitoring_loop.JPG)

* gpu에서 packet buffer를 polling 하는 loop
* 원래 의도는 copy_to_gpu를 통해 dpdk.c가 flag를 true로 바꿔주면 packet이 들어왔다는 신호로 인식하고 packet을 manipulate하면서 rx_pkt_cnt를 count해주려했음



<center> getter for rx packet count and tx packet buffer </center>
![Alt_text](image/02.20_getter_fct.JPG)

* dpdk.c 에서 위의 함수를 1초마다 불러서 gpu_monitoring_loop가 rx_pkt_cnt와 tx_pkt_buf를 채워주면 그 값을 가져가고 0으로 초기화해주는 역할을 하는 함수



* 현재 위의 두 함수 모두 제 기능을 못하는 상태
  * 원인 1)
    *  gpu_monitoring_loop가 무한루프임
    * 이 때문에 copy_to_gpu나 get_rx_cnt, get_tx_buf 같은 gpu의 resource를 필요로 하는 함수들이 무한루프에 밀려 기능을 못함(cudaErrorLaunchTimeout을 리턴함)
    * 그래서 gpu memory에 packet이 올라가지 않으니 gpu_monitoring_loop도 일을 안함
    * 위의 내용들이 반복됨
  * 원인 2)
    * dpdk.c에서 tx_pkt_buf를 받아 tx_buf라는 rte_mbuf 구조체 포인터 배열에 copy해 넣고 이를 transmitt함
    * 그 이유는 rx와 tx packet 모두 하나의 변수에 저장되면 rx가 batch를 하는 동안 tx가 packet을 덮어씌워버림
    * 이 때문에 또 다른 변수를 선언하여 copy하는 것을 택함
    * 이때 rte_mbuf 구조체에 tx_pkt_buf를 copy해 넣어야하는데 구조체의 field를 대략적으로라도 알아야함

* 위의 원인들때문에 현재 test가 불가함
* rte_mbuf는 구조체의 field만 보면 간단히 해결 가능 할 듯
* persistent loop를 고쳐야함





## 02/19 현재상황

* test가 가능한 상태로 완성
* 64byte의 packet 기준으로 512개(총 32kB)가 들어갈 수 있게 batch의 size를 정해주면 최대 속도(13.8Mpps)가 나옴
* 1514byte의 packet 기준으로 448개(총 662kB 정도)가 들어갈 수 있게 batch의 size를 정해주면 최대 속도(0.8Mpps)가 나옴



* 여러 테스트를 진행해봄
* 첫번째, print_gpu가 실행되지 않은 이유를 d_pkt_buf라는 shared memory에 계속 packet을 copy해 넣어서 print_gpu가 scheduler에게 밀려 실행되지 않은 것으로 추정하고 pinned_pkt_buf라는 전역변수에 2MB를 할당해 ring처럼 index에 따라 다른 자리에 packet을 copy해 넣어줘 shared memory 문제를 해결하려고 해봄
  * 하지만 여전히 실행되지 않음



<center> ring code </center>
![Alt_text](image/02.19_ring_code.JPG)



* 두번째, 첫번째 방법을 위한 코드가 제대로 작동하는지 확인하기 위해서 cpu memory에 buffer를 만들어서 같은 역할을 하게끔 코드를 짜서 확인해봄
  * pinned_pkt_buf를 다 0으로 초기화하고 dpdk에서 buffer를 받아와 copy해 넣은 다음 해당 부분의 위치와 index가 일치하는지 확인하기위해 해당 부분만 초록색으로 출력
  * copy해 넣은 부분을 다시 0으로 만들어서 다음 index의 test때 확인 가능하도록 해줌 
  * 잘 실행 됨



* \+ 문제 해결 
  * compile할때 sm의 버젼을 30으로 주니 정상적으로 실행됨

<center> ring check code test </center>
![Alt_text](image/02.19_handler_ring_test.JPG)

* 위의 결과물의 의미는 298번째에 packet이 잘 copy되어서 초록색으로 a0가 출력됨

<center> ring check code </center>
![Alt_text](image/02.19_ring_check_code.JPG)



* \+ dpdk의 rx rate를 확인하기 위해서 test를 해봄



<center> rx and tx rate </center>
![Alt_text](image/02.19_rx_and_tx_rate.JPG)

* 이유는 알 수 없으나 지난번 test때에 비해 1Mpps정도 오름



<center> rx rate without sending </center>
![Alt_text](image/02.19_rx_rate_without_swap.JPG)

* swap과 send  없이 실행해도 같은 Mpps를 보임
* sh_handler가 없을때 실행하면 6Mpps가 나왔었음



<center> tx rate without cuda function </center>
![Alt_text](image/02.19_rx_and_tx_rate_without_cuda_fct.JPG)

* cuda function을 주석처리했을 때 tx rate



<center> rx rate without cuda function </center>
![Alt_text](image/02.19_rx_rate_without_cuda_fct.JPG)

* recv_total로 직접 rx rate만 확인해보니 12.8Mpps로 보낸 packet수와 얼추 비슷함
  * receive는 잘 되지만 header를 swap하고 send하는 연산의 overhead 때문에 tx가 반 정도 나오는 듯
  * 이 전 결과와 비슷함



<center> rx rate without send and cuda function </center>
![Alt_text](image/02.19_rx_rate_without_swap_and_cuda_fct.JPG)

* send와 cuda function을 모두 뺀 상태의 rx rate
  * 정상적으로 나옴



* 위의 test 결과를 통해 생긴 의문점은 왜 cuda function과 send가 둘 다 있는 code와 cuda function만 있는 code의 rx rate가 동일한가 이다
  * 추측 ) cuda function과 send 모두 copy하는 연산이므로 같은 buffer를 건드리지만 서로에게 영향이 없어 더 느린쪽인 cuda function이 있을 때의 rx rate가 나온다





## 02/18 현재상황

* 실행에 문제가 없는 듯함
* 아래의 사진을 보면 gpu 상에서 dpdk_gpu_test라는 내가 만든 파일이 실행중임

<center> gpu proccess </center>
![Alt_text](image/02.18_dpdk_gpu_test_nvidia_smi.JPG)

* 하지만 여전히 화면에 출력은 안됨
* \+ cudaFree를 안해줘서 memory 사용량이 계속 늘어서 cudaFree를 써서 memory 누수를 막아줌
  * 현재는 22MB만 사용




<center> dpdk excution </center>
![Alt_text](image/02.18_dpdk_excution.JPG)

* gpu 함수를 통한 print를 제외한 다른 printf는 주석처리 한 상태
  * 즉 print_gpu라는 \_\_global\_\_함수를 제외하고는 print하는 함수의 호출이 없음
* 아무것도 뜨지 않음을 알 수 있음
  * 원인은 모르겠음....
  * gpu가 하는 출력이 다른 곳으로 되고 있지 않나하는 막연한 추측만 가지고 있음
* rx와 tx rate를 보면 속도가 줄어듬을 통해 함수 호출은 되고 있다고 추측할 수 있음



<center> rx and tx rate with call gpu function </center>
![Alt_text](image/02.18_dpdk_tx_rx_rate.JPG)



* 원래 rx가 6~7Mpps정도였으나 현재는 3Mpps정도를 보임
* 함수 호출과 출력으로 인한 overhead로 인해서 속도가 감소한 거 같음 
  * 수정 gpu 함수 호출 안해도 3Mpps정도임
  * cudaMalloc과 cudaMemcpy까지 호출 안하고 test해보니 6Mpps가 나옴
  * print_gpu는 실행이 안되는 듯 하고, cudaMalloc과 cudaMemcpy는 호출을 하면 속도가 떨어지는 것을보니 실행이 되는 듯함
* print_gpu는 실행이 안됨
* dpdk는 정상적으로 packet을 받아들이고 있고, copy_to_gpu가 gpu에 cudaMalloc으로 buffer 자리를 파주고 있지만 print_gpu만 실행이 안됨
* \_\_global\_\_함수만 실행이  안 되는 것으로 추측됨



## 02/17 현재상황

* suhwan 계정에서 compile된 걸 이용해 suhwan 계정에 있는 .dpdk.o.cmd와 .dtest.cmd 파일에서 flag들을 가져와 susoon 계정에 Makefile에 넣어주니 compile됨
* 실행시키면 port도 잘 찾음
* dpdk관련 실행은 문제 없게 됨
* 하지만 copy_to_gpu에서 d_pkt_buf를 읽어들이는 것과 print_gpu함수를 호출하는 게 안됨



<center>copy_to_gpu</center>
![Alt_text](image/02.17_copy_to_gpu.JPG)



<center> print_gpu </center>
![Alt_text](image/02.17_print_gpu.JPG)



<center>  Execution Result </center>
![Alt_text](image/02.17_output.JPG)



* 위의 캡쳐처럼 copy_to_gpu가 print_gpu를 호출하지만 출력 결과를 보면 packet도 출력이 안되고 [GPU]: 이부분도 아예 출력이 안되는 걸 보면 print_gpu가 호출이 안됨
* 그래서 copy_to_gpu에 print로 packet을 출력시키려 하니 segmentation fault error가 발생함
* cuda관련된 code가 실행되지 않고 있다고 추측 중



## 02/15 현재상황

* 서버 두 대 중 하나인 suhwan 계정에서 dpdk.c가 정상적으로 실행되는 것을 확인
* 둘의 차이는 rte.app.mk를 불러서 이를 통해 compile하는가 아니면 그냥 내가 넣어준 flag를 사용해서 compile하는 가임
* 이 차이가 port를 찾냐 못 찾냐의 차이를 주는 것 같음
* nvidia driver의 오류로 인한 linux 재설치 및 환경 세팅은 끝



## 02/13 현재상황

* suhwan 계정에서는 compile되지 않았지만 root 계정에서는 compile이 된 이유를 알아냄
  * root 계정으로 설치와 설정했던 모든 파일들이(Susun_examples 내의 파일들) 소유자가 root여서 suhwan 계정이 건들 수 없었음
  * 소유권 다 넘겨주니 excutable file을 제외하고는 모두 compile 됨
  * excutable file은 sudo가 필요함
    * library가 root 권한이어서 그런듯 함
    * library들도 소유권 변경해서 테스트해봐야함!!
  * object file들은 sudo 권한을 주면 또 compile이 안됨
    * 소유권이나 권한의 문제인 듯 하지만 확실하진 않음



<center> make error without sudo </center>
![Alt_text](image/02.13_make_error.JPG)



* 실행시에는 다음과 같은 에러가 발생

![Alt_text](image/02.13_excution_error.JPG)



* 첫번째 error는 address mapping error
  * sh_handler.cu 내에 read_handler 함수에서 device를 건드리는 function(\_\_global\_\_ or \_\_device\_\_ or cudaMalloc etc...)를 호출하면 error가 발생
  * linking 과정이나 함수 코드 내의 문제일 가능성 있음
* 두번째 error는 port를 찾을 수 없는 error
  * 이 error는 좀 더 살펴봐야함



## 02/12 현재상황

* root계정에서 suhwan 계정으로 옮겨서 컴파일을 시도 중
* pkg-config의 경로와 library의 경로가 잘못 설정되어 컴파일이 안되는 듯함
* 실제 path를 확인해보면 제대로 설정되어있음
* root계정에선 각 object file이 compile되지만 하나의 파일로 linking하는 데에서 에러가 발생
* suhwan계정에선 main.o를 제외한 파일들이 compile되지 않음...
  * suhwan 계정에서 불러오는 libdpdk.pc와 root 계정에서 불러오는 libdpdk.pc가 달라서 생기는 문제인 걸로 추정됨
  * 하지만 어디서 불러오는지는 찾을 수 없음...
