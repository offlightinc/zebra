# Zebra GBrain Save Status Plan

## Summary

Zebra sidebar footer의 기존 sync UI를 GBrain save 상태 UI로 전환한다. 사용자 노출 용어는 Saved / Saving / Save failed로 바꾸되, 내부 의미는 기존 Synced / Syncing / Sync failed와 대응된다.

핵심은 현재 selected vault 기준이다. Zebra는 여러 vault를 전환할 수 있으므로, 전역 GBrain 상태나 다른 vault의 cron job으로 현재 footer 상태를 표시하지 않는다.

중요한 구분:

- `gbrain status --repo <path> --json`는 사용하지 않는다. status는 `--repo`를 scope로 쓰지 않는다.
- `gbrain sync --repo <path>`는 유효하다. recurring live sync job이 특정 vault를 sync target으로 명시하는 용도로 사용한다.
- Zebra의 footer save 상태는 recurring jobs 전체가 아니라 selected vault를 대상으로 하는 live sync job만 추적한다.

## Key Changes

- `BrainSaveStatusService`가 현재 selected vault absolute path를 입력으로 받아 refresh한다.
- vault 변경 시 save status를 다시 refresh한다.
- GBrain status 판단:
  - `gbrain status --json`만 실행한다.
  - 결과의 `sync.sources[].local_path` 중 selected vault path와 매칭되는 source row만 사용한다.
  - selected vault source row가 없으면 전역 cycle/queue만으로 Saved / Saving / Save failed를 표시하지 않는다.
- OpenClaw runtime 판단:
  - selected vault path를 대상으로 하는 GBrain live sync cron job만 사용한다.
  - `status == "running"` -> Saving
  - `status == "ok"` -> Saved
  - `status == "error"` 또는 `skipped` -> Save failed
- Hermes runtime 판단:
  - selected vault path를 대상으로 하는 GBrain live sync cron job만 사용한다.
  - `last_status == "ok"` -> Saved
  - `last_status == "error"` -> Save failed
  - Hermes `jobs.json`만으로 running은 확정 불가하므로 Hermes 단독으로 Saving을 표시하지 않는다.

## Agent Cron Requirements

- Agent cron은 selected vault 기준으로 생성/검증되어야 한다.
- `platform_scheduler_install` hard-gate는 Zebra 임의의 `GBrain save` 1개 job이 아니라 GBrain 문서의 core recurring jobs를 설치하도록 지시한다:
  - Live sync, every 15 minutes: `gbrain sync --repo '<selected vault path>' --yes && gbrain embed --stale`
  - Auto-update, daily: `gbrain check-update --json`
  - Dream cycle, nightly: `gbrain dream --dir '<selected vault path>'`
  - Weekly health, weekly: `gbrain doctor --json && gbrain embed --stale`
- Footer save 상태 판단은 위 4개 중 selected vault를 대상으로 하는 Live sync job만 사용한다.
  - Auto-update, dream cycle, weekly health의 running/error는 footer Saved / Saving / Save failed 상태로 매핑하지 않는다.
  - OpenClaw/Hermes parser는 selected vault path와 live sync command shape가 모두 맞는 job만 save status job으로 인정한다.
- OpenClaw cron jobs는 selected vault target을 명시해야 한다:
  - Live sync message 내부 `gbrain sync --repo '<selected vault path>' --yes`
  - Dream cycle message 내부 `gbrain dream --dir '<selected vault path>'`
  - 가능하면 onboarding에서 검증된 `sourceId`도 함께 반영한다.
- Hermes cron jobs는 selected vault target을 명시해야 한다:
  - Live sync message 내부 `gbrain sync --repo '<selected vault path>' --yes`
  - Dream cycle message 내부 `gbrain dream --dir '<selected vault path>'`
  - Live sync와 dream cycle의 cron `--workdir '<selected vault path>'`
