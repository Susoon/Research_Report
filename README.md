# Daily Report for DPDK

##  ToDo List

1. ~~gpunet 코드에서 buffer의 운용 방법 확인~~
   * ~~gpu에 할당된 buffer의 총 size~~
   * ~~send / recv에 따른 buffer 활용~~
     * ~~왜 send에서는 index로 sbuf에 접근해서 message를 가져오고 recv에서는 ptr로 packet을 가져오는가~~
   * ~~gpu interface 확인~~
     * ~~warp단위로 함수를 호출하는 과정 확인~~
2. packet size별로 nf 돌려서 그래프 만들기
3. Matrix Multiplication 구현해서 dpdk와 gdnio로 실험하기
4. Evaluation할 app 찾아서 돌려보기

---
## 06/03 현재상황
1. 64B packet
* IV값을 대입해주는 것을 제외한 모든 부분(SHA포함)만 돌렸을 때의 성능을 확인해보았다.

<center> ipsec 64B Application Buffer </center>

![Alt_text](image/06.03_ipsec_64_all_appbuf_SHA.JPG)

* 100%의 성능이 나온다.
* 이는 IV값을 대입해주는 for문에 문제가 있다는 것을 보여준다.
  * 문제가 isolation되었다.
* 이를 어떻게 해결할 것인가에 대한 해결책이 필요하다.
* 해결책을 위해선 정확한 원인 파악이 필요하다.

2. 128B packet
* 128B 버전으로 구현된 ipsec을 실행시켰더니 다음과 같은 에러가 발생하면서 ipsec kernel이 launch되지 않았다.

<center> Error of 128B packet ipsec </center>

![Alt_text](image/06.03_ipsec_128_error.png)

* 위의 에러의 원인을 찾아냈다.
  * extended변수의 indexing 문제였다.
* 기존 64B와 1514B packet 코드를 기준으로 구현하였는데, 이 코드는 extended를 global memory에 선언하고 이를 매개변수로 받아 사용했다.
* 이 후 코드를 변경하면서 extended가 local memory로 넘어가게 되었는데 이 과정에서 indexing이 꼬이면서 에러가 발생하였다.

<center> Error part </center>

![Alt_text](image/06.03_ipsec_128_error.JPG)

* 위의 사진이 에러를 유발한 부분이다.
* 기존에는 global memory에 선언된 extended에 여러 packet의 data가 저장되고 이를 여러개의 thread가 나눠 사용하다보니 저런 index의 변환이 필요했다.
* 하지만 extended를 local memory에 선언한 뒤에는 각 thread가 고유의 extended 배열을 가지므로 그럴 필요가 없다.

<center> Fixed Error part </center>

![Alt_text](image/06.03_fix_ipsec_128_error.JPG)

* local memory에 선언된 extended를 위한 indexing을 구현한 것이다.
* 수정 후에는 kernel이 정상적으로 launch되었다.
* 하지만 여전히 문제가 남아있는 듯하다.

<center> ipsec 128B packet test </center>

![Alt_text](image/06.03_ipsec_128_appbuf.JPG)

* 위의 사진은 수정된 128B packet에 대한 ipsec 코드를 실행한 결과이다.
* 위의 코드는 rx\_buf에 직접 접근하여 ipsec작업을 진행하는 것이 아니라 local memory에 application buffer를 선언하여 그 위에서 작업을 진행한다.
* 이 코드는 현재 60%의 성능을 보이고 있다.
* 이는 위의 64B packet의 실험에서 문제가 되었던 IV값 대입부분을 **multi-thread로 실행**한 버전이다.
* 이전의 128B packet의 실험의 경우 위의 에러를 해결하지 못해 SHA를 주석처리 후 실험을 진행하였다.
* 그 결과 100%의 성능을 보였다.
* 64B packet의 SHA 처리 overhead가 그리 크지 않은 것으로 미루어보았을때, 128B packet도 SHA에 의한 overhead가 40%까지 성능을 저하시키진 않을 것으로 추측된다.
* 코드 전반적인 indexing 문제를 해결 후 재실험이 필요하다

---
## 06/01 현재상황
1. ipsec 64B 버전에서 SHA처리한 값을 rx\_buf에 memcpy하는 것을 single thread로 넣었을 때의 throughput을 구하였다.

<center> Single Thread Copy </center>

![Alt_text](image/06.01_ipsec_64_single_copy.JPG)

* 위의 결과가 현재까지 가장 높은 속도를 보여준다.

