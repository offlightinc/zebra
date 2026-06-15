# Task 제목 검색 구현 계획

## 요약

- v1 검색은 Task 탭에만 만든다.
- 검색 대상은 `<vault>/tasks/**` 아래에 있고 frontmatter가 `type: task`인 파일이다.
- 매칭 필드는 markdown 파일명/path basename과 frontmatter `title`이다.
- 검색 동작은 토큰 접두어 AND 검색이며, 결과는 상위 200개로 제한한다.
- 성능 목표는 인덱싱이 준비된 뒤 모든 검색어가 1초 안에 결과를 반환하는 것이다. 최초 인덱싱은 백그라운드에서 실행하고 UI를 막지 않는다.

## 주요 변경

- cmux upstream 변경이 아니라 ZebraVault 소유의 SQLite FTS5 task 검색 인덱스를 추가한다.
- task 파일마다 검색 가능한 레코드 하나를 저장한다. 레코드에는 `TaskListRow` 렌더링에 필요한 path, filename, title/displayName, status, priority, owner, dates, goal, related projects, tags, mtime/size를 포함한다.
- 일반 목록 렌더링에는 기존 Task list store를 유지한다. 다만 검색어가 있을 때는 검색 인덱스에서 결과를 읽어 현재 1000개 스캔 제한을 우회한다.
- `TaskSearchStore` ObservableObject를 추가한다.
  - `TaskFileListStore.rootPath`에 bind한다.
  - 백그라운드에서 인덱스를 빌드하고 reconcile한다.
  - 검색어 입력을 debounce한다.
  - `results`, `isIndexing`, `lastError`를 publish한다.
- 기존 Task toolbar에 compact search field를 추가한다.
- 검색 결과에도 기존 필터, 그룹, 정렬, 선택 상태, row action을 일반 task row와 동일하게 적용한다.
- 새 user-facing string은 모두 `Resources/Localizable.xcstrings`의 Zebra append 영역에 localization으로 추가한다.

## 인덱싱 동작

- 최초 bind 시 `tasks/` 아래의 모든 markdown 파일을 현재 1000개 제한 없이 스캔한다. 본문 전체가 아니라 frontmatter만 파싱하고, 유효한 `type: task` 파일만 SQLite에 upsert한다.
- file watcher 이벤트가 발생하면 백그라운드 reconcile을 실행한다.
  - 추가/변경된 파일은 다시 파싱해 upsert한다.
  - 삭제된 파일은 인덱스에서 제거한다.
  - reconcile 중에도 검색은 마지막으로 완성된 인덱스를 기준으로 계속 사용할 수 있다.
- 인덱스 DB는 Application Support 아래에 vault root에서 파생한 안정적인 key로 저장해 앱 재시작 후에도 재사용한다.
- 검색어가 비어 있으면 기존 목록 동작을 사용하고, 검색어가 있으면 인덱스 검색 결과를 사용한다.

## 테스트 계획

- temp vault와 temp SQLite DB를 사용해 `TaskSearchIndex`에 대한 ZebraVault unit test를 추가한다.
- filename match, title match, multi-token AND prefix match, 삭제된 파일 제거, 변경된 title 업데이트, non-task markdown 제외를 커버한다.
- 대량 task 파일 fixture를 기본 테스트로 만들지 않는다. 기존 list scan cap 우회는 테스트용 cap을 낮춘 runtime harness로 검증한다.
- 필요하면 검색 결과와 기존 filter/sort/group 동작이 함께 적용되는지 `TaskListViewModel` coverage를 추가한다.
- focused ZebraVault test를 실행하고, 구현 후에는 repo 규칙에 따라 escalation을 받아 `./scripts/reload.sh --tag task-search`를 실행한다.

## 완료 조건

- Task 탭 toolbar에 검색 입력이 있고, 검색어 입력 시 `<vault>/tasks/**`의 `type: task` 문서만 대상으로 검색된다.
- 검색 대상 필드는 markdown 파일명/path basename과 frontmatter `title`뿐이다.
- 검색어가 비어 있으면 기존 Task 목록 동작이 그대로 유지된다.
- 검색어가 있으면 기존 1000개 scan cap에 걸리지 않고, 인덱스 결과에서 상위 200개를 보여준다.
- 검색 결과에도 기존 status/priority/owner filter, sort, group, selection, row open, status/priority/due 편집이 정상 동작한다.
- 파일 추가/수정/삭제 후 watcher 기반 reconcile이 동작해서 검색 결과가 갱신된다.
- 인덱싱 중에도 UI가 멈추지 않고, 마지막 완성 인덱스로 검색이 가능하다.
- 인덱싱 완료 후 검색 쿼리는 resource-bounded synthetic index dataset 기준 1초 안에 반환된다.

