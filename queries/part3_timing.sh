#!/usr/bin/env bash
# queries/part3_timing.sh
# Час запитів частини 3 у прогрітому стані. Перший прогін part3.cypher компілює плани
# і прогріває кеш, тому не враховується. Далі п'ять прогонів, і для кожного запиту
# друкуються їхні часи (планування плюс отримання результату, мс) і медіана.
# Запуск з кореня репозиторію: bash queries/part3_timing.sh
set -euo pipefail

names="1 трилери|1 трилери, похибка|2 п'ятірки, список|2 п'ятірки, кількість|3 однакові назви|3 спільні вподобання|4 жанри, оцінки|4 жанри, фільми|5 рекомендації|6 шлях 1-2|6 шлях 1-46"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for run in 0 1 2 3 4 5; do
  docker exec -i neo4j_movielens cypher-shell -u neo4j -p password123 --format verbose < queries/part3.cypher 2>/dev/null \
    | grep -o 'after [0-9]* ms, results consumed after another [0-9]* ms' \
    | awk '{ print $2 + $8 }' > "$tmp/run$run"
done

paste "$tmp/run1" "$tmp/run2" "$tmp/run3" "$tmp/run4" "$tmp/run5" | awk -F'\t' -v names="$names" '
BEGIN { split(names, label, "|"); print "запит\t5 прогонів, мс\tмедіана, мс" }
{
  for (i = 1; i <= NF; i++) v[i] = $i + 0
  for (i = 2; i <= NF; i++) { x = v[i]; j = i - 1; while (j > 0 && v[j] > x) { v[j + 1] = v[j]; j-- } v[j + 1] = x }
  print label[NR] "\t" $1 " " $2 " " $3 " " $4 " " $5 "\t" v[3]
}'
