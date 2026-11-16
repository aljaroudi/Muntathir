#!/usr/bin/env bash
# Builds build/quran/dist/<id>.db from data/*.sql, then copies into the app bundle folder.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
data="$here/data"
out="${1:-$here/dist}"
ship="${2:-$here/../../apple/Muntathir/Resources/Quran}"
mkdir -p "$out" "$ship"

# Search key, identical to QuranSearchText.normalize: strip tashkeel and tatweel, unify alef, ya, and ta marbuta.
norm() {
  local e=$1 c
  for c in $(seq $((0x610)) $((0x61A))) $((0x640)) $(seq $((0x64B)) $((0x65F))) $((0x670)) $(seq $((0x6D6)) $((0x6ED))); do
    e="replace($e, char($c), '')"
  done
  for c in $((0x622)) $((0x623)) $((0x625)) $((0x671)); do
    e="replace($e, char($c), 'ا')"
  done
  echo "replace(replace($e, 'ى', 'ي'), 'ة', 'ه')"
}

load() { # <id>
  local db="$out/$1.db"
  rm -f "$db"
  {
    cat "$here/schema.sql"
    echo 'BEGIN;'
    awk '!f { i = index($0, "INSERT"); if (!i) next; f = 1; $0 = substr($0, i) } 1' "$data/$1.sql" |
      sed -e "s/INSERT INTO \`[^\`]*\`/INSERT INTO quran/" -e "s/\\\\'/''/g"
    echo 'COMMIT;'
  } | sqlite3 -bail "$db"
}

# A single word index supports basic offline search; broader retrieval lives on the API.
index() { # <id> <word tokenizer> [root column]
  sqlite3 -bail "$out/$1.db" "
    CREATE VIRTUAL TABLE quran_words USING fts5 (text${3:+, root}, content = '', tokenize = '$2');
    CREATE VIRTUAL TABLE quran_words_vocab USING fts5vocab (quran_words, col);"
}

finish() { # <id>
  sqlite3 -bail "$out/$1.db" "
    INSERT INTO quran_words (quran_words) VALUES ('optimize');
    PRAGMA optimize;
    VACUUM;"
}

expect() { # <id> <label> <sql> <expected count, or + for nonzero>
  local n
  n=$(sqlite3 "$out/$1.db" "ATTACH '$out/quran.db' AS ar; $3")
  [[ $4 == + && $n -gt 0 || $n == "$4" ]] || { echo "FAIL $1: $2 ($n)" >&2; exit 1; }
}

load quran
expect quran rows 'SELECT count(*) FROM quran' 6236
# Shipped text omits the basmala that Tanzil prefixes to each opening verse; saved highlight ranges depend on it.
sqlite3 -bail "$out/quran.db" "UPDATE quran SET text = substr(text, 36) WHERE aya = 1 AND sura NOT IN (1, 9) AND substr(text, 1, 35) = (SELECT text FROM quran WHERE \"index\" = 1);"
expect quran 'basmala stripped from openings' "SELECT count(*) FROM quran WHERE aya = 1 AND sura NOT IN (1, 9) AND text LIKE (SELECT text FROM quran WHERE \"index\" = 1) || '%'" 0
index quran 'unicode61 remove_diacritics 2'
sqlite3 -bail "$out/quran.db" "
  CREATE UNIQUE INDEX quran_sura_aya ON quran (sura, aya);
  INSERT INTO quran_words (rowid, text) SELECT \"index\", $(norm text) FROM quran;"
python3 "$here/layout.py" "$data/quran-data.xml" "$data/qpc-v1-15-lines.db" "$data/qpc-hafs-word-by-word.db" "$out/quran.db"
finish quran
for d in 'page 604' 'juz 30' 'hizb 240' 'manzil 7' 'ruku 556'; do
  expect quran "${d% *} count" "SELECT count(*) FROM quran_divisions WHERE kind = '${d% *}'" "${d#* }"
done
expect quran sajdas 'SELECT count(*) FROM quran_sajdas' 15
expect quran 'every verse paged' 'SELECT count(*) FROM quran WHERE page IS NULL OR juz IS NULL' 0
expect quran 'every page has 15 lines' 'SELECT count(*) FROM (SELECT page FROM quran_lines GROUP BY page HAVING count(*) = 15 OR page <= 2)' 604
expect quran 'page 1 is Al-Fatiha' 'SELECT count(*) FROM quran WHERE page = 1 AND sura = 1' 7
expect quran 'page 604 ends at 114:6' 'SELECT max("index") FROM quran WHERE page = 604' 6236
expect quran 'every verse has a QPC end marker' 'SELECT count(DISTINCT "index") FROM quran_words_qpc' 6236
expect quran 'Tanzil pages match layout' "SELECT count(*) FROM quran_divisions d JOIN quran q ON q.\"index\" = d.start WHERE d.kind = 'page' AND q.page != d.number" 0
echo "quran $(du -h "$out/quran.db" | cut -f1)"
expect quran 'word بسم' "SELECT count(*) FROM quran_words WHERE quran_words MATCH 'text : \"بسم\"'" +
expect quran 'word في matches فى' "SELECT count(*) FROM quran_words WHERE quran_words MATCH 'text : \"في\"'" +

for sql in "$data"/*.sql; do
  id=$(basename "$sql" .sql)
  [[ $id == quran ]] && continue
  load "$id"
  expect "$id" 'aligned with Arabic' 'SELECT count(*) FROM quran JOIN ar.quran USING ("index", sura, aya)' 6236
  expect "$id" 'no \x27 escapes left' "SELECT count(*) FROM quran WHERE text LIKE '%\\''%'" 0
  case $id in
    zh.*) sqlite3 -bail "$out/$id.db" 'VACUUM;' ;; # No word boundaries to index; searched with LIKE.
    en.*) index "$id" 'unicode61 remove_diacritics 2' ;;
    *) index "$id" 'unicode61 remove_diacritics 2' ;;
  esac
  [[ $id == zh.* ]] || {
    sqlite3 -bail "$out/$id.db" "INSERT INTO quran_words (rowid, text) SELECT \"index\", $(norm text) FROM quran;"
    finish "$id"
  }
  echo "$id $(du -h "$out/$id.db" | cut -f1)"
done
expect en.qarai 'exact believing excludes believers-only rows' "SELECT count(*) FROM quran_words WHERE quran_words MATCH '\"believing\"' AND rowid IN (SELECT \"index\" FROM quran WHERE text LIKE '%believers%' AND text NOT LIKE '%believing%')" 0
expect fr.hamidullah 'misericordieux matches Miséricordieux' "SELECT count(*) FROM quran_words WHERE quran_words MATCH '\"misericordieux\"' AND rowid = 1" 1
expect zh.jian '真主' "SELECT count(*) FROM quran WHERE text LIKE '%真主%'" +
cp "$out"/*.db "$ship/"
du -sh "$out"