## 완료 증거

완료 증거는 기본 자동화와 선택 성능 계측으로 분리한다. 기본 자동화는 빠르게 반복 가능한 작은 fixture만 사용하고, 성능 계측은 대량 파일을 만들지 않는 SQLite-only 데이터로 한 번 이상 남긴다.

- `TaskSearchIndex` unit test가 통과한다.
  - filename match
  - title match
  - multi-token AND prefix match
  - non-task markdown 제외
  - 삭제 파일 검색 결과 제거
  - title 변경 후 검색 결과 갱신
- 기존 list scan cap 우회 회귀 테스트가 통과한다.
  - repo, 실제 작업 vault, 테스트 temp 디렉터리 어디에도 1000개 이상의 task markdown 파일을 만들지 않는다.
  - 테스트 harness에서 list scan cap을 작은 값으로 낮춘다. 기준값은 `cap=10`, fixture는 작은 temp markdown task 25개다.
  - cap 밖에 있는 25번째 task를 검색어로 찾는다.
  - 이 증거는 검색 경로가 기존 capped list source가 아니라 task search index를 사용한다는 런타임 동작을 검증한다.
- 성능 계측 증거가 남는다.
  - repo에 대량 fixture를 체크인하지 않는다.
  - 10,000개 markdown 파일을 생성하지 않는다.
  - 파일 시스템 scanner를 거치지 않고 temp SQLite DB에 synthetic task search record 10,000건을 단일 transaction으로 bulk upsert한다.
  - synthetic record는 실제 task 문서가 아니라 path, filename, title 같은 검색 인덱스 metadata row다.
  - 인덱싱 완료 상태에서 대표 검색어 5개를 실행하고, 각 query의 worst-case elapsed time이 1초 미만임을 로그로 남긴다.
  - 이 계측은 기본 unit test의 필수 부하가 아니라 `ZEBRA_TASK_SEARCH_PERF=1` 같은 opt-in 성능 evidence로 실행한다.
  - 리소스 가드는 temp DB 50MB 이하, bulk load 30초 이하를 기준으로 둔다. 이 범위를 넘으면 fixture를 더 키우지 말고 query plan이나 인덱스 설계를 먼저 수정한다.
- UI 핵심 동작은 자동 증거로 보강한다.
  - `TaskSearchStore` watcher/reconcile 테스트가 파일 추가/수정/삭제 후 검색 결과 갱신을 검증한다.
  - `TaskSearchStore.replace` publish 테스트가 검색 결과에서 status/priority/due row action 후 결과 snapshot이 즉시 갱신됨을 검증한다.
  - `TaskListViewModel` 테스트가 검색 결과 snapshot에 기존 filter/sort/group pipeline이 그대로 적용됨을 검증한다.
  - `TaskSearchIndex` metadata 테스트가 검색 결과에 row 렌더링과 filter/sort/group에 필요한 status, priority, owner, dates, goal, project, tag가 보존됨을 검증한다.
- UI 수동 smoke checklist는 릴리즈 전 보조 검증으로 남긴다. 이 항목은 Codex 자동 완료 gate가 아니다.
  - 검색 입력/clear 동작
  - 검색 중 empty state
  - 검색 결과 클릭으로 문서 열기
  - 검색 결과에서 status/priority/due 변경
  - 검색 결과에 filter/sort/group 적용
- 빌드 검증이 끝난다.
  - focused ZebraVault tests pass
  - `./scripts/reload.sh --tag task-search` 성공
  - 최종 답변에 clickable tagged app link 포함

## 가정

- v1은 task 본문 텍스트를 검색하지 않는다.
- v1은 Documents 탭이나 앱 전역 검색을 대상으로 하지 않는다.
- v1은 오타 허용 fuzzy matching이나 문자열 중간 substring matching을 지원하지 않는다.
- 상위 200개 결과만 보여주는 것은 성능과 sidebar 사용성 측면에서 허용 가능하다.
