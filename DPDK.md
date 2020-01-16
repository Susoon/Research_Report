#DPDK

# 1. DPDK 개념
## 1.1 특징
* Intel Architecture 기반의 packet 처리 최적화 system software
* kernel 대신에 network packet을 처리하는 application을 제공하고 전용 CPU core을 할당해서 network card의 packet을 kernel을 거치지않고 직접 처리

## 1.2 장점
* packet 처리에 고성능을 보임
* 고가의 장비를 따로 구비할 필요가 없음
* CPU가 지장받지 않고 작업을 수행할 수 있음 (app에 전용 CPU core가 할당되므로)

## 1.3 단점
* Intel사의 system software다보니 사용가능한 lan card가 한정적임
* application이 network packet을 처리하다보니 application이 해야할 일이 많아짐
    * network packet 처리를 한다는 것은 packet header를 보고 packet 판별부터 동작까지 다 구현하는 것을 말함

## 1.4.kernel 기반 packet 처리 과정과 DPDK의 차이점
* batch packet 처리 기술을 통해 다수의 packet을 동시에 처리
* network packet마다 packet buffer memory를 dynamic하게 alloc/dealloc하던 것을 static하게 할당
* Lockless Queue를 구현하여 shared data 접근시의 bottle neck을 해결
* huge page를 이용하여 TLB miss를 줄임
* optimized poll mode driver를 통해 physical NIC과 virtual NIC driver을 최적화시킴
* pre-fetching과 cache line사이즈로 정렬하여 CPU가 data를 기다리는 것을 최소화시킴
* CPU core isolation을 사용하여 thread switching overhead를 해결
* KNI를 사용하여 host kernel networking stack의 성능을 개선

## 1.5 Lockless Queue
* 원래는 여러개의 thread가 동시에 push를 하거나 pop을 하는게 불가능한 것으로 알았음
* 기존 lockless queue의 경우 lock queue를 여러개를 두기때문에 동시에 하는 것이 불가능
* dpdk의 경우 single lock queue를 사용하여 이를 가능하게 함
* CAS(compare and swap)연산을 사용 (exchange로 기록된것은 의미상 비슷해서 표현을 다르게 한 것 같음)
* queue에 enqueue와 dequeue를 하는 게 또다른 queueing을 하는 듯한 느낌을 줌
* dpdk 홈페이지에는 core라고 표현을 하지만 thread와 비슷한 의미로 사용한 것 같음
    * 추가 확인 필요

### 1.5.1 Lockless Queue 실행 과정
* state를 담을 structure를 구성(cons_head/tail, prod_head/tail을 담고 있음)
* structure에서 각 core의 local variable에 prod_head와 cons_tail을 복사해서 넣어줌
* 각 core의 local variable에 prod_next(cons_next)를 만들어서 다음칸을 가리키게함
* local variable의 prod_head에 data를 저장하고, prod_next를 한칸 움직임
* local variable의 prod_next와 structure의 prod_head가 같도록 prod_head를 한칸 움직임
* 이때 하나의 core가 data를 저장하면서 sturcture의 prod_head가 움직인 상태기 때문에
다른 core의 prod_next와 structure의 prod_head가 다른 칸을 가리킴
* 이걸 compare함 
    * structure의 prod_head와 현재 core의 prod_next를 비교해서 같으면 data 저장을 진행
    * structure의 prod_head와 현재 core의 prod_next가 다르면 한칸 앞으로 움직임
    * 위를 반복해서 같아지게 만들어줌
    * redo part란 비교 후 prod_next를 움직이는 단계로 돌아가는 것을 말함
* data 저장이 끝나면 prod_tail을 앞으로 한칸 움직이고 끝냄
* 위는 enqueue의 경우만 나타냈는데 dequeue의 경우 cons_head와 cons_next로 똑같은 과정을 진행
* swap은 어디에...?
    * prod_head를 왔다갔다 하는 부분을 swap이라고 하는건가? -> swap이 아닌 거 같은데 -> 확인 필요

### 1.5.2 Lockless Queue 추가 내용
* 결국 lock이 발생할 수도 있음
    * redo part를 계속 돌리면 prod_next를 계속 돌리는 걸 반복하는 spin lock이 발생함
    * 이를 보고 CAS가 실패했다고 표현함
* homepage에 여러개의 lockless queue를 쓰는 경우보다 빠르고 간단하며 여러개의 dequeue/enqueue를 적용하기에 좋다고 표현함
    * 그럼 기존 spinlock이나 mutex, semaphore과의 성능차이는? -> 확인 필요
    * 여러개의 lockless queue는 bulk enqueue/dequeue를 아예 못하는건가? -> 확인 필요

## 1.6 optimized poll mode driver

## 1.7 CPU core isolation

## 1.8 Kernel NIC Interface(KNI) 

---
