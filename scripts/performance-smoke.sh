#!/bin/sh
set -eu

"$(dirname "$0")/test.sh" --performance
"$(dirname "$0")/package-app.sh"

open "build/LocalNote.app"
sleep 3

pid="$(pgrep -x LocalNote | head -1 || true)"
if [ -z "$pid" ]; then
  echo "LocalNote did not launch" >&2
  exit 1
fi

first_rss=""
maximum_rss=0
last_cpu="0.0"
sample=1
while [ "$sample" -le 8 ]; do
  rss_kb="$(ps -o rss= -p "$pid" | tr -d ' ')"
  last_cpu="$(ps -o %cpu= -p "$pid" | tr -d ' ')"
  if [ -z "$first_rss" ]; then first_rss="$rss_kb"; fi
  if [ "$rss_kb" -gt "$maximum_rss" ]; then maximum_rss="$rss_kb"; fi
  sleep 3
  sample=$((sample + 1))
done

growth_kb=$((maximum_rss - first_rss))
echo "Idle samples: first=${first_rss}KB max=${maximum_rss}KB growth=${growth_kb}KB finalCPU=${last_cpu}%"

if [ "$maximum_rss" -gt 131072 ]; then
  echo "RSS exceeded 128MB smoke-test ceiling" >&2
  kill -TERM "$pid" || true
  exit 1
fi

if [ "$growth_kb" -gt 16384 ]; then
  echo "Idle RSS grew by more than 16MB during the sample" >&2
  kill -TERM "$pid" || true
  exit 1
fi

kill -TERM "$pid" || true
