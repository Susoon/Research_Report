# 1. Introduction

* MAC(message authentication code)라는 secret key로 integrity를 보장함
* 전송한 data를 검증하기 위해서 authentication key가 공유된 상황에서 사용함
* HMAC은 hash function을 사용하는 MAC
  * SHA-1과 MD5가 대표적
* HMAC은 construction할 때 다음을 지켜야함
  * 수정을 안 하고 잘 쓰려면, hash function의 선택이 자유롭고 범용성이 있어야함
  * 어떠한 상황이더라도 original performance를 큰 감소 없이 유지해아함
  * key 사용과 handling이 간단해야함
  * hash function이 합리적인 가정하에 작동해야함
    * 말도 안되는 조건 걸고 그 안에서 완벽한 hash function을 사용하면 안된다는 뜻
  * 더 빠르고 안전한 hash function이 발견되면 대체가 쉬워야한다
* MD5와 SHA-1이 가장 많이 사용되는 hash function이지만 MD5의 경우 collision search attack에 약해서 MD5의 뛰어난 performance가 중요한 경우가 아니면 사용되지 않음
  * 막상 sample code는 MD-5로 나와있음....



# 2. Definition of MAC

* cryptographic한 hash function(H)와 secret Key(K)가 필요
* H는 data block들에 대해 기본적인 압축을 반복적으로 함
  * block 단위로 압축한다는 말을 내포함
* B는 여기서의 block 단위를 지칭함
  * 예시를 64Byte로 들었음
  * 대부분의 open source에서 64Byte단위
* L을 hash output의 byte-length로 지칭함
  * SHA-1기준 20byte
* K의 길이는 자유로움
  * 자세한 정보는 Key 부분에 있음
* K의 길이가 B보다 길면 H를 사용해서 L의 길이로 줄여서 사용
* K의 최소 추천 길이는 L임
  * 이유는 Key 부분에 있음
* 두 고정된 서로 다른 string인 ipad와 opad를 정의함
  * ipad = 0x36 를 B번 반복
  * opad = 0x5C 를 B번 반복
    * 어떤 값을 반복하냐는 크게 의미가 없는 듯함
    * inner padding과 outer padding이란 뜻이고, padding이니 그냥 자리 채워주는 거라 값은 크게 의미가 없는 것
* 'text'라는 data를 HMAC으로 계산하기 위해서

<center> H(K ^ opad, H(K ^ ipad, text)) </center>

* 를 실행시킴
* 즉, 다음과 같은 과정을 거침
  1. K의 끝에 0을 붙여서 B길이로 만듬
     * K가 만약 20byte이면 남은 44byte는 다 0x00으로 채움
  2. ipad와 (1)을 XOR(^)함
  3. 'text'라는 data 뒤에 (2)를 덧붙임
     * 최대 2 * B 길이의 stream
  4. (3)에 H를 적용
     * L 길이의 stream
  5. (1)이랑 opad를 XOR(^)한다
     * B 길이의 stream
  6. (4)에 (5)를 덧붙임
     * 최대 L + B 길이의 stream
  7. (6)에 H를 적용
     * L 길이의 stream
* 위의 과정을 보면 최대 2 * B의 길이까지 사용함
  * 찬규형이랑 얘기할땐 char 배열을 int 배열로 옮겨서 4배가 되는 데 왜 여긴 2배만 사용하지?
  * 2배 사용한 메모리랑 다른거를 manipulation할 메모리까지해서 4배인듯
  * 그럼 이를 줄일 방법은?



# 3. Keys

* HMAC에 사용되는 key의 길이는 아무렇게 되어도 상관은 없으나 L보다는 길게 하는 것을 추천함
* L보다 짧을 경우 안정성이 엄청나게 떨어짐
* B보다 길 경우에는 H에 의해 hashing 되어서 L길이로 줄어들어서 상관없음
* 그렇다고해서 길이를 무작정 길게할 필요는 또 없는게 길다고해서 안정성이 엄청나게 올라가지는 않음
* key의 랜덤성이 떨어지면 그래도 긴 걸 쓰자
* key는 random해야하고 주기적으로 바뀌어야함
  * 최근 공격들을 보면 특정 주기가 특별하게 안전하다라는 건 없지만 그래도 바꿔주자라고 말함



# 4. Implementaion Note

* HMAC code는 따로 수정할 필요가 없음
* 다만 IV라는 특별한 고정된 초기값을 생성해서 사용하는데, 이를 생성하는 부분의 code만 수정하면 조금 performance improvement가 있을 수 있음
  * 이걸 수정하는 건 우리가 할 일이 아님
* (K ^ ipad)와 (K ^ opad)는 미리 딱 한번만 연산을 해두면 계속 재활용할 수 있음
  * 이러한 점이 짧은 stream의 data를 authenticating할 때 큰 효과를 볼 수 있음
  * 이러한 방식으로 HMAC을 구현하면 local implementaion의 결정이고 inter-operability에는 효과가 없다
    * 이건 무슨 말인지 모르겠음
    * 아래의 내용이 본문 text

