# Summary of Aho-Corasick Algorithm

## Concept of Aho-Corasick Algorithm

* Aho-Corasick에 대한 이해를 도와준 블로그 링크이다

[Aho-Corasick Algorithm](https://m.blog.naver.com/kks227/220992598966)



* Aho-Corasick 알고리즘은 다음의 과정을 통해 진행된다

**1. 주어진 data들을 Trie에 담는다**

![Alt_text](image/03.19_Aho_Corasick_Trie.png)


​	
​	
* 위 링크의 블로그에서 보여준 사진이다

* W라는 data set에 있는 he, she, his, hers를 Trie에 담아서 표현해준다

* 이때 he, she, his, hers가 완성되는 지점은 빨갛게 표시되어있는데 저 부분들이 Output Link가 된다

**2. Failure Link를 이어준다**

![Alt_text](image/03.19_Aho_Corasick_Failure_link.png)

* 위의 사진은 S=shis라는 string을 test해보기 위해서 Failure Link를 추가한 그림이다
* sh까지 test했을때 가장 밑의 줄의 s->h의 과정을 거치다가 다음 글자인 i로 가기위해 두번째 줄의 h의 값을 가진 node로 이동한다
* 이러한 방식으로 하나씩 Failure Link를 추가해준다
* KMP알고리즘에서의 Failure 함수와 동일한 알고리즘의 방식으로 추가해주는 것이다
* 이 과정은 data를 Trie에 추가해주는 과정에 같이 진행된다
* 즉, **input data가 아닌 기존에 가지고 있던 data**를 사용해서 추가해주는 것이다
* 위의 예시에선 S=shis라는 input data를 이용해 Failure Link를 보였지만 실제로는 그렇지 않다

**3. Output Link를 지정해준다**

* 실제로 Link를 지정해준다기보단 Output node를 지정해주는 것이다
* **이 node를 마지막 node로 가지는 string data가 있다**라는 의미이다
* Failure Link를 통해 이동할 수 있는 지점까지 모두 포함해준다

**4. Input data를 matching한다**

* 모든 Link를 이어주었다면 Input data를 matching해본다
* Failure Link를 타고 이어가다가 Output Link를 만나면 가장 최근에 matching되었던 문자부터 Output Link까지의 문자를 matching된 문자열로 인식한다

![Alt_text](image/03.19_Aho_Corasick_Failure.png)

* 위의 사진은 이 전에 있던 예시와 다른 예시이다
* S = adadac를 input data로 받아 matching해본다고 가정하자
* 두번째 줄의 node를 타고 a -> d -> a -> d -> a까지 매칭한다
* 그 다음 a -> c를 매칭하기 위해서 2번째 줄의 3번째 a(파란색 노드)로 Failure Link를 타고 이동한다
* c를 값으로 가지는 child node가 없기 때문에 다시 Failure Link를 타고 두번째 줄의 첫번째 a(초록색 노드)로 Failure Link를 타고 이동한다
* a -> c로 이동할 수 있는 link가 있으므로 a -> c를 매칭시키고 끝낸다

---

## Application to NIDS

* NIDS에 사용될때 Aho-Corasick 알고리즘의 변화는 없다
* 알고리즘에 대한 내용은 제외하고 적용될때 추가된 부분만 기록한다

1. Trie를 만드는 data set이 rule set이다
   * nids의 특성상 당연하다
   * rule set을 Trie로 만들기 위해 rule set을 parsing하는 과정이 필요하다

2. GPU에서는 Trie를 2차원 배열의 형태로 사용한다
   * Linked List를 변형한 형태인 Trie를 직접 GPU상에서 구현하여 작동할 경우 overhead가 극심해진다
   * 이 때문에 Alphabet 표를 2차원 배열로 만들어 사용한다
   * 각 행은 depth를 의미하고, 각 열은 Alphabet을 의미한다.
     * e.g. 2행 = depth가 2인 node, 
     * 10열 = ASCII code를 10으로가지는 char값
       * 그래서 사실상 Alphabet이라고 칭할 수는 없음
   * 실제로는 portGroup별로 Trie를 가져아하므로 3차원 배열변수로 다루지만 Trie만을 보았을때는 2차원 배열이다
3. 각 state를 지정해주어야한다
   * -1 : 값이 없는, 존재하지 않는 node를 의미
   * 0  : root node를 의미
   * n : 다음 node가 n번째 node라는 의미
     * 다음 node가 n을 depth로 가지는 node라는 의미
     * 다음 state가 n을 depth로 가지는 node라는 의미
     * 다음 state의 위치
     * 모두 동일한 말이다
4. GPU에서는 Failure Link와 Output Link 모두 2차원 배열의 형태로 사용한다
   * Trie의 경우와 동일한 이유를 가짐
5. 여러개의 thread가 packet을 나눠서 관리하기때문에 rule matching 관리에 주의해야한다
   * thread가 payload를 나눠서 병렬적으로 관리하다보니, 분할된 구역에 걸쳐있는 rule들의 검색에 주의해야한다
     * 이와 관련된 부분은 section을 나눠서 아래에 서술함
   * thread를 어떻게 몇 개나 할당해줄것인가에 대한 실험도 필요하다
     * ipsec 구현에 사용된 thread 수를 이용

---

## Code Analysis

#### initialize\_nids

* initialize\_nids 함수는 이름과 동일하게 nids를 위한 초기화과정이 담긴다
* 초기화에는 rule set을 가져와 이를 Trie에 담는 것도 포함된다
* Trie에 담는 과정은 다음과 같다
  1. rule set 파일을 읽어와 이를 parsing하여 data를 뽑아내다
     * data에는 dst인지 src인지, port번호는 몇번인지, state는 어떠한지에 대해 담겨있다
     * dst / src와 port에 대한 정보를 알려주고, state의 수(depth)를 알려준다
     * (현재 state) : (이전 state) data(int) data(char)의 형태로 state의 정보가 저장되어있다
  2. Failure Link를 이어준다
     * 해당 port의 Failure Link의 정보를 담는 배열을 -1로 초기화한다
     * 0번째 열의 값들(root node)의 Failure Link를 0으로 지정해 root의 Failure Link가 root로 이어지게 한다
     * root의 child node를 queue에 저장해두고, queue를 pop 시키면서 child node들의 Failure Link를 모두 이어준다
     * Failure Link를 이어준다는 것은 해당 지점에서 Failure이 일어났을때 어디로 이어질 것인가, 즉, 같은 값을 가지는 node이면서 child node를 가지는 값을 찾아서 이어준다는 것이다
  3. Output node를 지정해준다
     * 사실 이 과정은 2번의 Failure Link를 이어주면서 같이 진행된다
     * 해당 지점을 거친 pattern이 어디에 있는 node에서 끝나는지를 저장해주는 것이다
     * 아직 완벽하게 이해가 되지 않은부분이다
  4. Trie에 값들을 대입해준다
* 위의 과정을 rule set에 있는 모든 port에 대해 마치면 이들을 cudaMemcpy로 gpu에 넘겨준다
  * 위의 Trie와 Failure Link, Output을 담는 array는 2차원 배열인데, 이를 cudaMemcpy2D나 cudaMallocPitch로 넘겨주지 않는다
  * cudaMallocPitch의 형태를 본따서 넘겨준다
  * gpu에allocation된 memory를 접근할 pointer를 담을 배열을 만들어 각각의 pointer에 cudaMalloc을 해준다
  * 결국 device pointer 배열을 만들어 이를 이용해 처리하는 방식이다
* gpu에 위의 데이터들을 다 넘겨주고 나면 nids Kernel을 호출한다

#### nids

* rule set에서 뽑아온 data들은 모두 대문자이므로, 대문자로의 변환을 위해 사용할 xlatcase 배열을 만든다
* lookup2D함수를 통해 받아온 packet의 port에 해당하는 Trie에서 rule과 matching되는 pattern이 있는지 Failure Link를 이어가며 찾아본다
* 찾은 후 output 배열에서 값을 찾아와 매칭이 된건지 판단하여 이를 ret에 저장한다
* 위의 과정을 반복한다
* 세부과정은 Application to NIDS부분 참고

---

## 분할된 구역에 걸쳐있는 rule들의 검색

* thread들이 payload를 나눠서 병렬적으로 검색을 하기 때문에 위에서 설명한 바와 같이 분할된 구역에 걸쳐있는 rule들은 검색이 안된다
  * e.g.) |(0) a b c d r u|(1) l e s e f g|
  * rule set 안에 "rules"라는 rule이 있고 각 thread가 6byte씩 관할하며 |를 기준으로 thread가 관할하는 memory 구역을 구분하며 (n)은 n번째 thread가 관할하는 구역을 지칭한다고 가정하자
  * 0번 thread는 u까지 확인하고 1번 thread는 l부터 확인하게 되므로 "rules"라는 rule은 0번과 1번 thread 모두 확인할 수 없게 된다
