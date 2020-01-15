# Daily Research

Jan.2020.

# 1.15. WED.
# 1. rx_handler.cu 함수 해석 완료
* 이름은 rx_handler로 되어있지만 실질적으로 rx와 tx 모두를 관리함
* 수많은 packet들이 밀려들어올때 copy를 최대한 적게하면서 kernel의 관리 없이 gpu로 보내는 것이 목적
* NIC에서 tx descriptor ring 내부의 dirty part들을 알아서 지워주는데 이를 빠르게 확인해서 doorbell 때리는게 더 빠르게 진행되도록 해줌
* 크게 initializer -> send -> monitoring_loop & print_gpu 순으로 작동된다고 보면됨

rx_handler part
* packet을 받아서 ethernet structure에 대입해서 ethernet part를 확인
* ip structure와 icmp structure에 각각 대입해서 ip인지 icmp인지 확인
* MAC address가 없으면 ARP 사용해서 ip주소로 MAC address를 받아옴
* Dump function을 사용해서 각 packet들을 gpu에 보내면서 화면에 출력해서 상태 확인함

tx_handler part
* main 역할은 senderable한 packet들을 cleanable하게 해주는 것
* ring의 header가 dirty part를 신경쓰지 않고 doorbell을 때릴 수 있도록 tail이 dirty part를 확인해줌
* 실제로 비워주는 건 아니지만 이를 확인하는 작업과 확인한 후 각 index들을 clean해주는 역할을 함
* send 함수와 거의 동일한 기능을 가졌으며, send에는 thread가 sequential하게 움직이게 해주는 기능도 포함되어있음(Atomicadd)

intializer part
* 우리가 사용할 data들을 저장하기 위해서 gpu에 cuda malloc과 cuda memcpy를 통해서 memory 공간을 할당해줌
* 실질적으로 thread를 열어서 tx_handler와 rx_handler들을 실행시켜줌
* main 함수 격의 함수

---