- `autopilot_install` path는 cron 4개를 직접 만들지 않는다. `gbrain autopilot --install --repo '<selected vault path>'`로 GBrain이 소유하는 daemon/launchd path를 사용한다.
- recurring job decision/completion은 전역이 아니라 target path/key별로 저장한다.
- vault A의 cron setup 완료가 vault B에 재사용되면 안 된다.
- Zebra가 vault 변경만으로 persistent cron을 자동 생성/수정하지 않는다. background job 생성은 기존 정책대로 사용자 승인 후 온보딩/agent가 수행한다.
- vault가 옮겨졌을 때 해당 path에 GBrain live sync cron job이 없으면, 기존 footer save/sync 상태 컴포넌트에서 `Save failed`를 표시하고 live sync cron job이 없다는 failure detail을 보여준다. 새 별도 UI를 만들지 않는다.

## Implementation Notes

- 기본 변경 위치는 `Packages/ZebraVault/Sources/ZebraVault/**`.
- cmux upstream 파일 직접 수정은 피하고 기존 Zebra adapter/touchpoint를 사용한다.
- path matching helper를 추가한다:
  - selected vault path, GBrain `local_path`, OpenClaw/Hermes `workdir`, command/prompt/script/description 내 path를 표준화 비교한다.
  - 단순히 `gbrain` 문자열만 있는 job은 selected vault job으로 인정하지 않는다.
- `ZebraServices`의 현재 `brainSaveStatus.start()` 전역 시작 방식은 selected vault path를 받을 수 있게 바꾼다.
- `ZebraGBrainOnboarding` recurring jobs prompt는 `<brain repo path>` placeholder만 보여주지 말고 resolved selected vault path를 shell-quoted example에 넣는다.
- `ZebraGBrainOnboarding` recurring jobs prompt는 platform scheduler 선택 시 GBrain core recurring jobs 4개를 만들도록 지시한다. `GBrain save`라는 Zebra 임의 1개 job으로 축약하지 않는다.
- save status parser는 4개 recurring jobs 중 live sync job만 footer 상태 source로 사용한다.
- `platform_scheduler_install`의 Step 7 `recurring_jobs completed` report는 단순히 scheduler/gateway가 준비된 상태만으로 허용하지 않는다.
  - selected vault용 GBrain live sync job이 실제 runtime scheduler에 존재해야 한다.
  - selected vault가 GBrain source로 등록되어 있어야 한다.
  - helper는 Step 7 completed guard에서 `gbrain sync`, `gbrain embed --stale`, `gbrain status --json` timestamp 확인을 직접 실행하지 않는다.
  - Step 7 completed report 저장 뒤 Save UI가 별도 post-completion refresh/poll을 수행한다. 이 poll이 selected vault source row의 완료 timestamp(`last_sync_at`, `last_synced_at`, `last_save_at`, `last_saved_at`, `updated_at` 중 하나), running 상태, 또는 실패 상태를 관찰한다.
- Step 3에서 brain repo target이 결정되면 Zebra의 selected vault도 그 repo path로 옮긴다:
  - target path가 이미 vault 목록에 있으면 select한다.
  - 없으면 vault 목록에 추가하고 select한다.
  - 이후 footer save status는 옮겨진 path 기준으로 평가된다.
- Hermes running 상태 지원은 이번 범위 밖이다.

## Test Plan

- GBrain status parser:
  - selected vault `sync.sources[].local_path`만 선택한다.
  - 다른 vault source가 fresh/saved여도 selected vault 상태로 표시하지 않는다.
  - `status --repo` 기반 설계가 쓰이지 않음을 테스트 또는 코드 구조로 확인한다.
- OpenClaw parser:
  - selected vault job running/ok/error/skipped 매핑을 검증한다.
  - `gbrain` 문자열만 있고 selected vault path가 없는 job은 무시한다.
  - selected vault path가 있어도 live sync job이 아닌 auto-update/dream/weekly health job은 footer save status로 사용하지 않는다.
  - Gateway 실패는 Save failed가 아니라 provider unavailable fallback이다.
- Hermes parser:
  - selected vault job `last_status == ok/error` 매핑을 검증한다.
  - `next_run_at`이 과거여도 Saving으로 매핑하지 않는다.
  - selected vault path가 있어도 live sync job이 아닌 auto-update/dream/weekly health job은 footer save status로 사용하지 않는다.