```
Choosing to implement HMAC in the above way is a decision of the local implementation and has no effect on inter-operability.
```



# 5. Truncated Output

* HMAC은 장단점이 있음
  * 장점 : hash의 결과가 attacker에게 정보를 덜 줌
  * 단점 : attacker를 예측할 bit가 적음
* 이는 모두 L의 size가 작은 데에서 나오는 듯함
* L의 size가 작으니 attacker에게 정보를 덜 주는데, attacker가 어떤 bit를 이용해서 공격했는지, 공격하는지, 공격할지에 대한 정보가 적다는 것
* 그래서 HMAC의 app들은 t라는 parameter를 사용해서 얼마만큼의 leftmost bit를 날릴지 정할 수 있음
* 이때 t의 길이는 birthday attack bound를 맞추기 위해서 hash의 결과물의 길이의 반보다 작지 않게, attacker가 예측하기 쉬운 길이의 lower bound인 80bit보다 작게 하지 않는 것을 추천함
  * 왜 80bit 이하의 truncation에서 birthday attack과 attacker가 공격하기 편한지?
  * 지금 당장 알아내야하는 부분은 아니지만 궁금하네...
* HMAC-H-t의 형태로 HMAC을 denote함
  * e.g.) HMAC-SHA1-80
    * SHA1를 hash fuction으로 사용하며 80bit를 truncate함
  * e.g.) HMAC-MD5
    * MD5를 hash function으로 사용하며 truncate하지 않음



# 6. Security

* 다음의 crptographic property들이 있어야 위의 message authentication이 유지됨

1. collision finding에 대한 내성
   * IV가 숨겨져있고 랜덤이면서 attacker들이 output을 explicit하게 사용할 수 없다는 조건이 있어야함
     * collision finding이 hash의 주기를 찾는다는 뜻인 거 같음
2. single block에 적용할 때에도 message authentication이 유지되어야함
   * HMAC에서는 이러한 block들이 inner H computation의 결과를 포함하고 있으므로 attacker들이 부분적으로는 몰라야하고, 특히 attacker들에 의해 완전하게 선택되면 안된다
     * single block에도 정상적으로 적용이 되어야한다는 말 같음
     * HMAC에서는 이러한 single block들도 inner H computation의 결과를 포함하고 있으니 attacker들이 이걸 자유자재로 다루게 되면 inner H 자체가 뚫릴 수 있으니 유의해야한다는 뜻인듯??
     * 90%정도 이해한 거 같음

* 이러한 부분들을 만족하려면 HMAC의 construction은 다음과 같은 message authentication을 위한 property들을 만족해야함
  1. hash function에 독립적이어야함
     * 다음에 더 좋은 거로 바꾸려면 당연한 얘기
     * Introduction에도 나와있음
  2. message authentication이 과도한 효과를 보여야한다
     * message authentication이 깨져서 다른 거로 교체되더라도 이 전에 authenticate된 것들이 영향을 받으면 안된다
       * 이게 가능한가....?
     * encryption은 영향을 과거에 한 것들이 영향받음
* HMAC에게 가장 강력한 공격은 collision의 frequency에 기반을 둔 것(birthday attack)이며 이는 최소한으로만이라도 합리적인 hash function에게는 통하지 않는다
  * 원래는 L size에 exponential하게 비례하는 횟수만큼 brute force로 때려맞춰야하는데 collision이 이보다 작은 횟수에서 발견되면 쉽게 뚫려버림
    * 본문의 예시는 MD5이며, L=16bytes를 사용하는 상황을 예시로 듬
    *  이것을 birthday attack으로 깨려면 2^64의 시도를 해봐야한다고 함
    * 그런데 collision이 2^30번만에 나온다고 가정하면 보안을 깨는 횟수가 반으로 줄어버림
  * collision의 발견이 빨라진다는 것은 modulo로 예시를 들면 modulo의 값이 너무 작아서 한바퀴 도는 주기가 작다는 뜻인듯
    * 7을 modulo로 사용하면 최대로 돌아도 7번이면 한바퀴를 돌게 되니 L이 아무리 커도 7번만에 뚫을 수 있음
* 이러한 것들을 막아주려면 random key를 사용해야하고, 안전한 key의 변경 mechanism, 주기적인 key 변경, key의 안전한 보호가 필수적임
  * 당연한 얘기

# Conclusion

* 우리가 HMAC을 위한 hash function을 개발하는 게 아니니 전체적인 내용 모두가 필요하지는 않음
* 혹시나 언젠가 필요할까 싶어서 일단 번역하면서 나름의 정리를 해보았음
* 지금 가장 문제인 부분은 1514B를 HMAC-SHA1의 알고리즘으로 처리할때 메모리가 부족한 부분임
* 결국 2번 chapter인 definition부분이 제일 중요함
* 자세한 code나 이런 부분들은 definition쪽의 construction부분만 확인하고 hash function들은 굳이 볼 필요 없을듯?

