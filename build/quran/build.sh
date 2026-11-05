#!/usr/bin/env bash
# Builds build/quran/dist/<id>.db from data/*.sql, then copies into the app bundle folder.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
data="$here/data"
out="$here/dist"
ship="$here/../../apple/Muntathir/Resources/Quran"
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

# quran_words: ranked whole-word/prefix index. quran_fts: trigram index for text inside words.
index() { # <id> <word tokenizer> [root column]
  sqlite3 -bail "$out/$1.db" "
    CREATE VIRTUAL TABLE quran_words USING fts5 (text${3:+, root}, content = '', tokenize = '$2');
    CREATE VIRTUAL TABLE quran_words_vocab USING fts5vocab (quran_words, col);
    CREATE VIRTUAL TABLE quran_fts USING fts5 (text, content = '', tokenize = 'trigram remove_diacritics 1');
    INSERT INTO quran_fts (rowid, text) SELECT \"index\", $(norm text) FROM quran;"
}

finish() { # <id>
  sqlite3 -bail "$out/$1.db" "
    INSERT INTO quran_words (quran_words) VALUES ('optimize');
    INSERT INTO quran_fts (quran_fts) VALUES ('optimize');
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
index quran 'unicode61 remove_diacritics 2' root
sqlite3 -bail "$out/quran.db" "
  CREATE UNIQUE INDEX quran_sura_aya ON quran (sura, aya);
  CREATE TABLE quran_search AS SELECT \"index\", sura, aya, $(norm text) AS text, '' AS root FROM quran;
  CREATE TABLE quran_roots_raw (word TEXT, root TEXT);"
python3 "$here/roots.py" "$data/morphology.txt" "$out/quran.db"
sqlite3 -bail "$out/quran.db" "
  CREATE TABLE quran_roots (word TEXT, root TEXT, PRIMARY KEY (word, root)) WITHOUT ROWID;
  INSERT OR IGNORE INTO quran_roots SELECT word, $(norm root) FROM quran_roots_raw;
  INSERT INTO quran_words (rowid, text, root) SELECT \"index\", text, $(norm root) FROM quran_search;
  DROP TABLE quran_search;
  DROP TABLE quran_roots_raw;"
finish quran
echo "quran $(du -h "$out/quran.db" | cut -f1)"
expect quran 'word بسم' "SELECT count(*) FROM quran_words WHERE quran_words MATCH 'text : \"بسم\"'" +
expect quran 'word في matches فى' "SELECT count(*) FROM quran_words WHERE quran_words MATCH 'text : \"في\"'" +
expect quran 'root كتب has 2:79' "SELECT count(*) FROM quran_words WHERE quran_words MATCH 'root : \"كتب\"' AND rowid = (SELECT \"index\" FROM quran WHERE sura = 2 AND aya = 79)" 1
expect quran 'يكتبون has root كتب' "SELECT count(*) FROM quran_roots WHERE word = 'يكتبون' AND root = 'كتب'" 1
expect quran 'substring صوم in 19:26' "SELECT count(*) FROM quran_fts WHERE quran_fts MATCH '\"صوم\"' AND rowid = 2276" 1

for sql in "$data"/*.sql; do
  id=$(basename "$sql" .sql)
  [[ $id == quran ]] && continue
  load "$id"
  expect "$id" 'aligned with Arabic' 'SELECT count(*) FROM quran JOIN ar.quran USING ("index", sura, aya)' 6236
  expect "$id" 'no \x27 escapes left' "SELECT count(*) FROM quran WHERE text LIKE '%\\''%'" 0
  case $id in
    zh.*) sqlite3 -bail "$out/$id.db" 'VACUUM;' ;; # No word boundaries to index; searched with LIKE.
    en.*) index "$id" 'porter unicode61 remove_diacritics 2' ;;
    *) index "$id" 'unicode61 remove_diacritics 2' ;;
  esac
  [[ $id == zh.* ]] || {
    sqlite3 -bail "$out/$id.db" "INSERT INTO quran_words (rowid, text) SELECT \"index\", $(norm text) FROM quran;"
    finish "$id"
  }
  echo "$id $(du -h "$out/$id.db" | cut -f1)"
done
expect en.qarai 'believing matches believers' "SELECT count(*) FROM quran_words WHERE quran_words MATCH '\"believing\"' AND rowid IN (SELECT \"index\" FROM quran WHERE text LIKE '%believers%')" +
expect fr.hamidullah 'misericordieux matches Miséricordieux' "SELECT count(*) FROM quran_words WHERE quran_words MATCH '\"misericordieux\"' AND rowid = 1" 1
expect zh.jian '真主' "SELECT count(*) FROM quran WHERE text LIKE '%真主%'" +
cp "$out"/*.db "$ship/"
du -sh "$out"