2. ipsec 64B 버전에서 ipsec의 모든 과정을 single thread로 실행했을 때의 throughtput을 구하였다.
  * 여기서는 다양한 상황을 가정하였다.
  1. rx\_buf를 이용해 직접 작업을 하며, IV값 대입을 1byte씩 연산하여 대입한 경우
  2. application용 buffer를 kernel의 local memory 영역에 선언하여 rx\_buf의 값을 복사해 작업하며, IV값 대입을 1byte씩 연산하여 대입한 경우
  3. application용 buffer를 kernel의 local memory 영역에 선언하여 rx\_buf의 값을 복사해 작업하며, IV값 대입을 8byte씩 연산하여 대입한 경우

<center> IV value Assign with 1 byte Code </center>

![Alt_text](image/06.01_assigncode_single.JPG)

* IV값 대입을 1byte씩 진행한 경우의 코드이다.
* 최적화를 위해서 aes_tmp값을 buffer에 대입하는 것은 memcpy로 대체했다.

<center> IV value Assign with 8 byte Code </center>

![Alt_text](image/06.01_assigncode_eight.JPG)

* IV값 대입을 8byte씩 진행한 경우의 코드이다.
* 역시 최적화를 위해서 memcpy를 사용했다.

* 각각의 경우에 대해서 \(1\) SHA만 실행한 경우, \(2\)IV값 대입만 실행한 경우, \(3\) SHA와 IV값 대입 모두 실행한 경우로 나누어 실험을 진행하였다.
* 자세한 실험 결과는 아래에 남겼다.
---
### Single Thread 실험
1. rx\_buf & 1byte

<center> rx_buf & 1byte : SHA </center>

![Alt_text](image/06.01_ipsec_64_single_SHA_rxbuf.JPG)

<center> rx_buf & 1byte : Assign </center>

![Alt_text](image/06.01_ipsec_64_single_assign_rxbuf.JPG)

<center> rx_buf & 1byte : SHA & Assign </center>

![Alt_text](image/06.01_ipsec_64_single_all_rxbuf.JPG)

* rx\_buf에 직접 작업을 하는 경우 RX rate까지 떨어지는 것을 알 수 있다.
* SHA만 실행한 경우 96%의 효율을 보여주지만, IV값 대입을 실행할 경우 rx\_buf에 접근 횟수가 늘어나 rx\_kernel가 rx\_buf에 접근하는 것을 방해해 RX rate까지 떨어진 것을 확인할 수 있다.
* SHA와 IV값 대입을 모두 실행할 경우 30%의 아주 저조한 효율을 보인다.

2. application buf & 1byte

<center> application buf & 1byte : SHA </center>

![Alt_text](image/06.01_ipsec_64_single_SHA_appbuf.JPG)

<center> application buf & 1byte : Assign </center>

![Alt_text](image/06.01_ipsec_64_single_assign_appbuf.JPG)

<center> application buf & 1byte : SHA & Assign </center>

![Alt_text](image/06.01_ipsec_64_single_all_appbuf.JPG)

* application buffer를 사용한 경우 RX rate에 전혀 영향이 없음을 확인할 수 있다.
* SHA만 진행한 경우 rx\_buf를 사용했을 때보다 더 낮은 pps를 보이지만 IV값 대입을 진행한 경우에는 더 높은 pps를 보였다.
* 특히 SHA와 IV값 대입 모두 진행했을 경우에는 rx\_buf를 사용했을 때보다 20%가량 더 높은 pps를 보였다.

<center> Copy to App buf </center>

![Alt_text](image/06.01_ipsec_64_copy_appbuf.JPG)

* packet을 받아와 buf에 copy해주면서 발생하는 overhead에 의해 SHA가 더 낮은 pps를 보였는지 확인하기 위해서 buf에 copy해주는 것만 실행되게끔 수정 후 실험해보았다.
* 100% 효율을 보였지만 copy overhead가 전혀 없다고 확신할 수는 없다.
  * SHA와 copy를 동시에 진행함으로 인해 overhead가 큰 폭으로 증가할 가능성이 있으므로
    * scheduling이 꼬인다거나, 단순히 둘의 overhead의 합이 크다거나
* 하지만 크게 영향을 미치지는 못하는 것으로 보인다.

3. application buf & 8byte

<center> application buf & 8byte : Assign </center>

![Alt_text](image/06.01_ipsec_64_eight_assign_appbuf.JPG)

<center> application buf & 8byte : SHA & Assign </center>

![Alt_text](image/06.01_ipsec_64_eight_all_appbuf.JPG)

