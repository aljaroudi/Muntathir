"""Import the practical-law tab of Shirazi's official Q&A API."""
from concurrent.futures import ThreadPoolExecutor
import html
import json
import re
import sqlite3

from books import MIRROR, entries, ensure_mirror
from htmlutil import class_tokens, html_to_text, read_element, walk
from shirazi import Client, LANGUAGES, catalog_url


def chapters(catalog):
    parents = []
    last = None
    for event in walk(catalog.partition("<script")[0]):
        if event[:2] == ("start", "ul"):
            parents.append(last)
        elif event[:2] == ("end", "ul") and parents:
            parents.pop()
        elif event[0] == "start":
            classes = class_tokens(event[2])
            if not ({"acar_span", "bookItem"} & classes):
                continue
            kind = "category" if "acar_span" in classes else "item"
            site_id = event[2]["rel"]
            key = kind + site_id
            heading = html_to_text(read_element(catalog, event[4])[2]).lstrip("- ")
            yield key, kind, site_id, heading, parents[-1] if parents else None
            if kind == "category":
                last = key


def page_entries(raw, heading, lang):
    for event in walk(raw):
        if event[0] == "start" and event[2].get("id") == "estefta_body_Book":
            text = html.unescape(event[2]["value"]).strip()
            share = re.search(r"ShareTreatise=(\d+)(?:&amp;|&)langs=" + lang, raw)
            if not share:
                raise ValueError("missing published body or share ID")
            url = catalog_url(lang).split("?")[0] + f"?ShareTreatise={share[1]}&langs={lang}"
            return url, entries(text, heading)
    for event in walk(raw):
        if event[:2] == ("start", "div") and class_tokens(event[2]) == {"rtl"}:
            if not html_to_text(read_element(raw, event[4])[2]):
                return catalog_url(lang), entries("", heading)
    raise ValueError("missing treatise body")


def crawl(db, lang):
    client = Client(0.15)
    client.open_session(lang)
    catalog = client.post("/estefta", dict(dataType="treatise", ShareEstefra="", search="", ShareTreatise="", langs=lang), lang)
    toc = list(chapters(catalog))
    if not toc:
        raise ValueError(f"{lang}: no treatise catalog")

    def fetch(item):
        key, kind, site_id, title, parent = item
        fields = dict(itemId=site_id if kind == "item" else "",
                      catIdCur=site_id if kind == "category" else "", ShareTreatiseRoot="0", langs=lang)
        raw = client.post("/esteftatreatiseBook", fields, lang)
        try:
            url, rows = page_entries(raw, title, lang)
        except ValueError as exc:
            # Some contents nodes group children without supplying their own text.
            if any(child[-1] == key for child in toc) and 'id="ResultsInB"' in raw and "ShareTreatise=" not in raw:
                url, rows = catalog_url(lang), entries("", title)
            else:
                raise ValueError(f"{lang}/{key}: {exc}") from exc
        return dict(id=key, title=title, parent=parent, raw=raw, url=url, entries=rows)

    with ThreadPoolExecutor(max_workers=4) as pool:
        result = list(pool.map(fetch, toc))
    if not any(chapter["entries"] for chapter in result):
        print(lang, "catalog has no readable entries", flush=True)
        return
    title = {"AR":"المسائل الإسلامية", "EN":"Practical Laws", "FA":"رساله عملیه"}[lang]
    with db:
        db.execute("INSERT OR REPLACE INTO book_edition(authority,language,site_id,title,url,chapters) VALUES (?,?,?,?,?,?)",
                   ("shirazi",lang,"treatise",title,catalog_url(lang),json.dumps(result,ensure_ascii=False)))
    print(lang, len(result), flush=True)


if __name__ == "__main__":
    import sys
    failed = False
    with sqlite3.connect(MIRROR) as db:
        ensure_mirror(db)
        for language in sys.argv[1:] or LANGUAGES:
            try:
                crawl(db, language)
            except Exception as exc:
                failed = True
                print(language, exc, file=sys.stderr, flush=True)
    sys.exit(failed)
