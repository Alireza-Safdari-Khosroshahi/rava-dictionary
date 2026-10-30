#!/usr/bin/env python3
"""Add offline German pairs from WikDict StarDict archives to a Rava index."""

import argparse
import html
import re
import sqlite3
import struct
import zipfile
from collections import defaultdict
from pathlib import Path


TRANSLATION = re.compile(r"<div>([^<>]+)</div>")


def read_archive(path):
    with zipfile.ZipFile(path) as archive:
        index = archive.read(next(name for name in archive.namelist() if name.endswith("/stardict.idx")))
        content = archive.read(next(name for name in archive.namelist() if name.endswith("/stardict.dict")))
    cursor = 0
    while cursor < len(index):
        end = index.index(0, cursor)
        headword = index[cursor:end].decode("utf-8")
        offset, size = struct.unpack(">II", index[end + 1:end + 9])
        cursor = end + 9
        article = content[offset:offset + size].decode("utf-8", errors="replace")
        equivalents = []
        for match in TRANSLATION.finditer(article):
            value = html.unescape(match.group(1)).strip()
            if value and len(value) <= 100 and value not in equivalents:
                equivalents.append(value)
        if equivalents:
            yield headword, equivalents[:16]


def merged_entries(path):
    combined = {}
    for headword, equivalents in read_archive(path):
        slot = combined.setdefault(headword, [])
        for equivalent in equivalents:
            if equivalent not in slot and len(slot) < 16:
                slot.append(equivalent)
    return list(combined.items())


def build(database, german_english, english_german):
    db = sqlite3.connect(database)
    db.executescript("""
        DROP TABLE IF EXISTS extra_senses;
        DROP TABLE IF EXISTS extra_entries;
        CREATE TABLE extra_entries (
            id INTEGER PRIMARY KEY, direction TEXT NOT NULL,
            headword TEXT NOT NULL, preview TEXT NOT NULL
        );
        CREATE INDEX extra_direction_headword
            ON extra_entries(direction, headword COLLATE NOCASE);
        CREATE TABLE extra_senses (
            entry_id INTEGER NOT NULL, sense_order INTEGER NOT NULL,
            meaning TEXT NOT NULL, bridge TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX extra_senses_entry ON extra_senses(entry_id, sense_order);
    """)
    en_fa = defaultdict(list)
    fa_en = defaultdict(list)
    for english, persian in db.execute("""
        SELECT w.english, s.meaning_fa FROM words w JOIN senses s ON s.word_id=w.id
        WHERE s.meaning_fa IS NOT NULL AND s.meaning_fa != ''
        ORDER BY w.frequency_rank, s.sense_order
    """):
        key = english.casefold()
        if persian not in en_fa[key] and len(en_fa[key]) < 4:
            en_fa[key].append(persian)
        if english not in fa_en[persian] and len(fa_en[persian]) < 24:
            fa_en[persian].append(english)

    en_de = merged_entries(english_german)
    de_en = merged_entries(german_english)
    fa_de = defaultdict(list)
    for english, german in en_de:
        for persian in en_fa.get(english.casefold(), [])[:1]:
            for equivalent in german[:2]:
                pair = (equivalent, english)
                if pair not in fa_de[persian] and len(fa_de[persian]) < 24:
                    fa_de[persian].append(pair)

    def insert(direction, headword, senses):
        if not senses:
            return
        cursor = db.execute(
            "INSERT INTO extra_entries(direction,headword,preview) VALUES(?,?,?)",
            (direction, headword, senses[0][0]),
        )
        db.executemany(
            "INSERT INTO extra_senses VALUES(?,?,?,?)",
            ((cursor.lastrowid, number, meaning, bridge)
             for number, (meaning, bridge) in enumerate(senses)),
        )

    with db:
        for headword, equivalents in de_en:
            insert("de-en", headword, [(word, "") for word in equivalents])
            persian = []
            if en_fa.get(equivalents[0].casefold()):
                for english in equivalents[:3]:
                    for meaning in en_fa.get(english.casefold(), [])[:1]:
                        if meaning not in [row[0] for row in persian]:
                            persian.append((meaning, english))
            insert("de-fa", headword, persian)
        for headword, equivalents in en_de:
            insert("en-de", headword, [(word, "") for word in equivalents])
        for headword, equivalents in fa_de.items():
            ranked = sorted(equivalents, key=lambda row: (
                len(row[0].split()) > 1,
                not row[0][:1].isupper(),
            ))
            insert("fa-de", headword, ranked[:15])
        for headword, equivalents in fa_en.items():
            insert("fa-en", headword, [(word, "") for word in equivalents[:15]])
    db.execute("ANALYZE")
    db.commit()
    for direction, count in db.execute(
        "SELECT direction,COUNT(*) FROM extra_entries GROUP BY direction"
    ):
        print(f"{direction}: {count:,} entries")
    db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    parser.add_argument("de_en_zip", type=Path)
    parser.add_argument("en_de_zip", type=Path)
    args = parser.parse_args()
    build(args.database, args.de_en_zip, args.en_de_zip)