* IV값 대입을 8byte로 하는 경우는 SHA만 실행할 경우 2번 실험과 동일하기때문에 SHA 실험은 진행하지 않았다.
* 1byte씩 진행하는 경우보다 더 느린 속도를 보였다.
* 이 전에 misaligned 문제를 해결하기 위해 uint32\_t를 모두 unsigned char로 수정하여 코드를 실행했을 때, 형 변환이 너무 빈번하게 일어나 오히려 속도가 떨어진 것과 동일한 원인에 의해 속도가 떨어진 것으로 추정된다.
* 사실 misaligned 문제가 여기서도 발생한다.
  * 형변환을 통한 할당이 진행되는데 sizeof\(struct ethhdr\)의 값이 2의 제곱수 형태가 아니므로
* 위의 코드를 확인해보면 pps 측정을 위해 sizeof\(struct ethhdr\)의 값 없이 진행한 것을 확인할 수 있다.
* application buffer로만 실험을 진행한 이유도 있다.
* rx\_buf에 직접 접근하여 형변환을 시도할 경우 illegal memory access 에러를 띄우고 실행이 되지 않는다.

<center> Illegal Memory Access Error </center>

![Alt_text](image/06.01_ipsec_64_eight_all_appbuf.JPG)
* 런타임 에러가 발생하는 것을 확인할 수 있다.
---
### 결론 및 추가 실험의 필요성
1. rx\_buf를 사용할 경우 RX rate의 성능저하
* rx\_buf에 직접 접근하여 처리할 경우, syncthreads가 없어 여러개의 thread가 제각기 다른 시간에 rx\_buf에 접근하게 된다.
  * e.g.) thread 1번이 접근하는 중에 thread 2번이 접근하고, thread 15번이 접근을 시도하는 등
* rx\_kernel의 경우 syncthreads에 의해 모든 therad가 기다렸다가 한 번에 접근을 시도하는 데, ipsec이 rx\_buf에 연속적으로(각 therad의 접근시간이 연속적으로) 접근을 시도해서 rx\_kernel이 방해받게 되는 것이다.
* 이로인해 application buffer의 속도가 더 빨라진 것으로 추측된다.

2. 1 thread per 1 packet의 가능성
* 위의 결과를 보면 ipsec의 모든 과정을 1개의 thread로 실행할 경우 속도가 급격하게 떨어짐을 알 수 있다.
* 1 thread per 1 packet이 가능해졌을 경우의 장점은 **모든 size의 packet에 대해 동일하게 ipsec을 적용할 수 있다**이다.
* 위의 장점이 주는 효과는 거대하다.
  * 가능만하다면 ipsec에는 더이상 이슈가 존재하지 않는다.
  * batch를 할 필요도 없어보인다.
* 다만 가능성이 낮아보이고, **이를 해결하는 것이 현재 논문에 꼭 필요한 사항인가**가 의심된다.
  * 이거 하나로도 논문을 쓸 수 있지 않을까라는 생각도 든다.
* 추가적으로 알아볼 필요는 있겠으나, 구현을 통한 직접적인 해결이 필요한지는 더 논의가 필요한 것 같다.

---
## 05/27 현재상황
* ipsec 64B의 성능향상을 위한 실험을 진행했다.

1. Memory False Sharing에 의한 성능 저하가 있는가
* 결론부터 말하자면 **없다**.
* 실험은 다음과 같은 상황속에서 실행되었다.
  * data의 크기 : 64B / 20B
  * thread의 수 : 1 / 2 / 3
  * copy방향 : local memory \-\> global memory

---
## 05/26 현재상황

1. ipsec 1024B의 성능저하 원인을 알아보려 이것저것 실험 중 이상한 현상을 발견했다.
  * 해결
2. ipsec 64B의 성능향상 실험

---
### 1번 현상 의문제기 & 실험 1

<center> ipsec 1024B ring num </center>

![Alt_text](image/05.26_ipsec_1024_rot_num.JPG)

* 위의 사진은 192pps로 PKT-GEN에서 packet을 보냈을 때, gdnio가 packet 수를 count하는 if문 내에서 ring의 몇번째 칸이 반응하는지 출력한 것이다.
  * e.g.) \[1th rot\] ring num : 15는 1번째 rotation의 15번째 칸이니 186(=171 * 1 + 15)번째 칸에 packet이 들어왔고 이때문에 해당 칸을 담당하는 thread가 위의 값을 출력한 것이다.
* 위의 사진을 보면 대부분 0번째 rotation만 출력됨을 알 수 있다.
  * 위의 사진은 일부분만 가져온 것이긴하지만 1번째와 2번째 rotation에서 출력된 경우는 전체 중 10%이하에 불과했다.