* 이 문제를 해결하기위해 코드를 조금 수정했다



<center> original code </center>



![Alt_text](C:/Users/김수환/AppData/Local/Packages/CanonicalGroupLimited.Ubuntu18.04onWindows_79rhkp1fndgsc/LocalState/rootfs/home/add/work/Research_Report/image/03.20_aho_corasick_thread_problem_origin.JPG)

* 기존 code에서는 각 thread가 배정받은 payload_len/NIDS_THPERPKT(16bytes) 만큼만 확인한다



<center> modfied code </center>



![Alt_text](C:/Users/김수환/AppData/Local/Packages/CanonicalGroupLimited.Ubuntu18.04onWindows_79rhkp1fndgsc/LocalState/rootfs/home/add/work/Research_Report/image/03.20_aho_corasick_thread_problem_solved.JPG)

* 수정된 code에서는 while문의 조건을 true로 주어 내부에서 조건이 만족되지 않는한 무한 loop를 돌게 했다
* 다른 부분은 동일하게 주고, 내부에 loop 종료 조건을 추가해주었다
* lookup을 마친 현재의 node가 root node라면 Trie 내에서 search할 수 있는 모든 node를 탐색을 마친 후 새로운 string을 시작해야하는 상태이다
* 이 상태에서 현재 보고 있는 문자가 관할 메모리 구역 외에 있다는 것은, 관할 메모리 구역에서 시작된 string은 rule set과 모두 matching해보았다는 이야기가 된다
* 따라서 이 때 flag를 true로 주고 Output Link를 확인한 후 break로 빠져나간다

---

## 수정한 code에 대한 분석

* code는 현재 미완성된 상태로 남아있다
* 추후에 수정해야할 부분을 남겨둔다

1. Trie를 타다가 root로 다시 돌아왔을때, Output Link를 확인해야하는가
   * root는 시작점이라는 것을 제외하고는 아무 의미가 없는 node이다
   * 그러면 여기서 Output Link를 확인하지 말고 그냥 while문을 탈출시키는게 더 좋지 않을까?

