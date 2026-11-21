#!/usr/bin/env python3
"""Mirror marja Q&A into SQLite. Safe to rerun.

    python3 scrape.py
    python3 scrape.py --authority khorasani --language fa
    python3 scrape.py --authority sistani --language arabic

Authorities: sistani.py, shirazi.py, khorasani.py, hakeem.py, najafi.py,
fayadh.py, alrohani.py, rohani.py, mshirazi.py (the last five share mirror.py).
Shared HTML walking: htmlutil.py. Database setup: db.py.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from db import DEFAULT_DB, init_db, rebuild_fts, utc_now
import alrohani
import books
import fayadh
import hakeem
import najafi
import rohani
import treatise
import khorasani
import mshirazi
import shirazi
import sistani

AUTHORITIES = ("sistani", "shirazi", "khorasani", "hakeem", "najafi", "fayadh", "alrohani", "rohani", "mshirazi")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Mirror marja Q&A into SQLite.")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--authority", action="append", default=[], help=", ".join(AUTHORITIES) + "; omit for all")
    parser.add_argument("--language", action="append", default=[], help="language code as that authority's site publishes it")
    parser.add_argument("--reset", action="store_true", help="delete the database before crawling")
    parser.add_argument("--concurrency", type=int, default=4)
    parser.add_argument("--delay", type=float, default=0.05, help="minimum seconds between request starts")
    parser.add_argument("--limit", type=int, default=0, help="cap topics or questions per language; do not use on the live database")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sistani.self_test()
    shirazi.self_test()
    khorasani.self_test()
    hakeem.self_test()
    najafi.self_test()
    fayadh.self_test()
    alrohani.self_test()
    rohani.self_test()
    mshirazi.self_test()
    if args.self_test:
        return 0
    if args.concurrency < 1:
        raise SystemExit("--concurrency must be >= 1")
    authorities = args.authority or list(AUTHORITIES)
    unknown = sorted(set(authorities) - set(AUTHORITIES))
    if unknown:
        raise SystemExit("unknown authority %s" % ", ".join(unknown))
    lang_filter = set(args.language)
    codes = {
        "sistani": {item[0] for item in sistani.FALLBACK_LANGUAGES},
        "shirazi": set(shirazi.LANGUAGES),
        "khorasani": set(khorasani.LANGUAGES),
        "hakeem": set(hakeem.LANGUAGES),
        "najafi": set(najafi.LANGUAGES),
        "fayadh": set(fayadh.LANGUAGES),
        "alrohani": set(alrohani.LANGUAGES),
        "rohani": set(rohani.LANGUAGES),
        "mshirazi": set(mshirazi.LANGUAGES),
    }
    known = set().union(*codes.values())
    if lang_filter - known:
        raise SystemExit("unknown language %s" % ", ".join(sorted(lang_filter - known)))
    runners = {
        "sistani": sistani.crawl,
        "shirazi": shirazi.crawl,
        "khorasani": khorasani.crawl,
        "hakeem": hakeem.crawl,
        "najafi": najafi.crawl,
        "fayadh": fayadh.crawl,
        "alrohani": alrohani.crawl,
        "rohani": rohani.crawl,
        "mshirazi": mshirazi.crawl,
    }
    conn = init_db(args.db, args.reset)
    started = utc_now()
    cursor = conn.execute(
        "INSERT INTO crawl (started_at, status, languages, authorities) VALUES (?, 'running', ?, ?)",
        (started, ",".join(sorted(lang_filter)), ",".join(authorities)),
    )
    crawl_id = cursor.lastrowid
    conn.commit()
    reports = []
    try:
        for name in AUTHORITIES:
            if name not in authorities:
                continue
            if lang_filter and not (lang_filter & codes[name]):
                continue
            selected = sorted(lang_filter & codes[name]) if lang_filter else None
            reports.extend(runners[name](
                conn,
                languages=selected,
                concurrency=args.concurrency,
                delay=args.delay,
                limit=args.limit,
            ))
            if not args.limit and name in ("sistani", "shirazi", "mshirazi"):
                books.ensure_mirror(conn)
                if name == "mshirazi":
                    for failure in mshirazi.crawl_book(conn, args.delay):
                        reports.append(dict(ok=False, authority=name, error=failure))
                elif name == "sistani":
                    for failure in books.crawl(conn, selected or books.LANGS, None):
                        reports.append(dict(ok=False, authority=name, error=failure))
                else:
                    for language in selected or shirazi.LANGUAGES:
                        try:
                            treatise.crawl(conn, language)
                        except Exception as exc:
                            reports.append(dict(ok=False, authority=name, language=language, error=str(exc)))
        if not args.limit:
            rebuild_fts(conn)
        conn.execute("ANALYZE")
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        conn.commit()
    finally:
        conn.close()
    incomplete = [report for report in reports if not report.get("ok")]
    note = "; ".join(
        "%s/%s questions=%s errors=%s" % (
            report.get("authority", "sistani"),
            report.get("language"),
            report.get("questions"),
            report.get("errors"),
        )
        for report in reports
    )
    conn = init_db(args.db, False)
    conn.execute(
        "UPDATE crawl SET finished_at = ?, status = ?, note = ? WHERE id = ?",
        (utc_now(), "incomplete" if incomplete else "ok", note, crawl_id),
    )
    conn.commit()
    conn.close()
    print("db: %s" % args.db)
    for report in reports:
        print(
            "%s %s topics=%s declared=%s questions=%s inserted=%s updated=%s deleted=%s errors=%s partials=%s warnings=%s"
            % (
                report.get("authority", "sistani"),
                report.get("language"),
                report.get("topics"),
                report.get("declared"),
                report.get("questions"),
                report.get("inserted"),
                report.get("updated"),
                report.get("deleted"),
                report.get("errors"),
                report.get("partials"),
                report.get("warning_count"),
            )
        )
        if report.get("error"):
            print("  error: %s" % report["error"])
        for warning in report.get("warnings") or []:
            print("  warn: %s" % warning)
    return 1 if incomplete else 0


if __name__ == "__main__":
    raise SystemExit(main())