* 결국 ipsec의 thread들이 **0번째 rotation에서는 제 몫의 일을 다하지만 그 외의 rotation의 경우 그렇지 못한다**라는 것을 알 수 있다.
* 하지만 의문인 것은 그렇다면 왜 **몇몇 thread는 일을 하고 그 외의 thread는 일을 하지 못하는가**이다.
* 만약 기존의 가설대로 rx\_kernel이 ipsec의 thread들이 packet buffer에 접근하는 것을 막아 packet을 확인하지 못해서 성능이 떨어진 것이라면, 0번째 rotation에서만 일을 하고 나머지 rotation에서는 일을 하지 못해야하는 것이 맞다.
  * 혹시나 몇몇 thread가 먼저 일을 마치고 rx\_kernel이 막기 전에 packet buffer에 접근하는 일이 생길까봐 ipsec에서 syncthreads()로 thread를 정리하면서 코드가 진행되게끔했다.
* 결국 packet buffer에 ipsec의 모든 thread들이 동시에 도착하지만 몇몇 thread들만 packet을 확인할 수 있었다는 것이다.
* 이것은 결국 두루뭉실하게 넘어갔던 rx\_kernel이 ipsec의 thread들을 **막는다**는 개념을 정확하게 할 필요가 있음을 보여주는 것이라 추측된다.
* 0번째뿐만이 아닌 1번째, 2번째 rotation까지 넘어가서 일을 하는 thread들이 특정한 칸(e.g. 각 rotation의 0번째 칸)을 담당하는 thread들인지, 아니면 랜덤한 thread들인지 확인해볼 필요가 있을 것 같다.
  * 현재까지는 15번째 이하의 칸을 관리하는 thread들만 다음 rotation에 넘어가서도 packet을 확인할 수 있었다
---

### 실험 2

* pps는 출력하지 않고 rot\_index가 변하는 시점과 ring num만 출력하게 해보았다

<center> ring num and rot_index </center>

![Alt_text](image/05.26_ipsec_rot.JPG)
* 위의 사진을 보면 rot\_index는 1에서 2로 넘어갔음에도 불구하고 rot\_index가 변하는 시점 앞뒤로 대부분 0번째 rotation에 속해있음을 확인할 수 있다.
  * 1에서 2로 넘어갔다면 변하는 시점 전에는 1번째 rotation으로 찍혀야하고 후에는 2번째 rotation으로 찍혀야함이 맞다.
* 그 말은 결국 **rotation은 돌지만 대부분의 thread들은 다음 rotation으로 넘어가지 못했다**라는 결론이 나온다.
  * 이번에도 15번째 이하의 칸을 관리하는 thread들만 rotation에 넘어가서도 packet을 확인할 수 있었다.
  * 즉, 945(=15*63)번째 thread까지만 rotation을 돌았다는 뜻이다.
    * 1개의 Thread Block에는 1008개의 thread가 할당되어 있다.
    * Thread Block과 어느정도 연관돼있을 가능성이 있어보인다.
      * 63(=1008-945)개의 thread만 빼고 모두 첫번째 Thread Block에 있는 thread만 넘어간 것이다.
      * 1024B의 packet은 1개의 packet당 63개의 thread가 할당된다.
* 각 Thread Block이 어떻게 일을 하고 있는지 확인이 필요해보인다.

---
### 해결

* rot\_index 변수를 shared 변수로 설정해두었는데, shared 변수의 경우 Thread Block 내에서만 공유되고 서로 다른 Thread Block간에는 공유되지 않는다.
* 그래서 첫번째 Thread Block에서만 rotation을 돌고 다른 Block의 경우 돌지 않아 성능이 떨어진 것이다.
* 수정 후 재실험이 필요하다.
---
### 2번 문제 현상 및 의문 제기

* 64B packet을 ipsec에 넣고 돌렸을 때 생기는 성능저하가 SHA처리한 값을 packet에 memcpy로 넣어주는 과정에서 생기는 것을 발견.
  * 05/25일자 실험 참고
