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
---
