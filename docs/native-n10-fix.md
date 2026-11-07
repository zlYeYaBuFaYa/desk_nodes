# N10 reproducibility followup

Prepared against author HEAD `bfe209a027bd16cb44a2bd45cfebb6dcd7b6d062`; left uncommitted for supervisor review and a separate `native-n10-fix` followup. No application sources or prior milestone/spec/plan documents changed.

`git am` integration N10 `5654152705c87da6f13053a1d02c1f407a74d8f8` has parent `a2791ba`, so the author baseline object need not exist there. Selecting HEAD's parent would also become incorrect after a followup, and trusting any available parent could bless altered authoritative inputs. The checker now uses a checked-in content manifest instead of selecting a commit. Its 24 paths, regular-file Git modes and SHA-256 digests were independently compared with the complete protected tree at original baseline `5e6443371a6181f63fe30cd41d8c6f023ea8410b`. Verification requires no Git object, remote, hash alias, or history depth. The manifest is a review-controlled anchor; never regenerate it from a candidate integration tree to make a failure pass.

The checker verifies actual working-tree bytes (including uncommitted review changes), executable modes and the complete file set beneath `docs/spec`, plus the plan and N1–N9 docs. Missing/added/changed files and symlinks fail explicitly. Empty directories have no Git file identity. Existing resource/source/prototype checks remain active. Manifest/helper/checker changes require ordinary code review, as did the former embedded baseline constant.

Validation completed on Linux:

- `python3 scripts/test-n10-preservation.py`: four tests passed, running the real complete N10 checker 30 times. Temporary repositories contain only checker inputs, with independent object stores, isolated Git configuration/environment, no alternates, and confirmed absence of the original baseline object. Coverage includes uncommitted review, committed N10 and followup histories, alternate parents containing changed protected content, unstaged/staged changes to requirements/plan/every N1–N9 doc, additions, deletions, executable mode and symlink changes. Fixture commits exist only in disposable repositories.
- `check-n1.py`, `check-n7.py`, `check-n8.py`, `check-n9.py`, `check-n10.py`: passed; icon `--check`: passed.
- All Python scripts compiled for syntax; shell syntax checks passed; native Swift source/test grammar parse passed (no SDK/typecheck claim).
- `git diff --check` and original-baseline spec/plan/N1–N9 preservation diff: passed. Independent manifest comparison: all 24 entries matched.

Reproduction runner and evidence: `/workspace/desknotes/logs/native-n10-fix-checks.sh`, `native-n10-fix-fixtures.log`, `native-n10-fix-static.log`, `native-n10-fix-native-parse.log`, `native-n10-fix-anchor.log`, and `native-n10-fix-review.log`. An initial fixture run exposed an unhelpful missing-file exception; the corrected path inventory now reports it as a protected-path failure and the full suite passed. No full Swift build/test was needed because application sources are unchanged. Mac acceptance remains unverified. No commit/push/rebase/amend or tool installation occurred in the author repository; no quota exhaustion occurred.