* 성능저하의 구체적인 주 요인이 무엇인가와 memcpy를 제거할 수 있는가에 대한 실험을 진행해야함
  1. Multi-Thread copy로 인해 발생한 Memory False Sharing에 의한 성능저하가 큰 폭으로 존재하는가
    * 성능저하의 실질적 주요인은 memcpy 그 자체이겠지만, 05/25의 실험의 결과를 보면 Multi-Thread copy가 Single-Thread copy보다 성능이 떨어지는 것의 원인 파악이 필요해보였다.
    * Multi-Thread copy와 Single-Thread copy의 성능차이가 Memory False Sharing에 의한 것으로 가설을 세우고 실험을 진행했다.
      * 20B밖에 되지 않는 data를 3개의 Thread로 나누어 copy를 하다보니 서로의 cache를 더럽혀 overhead가 발생하지 않을까라는 추측을 통해 가설을 세웠다.
      * GPU의 실질적으로 호출되는 cache line size는 32B이다.
      * [GPU cacheline Question](https://forums.developer.nvidia.com/t/pascal-l1-cache/49571/4)
  2. SHA의 결과값을 packet에 붙여주기위해 사용되는 octx배열의 삭제를 통한 memcpy 제거
    * octx 배열의 경우 Outer Digest를 진행하고 그 결과값을 packet에 붙여주기전까지의 data를 저장하기 위해 사용된다.
    * 결국 octx 배열을 사용하지 않고 Outer Digest에 packet buffer를 바로 넘겨주면 memcpy가 필요없게 된다.

---
## 05/25 현재상황

* ipsec의 경우 한번의 loop으로 모든 packet(512)개를 처리할 수 없는 경우 packet을 받았는지 확인하는 것 자체에서 성능저하가 이미 발생
  * 512byte 이상의 packet의 경우 두 번 이상의 loop로 packet을 처리해야함
  * 1024byte 기준으로 512개의 packet을 3번에 걸쳐서 처리함
* rx\_kernel과 ipsec의 처리속도 차이로 추정중



* 64byte의 경우 ipsec을 실행시켰을 때, 성능저하가 있었던 것에 대해서 추가 실험을 진행했음
  * AES만 실행될 때
  * SHA처리까지만 진행되고 처리된 값이 copy되지는 않을 때
  * SHA처리 된 값이 multi-thread에 의해 copy될 때
  * SHA처리 된 값이 하나의 thread에 의해 copy될 때



<center> Only AES </center>



![Alt_text](image/05.25_64_aes.JPG)



<center> AES and SHA </center>



![Alt_text](image/05.25_64_sha.JPG)



<center> Copy with multi-threads </center>



![Alt_text](image/05.25_64_sha_multcopy.JPG)



<center> Copy with one-thread </center>



![Alt_text](image/05.25_64_sha_copy.JPG)



---

## 05/19 현재상황

* ipsec에 1개의 thread block당 512개이상의 thread를 할당할 경우 kernel이 launch되지 않았다.
  * 128byte 이상을 처리하는 ipsec 커널의 경우 1개의 thread block에 512개 이상의 thread가 할당됨
    * 모두 launch되지 않음
  * 128B를 처리하는 ipsec 커널의 경우, 1개의 thread block당 896개의 thread를 사용하고 총 4개의 thread block이 사용됨
  * 이를 1개의 thread block당 448개의 thread를 할당하고 총 8개의 thread block으로 늘렸을때는 launch됨
* 이와 동일한 현상이 nids에도 발생하는지 확인 필요
  * nids의 경우 먼저 확인되어야할 것이 packet의 size별로 할당되는 thread의 수가 다른지 코드를 확인해야함
* MM의 경우 일단 local 상에서 실험 후 코드 분석 필요
  * local 상에서 Matrix 크기별로 속도 측정
  * 커널에 thread 할당하는 것과 매커니즘 분석 필요
* DMA Batch 관련 이슈 확인해보기
  * Batched DMA로 검색해보면 될듯함
  * ~~시간이 된다면~~

---
## 05/18 현재상황
* nf의 indexing 문제의 원인을 대략적으로 파악하였다.
* 기존 if문에서 packet을 받은 것을 확인한 방법은 다음과 같다.

<center> packet checking in router </center>

![Alt_text](image/05.17_router_indexing.JPG)
* 위의 사진을 보면 chapter\_idx에는 0x1000을 곱해주었지만 threadIdx.x에는 곱해주지 않았음을 확인할 수 있다.
* 이렇게 되면 thread번호를 통한 이동은 1byte씩 이동하게 된다.
* 원래는 4byte씩 이동해야하므로, 각 thread가 본인이 맡아야할 packet의 부분에 정확하게 도달하지 못하게 된 것이다.
  * 왜 4byte씩인지는 확인해볼것
* rx\_kernel에 buf\_status의 값을 변화시키는 부분이 있어 packet을 확인하는 부분에 buf\_status를 활용하는 것으로 수정했다.
  * rx\_buf의 값을 변화시키며 packet을 확인하는 것은 packet의 data를 변조시키는 것이므로 이를 피하면서 indexing 문제도 덜한 buf\_status를 활용했다.

<center> packet checking with buf_status in router </center>

![Alt_text](image/05.18_router_indexing_buf_status.JPG)
* 위의 사진처럼 buf\_status의 값을 확인해서 packet을 확인하게끔했다.
* 수정 후 pps는 다음과 같이 확인되었다.

<center> pps with router after modification </center>

![Alt_text](image/05.18_router_pps_buf_status.JPG)
* 정확히 25%가 나오는 것을 확인할 수 있다.
* 이는 chapter\_idx의 관리가 제대로 되지 않아 발생한 문제로 추측된다.

---
## 05/17 현재상황
* nf와 Matrix Multiplication 구현중이다.

---

### NF 구현

* nf의 경우 router, ipsec, nids 모두 수정 후 실행해보았다.
* pps가 매우 이상하게 계산된다



<center> router pps </center>



![Alt_text](image/05.17_router.JPG)



<center> ipsec pps </center>



![Alt_text](image/05.17_ipsec.JPG)



<center> nids pps </center>



![Alt_text](image/05.17_nids.JPG)

* 위의 캡쳐사진들을 보면, packet을 아예 처리하지 못하거나, 1%미만의 packet들만 처리하는 것을 확인할 수 있다
* 이에 대한 원인은 추측 중이다
  1. rx\_buf의 인덱싱문제
     * ipsec과 nids의 경우, 코드 수정후 재확인 필요
     * 자세한 내용은 아래에
  2. 아직 해결되지 않은 buffer의 pipelining 문제
     * 이는 찬규형과 얘기해봐야 알 것 같다
---
### rx_buf indexing problem
* router는 1개의 packet당 1개의 thread가 할당되고, router 커널이 512개의 Thread를 가진 1개의 Thread Block을 할당받는다.
  * rx\_kernel과 동일한 개수의 Thread가 할당되고, 동일한 개수의 Thread를 가진다.
* 따라서 rx\_kernel에 chapter\_idx를 도입한 것과 동일하게 indexing을 해주면 문제가 없다.



<center> router indexing </center>



![Alt_text](image/05.17_router_indexing.JPG)
* 위의 if문 내부 조건을 보면, (0x1000\*512)\*chapter\_idx를 인덱스에 더해주어 chapter\_idx를 도입하고 있음을 알 수 있다.
* ipsec과 nids는 1개의 packet당 1개 이상의 thread가 할당되어, rx\_kernel과 다른 개수의 Thread를 가지게 된다.
  * ipsec은 64B의 packet의 경우 1개의 packet당 3개의 thread가 할당되어, 커널이 128개의 thread를 가진 Thread Block 3개를 가진다.
  * nids의 경우 1개의 packet당 3개의 thread가 할당되어, 커널이 128개의 thread를 가진 Thread Block 3개를 가진다.
* 따라서 chapter\_idx를 도입할 때, 추가적인 indexing이 필요하다.



<center> ipsec indexing </center>



![Alt_text](image/05.17_ipsec_indexing.JPG)
* 위의 if문 내부 조건을 보면, chapter\_idx외에 (0x1000\*PPB)\*seq\_num를 인덱스에 더해주어 chapter\_idx를 도입하고 있음을 알 수 있다.
* router와 달리 ipsec과 nids는 loop를 1번 실행하여 모든(512개) packet을 처리할 수 없으므로, 1번의 loop 실행 뒤 chapter\_idx 변경을 하면 안된다.
  * 1번의 loop 실행이 128개의 packet을 처리하니 총 4번의 loop가 필요하다.
    * 위에서 제시한 예시의 경우 3개의 Thread Block이 1번 loop를 실행한 뒤 1개의 Thread Block이 loop를 1번 더 실행해주어야한다.
* 따라서 seq\_num을 사용하여 4번에 걸쳐서 대입하게끔 유도한 것이다.

* 위의 추측대로 문제가 해결된다면, router는 제대로 작동해야함이 맞다.
* 하지만 router도 정상 작동을 하지 않는 것을 통해 다른 문제가 있을 수 있음을 추측할 수 있다.

---

### Matrix Multiplication

* 다음과 같은 가정 속에서 코드를 구현했다
  1. packet의 payload에 matrix의 값들이 빈틈없이 채워져있다고 가정했다.
    * packet의 payload size가 60B라면 4B의 int값 15개가 채워져있다고 가정했다.
  2. (1개의 packet에 들어있는 data의 개수) * 16의 row와 column을 가진 Square Matrix로 연산한다 
    * 60B의 payload size를 기준으로 15 * 16 = 240개의 row와 column을 가졌다고 가정했다
  3. MM 커널에서 packet을 받아와 mat1과 mat2에 data를 넣어준 뒤 gpu\_matrix\_mult함수를 호출시, mat1과 mat2를 곱하여 mat\_result에 저장하는 과정을 진행한다
    * gpu\_matrix\_mult함수가 github에서 가져온 코드이다

* github에 star를 2번째로 많이 받은 코드를 가져왔다
  * github 사이트 : [matrix-cuda](https://github.com/lzhengchun/matrix-cuda)
  * 첫번째로 많이 받은 코드는 cuda로 구현하였지만 python에서 사용할 수 있게끔 API를 제공하는 모듈이어서 제외했다
  * 첫번째로 많이 받은 MM 코드 : [blocksparse](https://github.com/openai/blocksparse)
  
* 어떠한 알고리즘을 적용하는 것이 아닌 직접 곱셈을 하는 코드이다
  
  * 이러한 이유때문에 첫번째 코드를 써야하나 고민중에 있다
  
* 이 코드는 seed를 고정한 후 rand함수를 사용해 matrix를 채우고, gpu에서 MM을 계산하고 cpu에서 MM을 계산한 후 속도차이를 확인하는 코드이다.

* matrix를 채우는 부분을 packet에서 데이터를 뽑아서 채워넣도록 수정했다



<center> Filling Matrix </center>



![Alt_text](image/05.17_MM_kernel.JPG)

* packet의 data부분을 memcpy로 matrix(2차원 배열이지만 1차원처럼 사용)에 그대로 넣어주었다.
  * packet의 payload에 matrix의 값이 빈틈없이 채워져있다는 가정을 위해서.
* 한번에 matrix의 모든 값을 채워넣을 수 없으므로, mat\_idx를 사용하여 현재 값이 대입되어야할 위치를 알려준다.
* mat\_flag로 현재 값을 대입 중인 matrix를 알려준다.
  * cur\_mat\[mat\_flag\]가 현재 값을 대입 중인 matrix이다.
* mat\_flag가 2가 되면 mat1과 mat2 모두 값 대입이 완료되었다는 의미이므로, gpu\_matrix\_mult 커널을 호출한 뒤 chapter\_idx를 이동시키고, pkt\_cnt값을 올린다.

* 현재 위의 코드는 실행되지 않고 있다.
  * cudaMemcpy가 실행되지 않는다.



<center> Error Part </center>



![Alt_text](image/05.17_errorpart.JPG)

* while문 전체를 주석처리할 경우 실행되지만, while문만 남기고 while문 내부 코드를 전부 주석처리하여도 실행이 안된다.
* 원인은 할당된 thread의 수가 gpu가 감당할 수 있는 thread의 수를 넘어갔기 때문으로 추측중이다.
* 이 때문에 thread 수를 재조정 중이다.
  * row와 column이 모두 240(=15\*16)이므로 matrix의 값의 총 개수는 49600(=240\*240)이다.
  * 하나의 값당 하나의 thread가 사용되므로 총 49600개의 thread를 할당하려 시도했던 것이다.
  * 이로 인해 MM 커널에서 thread를 모두 가져가버렸고, rx\_kernel이 사용하려했던 thread도 MM이 사용하게 되어버린 것이다.
* 여기서 의문은 thread의 수를 과도하게 할당했다면, 커널 자체가 실행되지 않았어야하지않는가 이다.
* 더 자세히 알아볼 필요가 있을 것 같다.
* 아래의 사이트는 MM 코드를 수정하면서 찾아본 cuda의 thread 할당방법을 소개한 사이트이다.
  * 아직 더 읽어봐야할 것 같다.
* [cuda_Grid](http://haanjack.github.io/cuda/2016/03/27/cuda-prog-model.html)



---

## 04/01 현재상황

* 아래의 것들은 확인한 내용들이다

1. segment의 개수
2. 각 segment의 크기 지정
3. rte\_mem\_virt2phy의 역할 및 원리

* 아래의 것들은 추가 확인이 필요한 내용들이다

1. VFIO driver
2. rte\_mem\_virt2phy의 세부 원리 및 실제 활용
   * /proc/self/pagemap의 사용방법
3. HEADROOM의 존재 이유

---

### 1. segment의 개수

* 결론부터 말하자면 **LRO를 사용하지 않는 경우는 모두 1개, LRO를 사용하는 경우는 packet과 segment의 크기에 따라 다르다**
* ixgbe 드라이버를 사용할 경우 rx를 담당하는 함수는 총 6가지가 있다
  * ixgbe_recv_pkts_lro_bulk_alloc
  * ixgbe_recv_pkts_lro_single_alloc
  * ixgbe_recv_scattered_pkts_vec
  * ixgbe_recv_pkts_vec
  * ixgbe_recv_pkts_bulk_alloc
  * ixgbe_recv_pkts
* 이를 나누는 기준은 2가지로 나뉜다
  * packet의 처리 방식
    1. LRO(Large Receive Offload)
    2. vectore
    3. default
  * allocation 방식
    * bulk allocation(batch allocation)
    * single allocation
    * default
* 위의 기준에 따라 총 6가지의 함수가 생겼고, 현재 드라이버의 상태와 사용자가 입력해준 옵션에 맞춰서 함수가 선택된다
* 이 중 LRO버전을 제외한 모든 함수들은 segment가 1로 고정되어있다
  * 모든 packet이 하나의 segment에 담겨진다는 뜻이다
* LRO버전의 경우 여러개의 packet을 하나로 합쳐서 넘겨주기 때문에 합쳐진 packet의 크기가 segment의 크기를 넘을 수 있다
* 이를 위해서 segment를 여러개를 만들어 packet을 저장한다

* 이 때문에 segment의 크기와 packet의 크기에 따라 segment의 개수는 달라질 수 있다

---

### 2. 각 segment의 크기 지정

* segment의 크기는 **프로그래머가 mempool을 만들때 지정해준다**



<center> mempool_create in fancy </center>



![Alt_text](image/04.01_mempool_create_in_fancy.JPG)

* fancy에 있는 dpdk 코드이다
* rte\_pktmbuf\_pool\_create라는 함수를 보면 매개변수로 RTE\_MBUF\_DEFAULT\_BUF\_SIZE를 넘겨준다
* 이 매개변수는 위의 주석에서 4번에 해당하는 변수로 각 mbuf의 data buffer의 크기를 지정해주는 변수이다
* RTE\_MBUF\_DEFAULT\_BUF\_SIZE는 2048 + 128로 지정되어있다
  * 03/31일자 기록 참고
* 이와 관련된 내용은 03/31일자 기록에 있는 함수의 매개변수를 따라가보면 확인할 수 있다
* 그렇다면 이 data buffer의 크기는 어떤 범위에서 허용될까



<center> buf_size setting in ixgbe_dev_rx_init </center>



![Alt_text](image/04.01_buf_size_set_in_ixgbe_dev_rx_init.JPG)

* 위의 캡쳐를 보면 1KB에서 16KB사이의 값이 유효하다고 한다
* ixy에서도 그렇고 위의 default값도 그렇고 2KB로 지정되어있는데 왜 최소가 1KB로 되어있을까
* 그 이유는 ixgbe의 rx함수 중 vector 기능을 사용하는 함수에서 추측할 수 있다



<center> comment in _recv_raw_pkts_vec </center>



![Alt_text](image/04.01_comment_in_recv_raw_pkts_vec.JPG)

* 위의 주석은 \_recv\_raw\_pkts\_vec의 함수에 있는 주석이다
  * \_recv\_raw\_pkts\_vec함수는 ixgbe\_recv\_pkts\_vec 함수를 따라가면 나오는 vector 기능을 사용하는 rx 함수이다
* 4개의 packet을 하나의 loop에서 처리한다고 기술되어있다
* 4개의 packet을 한번에 처리하여 contiguous한 공간에 담아준다



<center> load to contiguous memory space  </center>



![Alt_text](image/04.01_conti_vec.JPG)

* 따라서 총 4KB 이상의 메모리를 사용하게 하여 DMA의 사용 효율을 높인 것이다

---

### 3. rte\_mem\_virt2phy의 역할 및 원리

* 함수명 그대로 Virtual Address를 Physical Address로 변환해주는 기능을 한다
* 좀더 자세히 설명하자면 **Virtual Address에 해당하는 page를 찾아 Physical Address로 변환해준다**



<center> Get Page Number </center>



![Alt_text](image/04.01_get_page_num.JPG)

* 위의 캡쳐는 rte\_mem\_virt2phy 함수의 일부이다
* Virtual Address를 page size로 나눠서 page number를 구한다
  * page는 virtual address의 관점이고, frame이 physical address의 관점이다
  * 따라서 virt\_pfn이라는 변수는 사실 page number를 뜻하고, 아래의 page라는 변수가 실제 pfn이 될 것이다
* offset을 이용해 pfn값을 구해온다
  * pagemap을 읽어와 사용하는 이 부분은 추가확인이 필요함



<center> Get Physical Address </center>



![Alt_text](image/04.01_get_phy_addr.JPG)

* 위의 캡쳐는 이전 캡쳐의 다음 부분이다
* 구한 pfn값과 Virtual Address를 page size로 나누어 얻은 page offset(실제로는 frame offset)을 더해 Physical Address를 구한다

---

### 확인해야할 부분

1. VFIO driver
   * VFIO 드라이버가 dpdk에서 하는 역할을 확인해야한다
   * VFIO와 IOVA as VA 모드간의 관계도 확인해야한다
2. rte\_mem\_virt2phy의 세부 원리 및 실제 활용
   * /proc/self/pagemap의 사용방법과 offset의 역할에 대한 확인이 필요하다
3. HEADROOM의 존재 이유
   * 빈 padding일 가능성이 매우 크지만 확실하지 않다
   * tailroom은 document에서는 등장하지만 실제 코드에서는 등장하지 않는다는 점과 함께 확인해볼 필요가 있다