- Vault switching:
  - vault A job/source만 있는 상태에서 vault B 선택 시 vault A 상태를 표시하지 않는다.
  - vault 변경 시 `BrainSaveStatusService`가 새 path로 refresh된다.
  - vault B에 live sync cron job이 없으면 기존 footer save/sync 상태 컴포넌트가 `Save failed`와 live sync cron job 없음 detail을 표시한다.
- Onboarding/cron:
  - recurring jobs prompt가 GBrain core recurring jobs 4개를 설치하도록 지시한다.
  - live sync prompt가 selected vault path를 실제 `gbrain sync --repo '<path>'` 예시에 포함한다.
  - dream cycle prompt가 selected vault path를 실제 `gbrain dream --dir '<path>'` 예시에 포함한다.
  - Hermes prompt가 live sync와 dream cycle에 `--workdir '<path>'`를 포함한다.
  - recurring job receipt가 target path별로 저장된다.
  - vault A recurring job completion이 vault B completion에 적용되지 않는다.
  - Step 3에서 resolved brain repo target이 정해지면 selected vault가 그 path로 이동한다.
  - `platform_scheduler_install` Step 7 completed report는 scheduler ready, selected vault live sync job 존재, source verification까지 검증한 뒤 허용된다.
  - Step 7 completed report 직후 Save UI는 post-completion refresh/poll을 수행한다. `unknown`이면 즉시/1/3/5/10/20/30/60/90초 관찰 window 안에서 재시도하고, Saved / Saving / Save failed 중 하나가 관찰되면 멈춘다.

## Completion Criteria

- Sidebar footer가 save 용어 Saved / Saving / Save failed를 표시한다.
- 상태 판단은 selected vault path 기준이다.
  - GBrain: selected vault와 매칭되는 `sync.sources[].local_path` row만 사용.
  - OpenClaw/Hermes: selected vault와 매칭되는 GBrain live sync cron job만 사용.
  - 매칭 source/job이 없으면 전역 상태나 다른 vault 상태를 표시하지 않음.
- selected vault path에 매칭되는 live sync cron job이 없으면 기존 footer save/sync 상태 컴포넌트가 `Save failed`를 표시하고, failure detail은 live sync cron job이 없다는 사실을 설명한다.
- `gbrain status --repo <path> --json`는 사용하지 않는다.
- platform scheduler hard-gate는 GBrain core recurring jobs 4개를 설치하도록 지시한다.
- footer save 상태는 core recurring jobs 4개 중 live sync job만 상태 source로 사용한다.
- live sync cron은 selected vault를 `gbrain sync --repo '<selected vault path>' --yes` target으로 명시한다.
- `platform_scheduler_install` Step 7 completed는 selected vault에서 live sync 경로가 실제 1회 성공했고 Save UI parser가 읽을 완료 timestamp가 생긴 뒤에만 허용한다.
- `autopilot_install`은 4개 cron을 직접 만들지 않고 `gbrain autopilot --install --repo '<selected vault path>'` daemon path를 사용한다.
- Step 3에서 resolved brain repo target이 결정되면 Zebra selected vault가 그 path로 이동한다.
- Hermes는 running marker가 없으므로 Hermes 단독으로 Saving을 표시하지 않는다.
- OpenClaw와 Hermes는 서로 보완하지 않고 선택된 runtime별로 독립 판단한다.
- OpenClaw 인증/접속 실패는 Save failed가 아니라 fallback이다.
- recurring job setup/completion은 target path별로 저장되고 검증된다.
- 관련 unit tests가 통과한다.
- 구현 후 `./scripts/reload.sh --tag <tag>`로 Zebra Debug build 성공을 확인한다.

## Assumptions

- Persistent cron 생성/변경은 사용자 승인 없이 자동 수행하지 않는다.
- multi-vault 동시 scheduler orchestration은 이번 범위가 아니다.
- 이번 목표는 “현재 selected vault에 대해 정확한 save 상태와 setup completion을 보여주는 것”이다.
