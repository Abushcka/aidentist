#!/usr/bin/env bash
# Кладёт журнал упавшей сборки в ветку ci-logs (чтобы его можно было прочитать без доступа к Actions).
set -u
job="$1"; log="$2"
[ -f "$log" ] || echo "нет журнала" > "$log"
tail -c 200000 "$log" > "/tmp/$job.log"
git config user.name "ci"; git config user.email "ci@users.noreply.github.com"
git fetch origin ci-logs:ci-logs 2>/dev/null && git checkout ci-logs || git checkout --orphan ci-logs
git rm -rf --cached . >/dev/null 2>&1 || true
cp "/tmp/$job.log" "$job.log"
echo "run ${GITHUB_RUN_NUMBER} $(date -u)" > "$job.run"
git add "$job.log" "$job.run" && git commit -qm "log $job run $GITHUB_RUN_NUMBER" && git push -q origin ci-logs
