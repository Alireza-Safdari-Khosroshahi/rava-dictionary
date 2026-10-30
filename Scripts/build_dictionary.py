#!/usr/bin/env python3
"""Build the local SQLite search index from Openjam's MIT-licensed JSON."""

import argparse
import json
import sqlite3
from pathlib import Path


def load(path):
    with path.open(encoding="utf-8") as source:
        return json.load(source)


def build(source: Path, output: Path):
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    db = sqlite3.connect(output)
    db.executescript("""
        PRAGMA journal_mode=OFF;
        CREATE TABLE words (
            id TEXT PRIMARY KEY, english TEXT NOT NULL, frequency_rank INTEGER,
            level TEXT, ipa TEXT
        );
        CREATE INDEX words_english ON words(english COLLATE NOCASE);
        CREATE TABLE senses (
            id TEXT PRIMARY KEY, word_id TEXT NOT NULL, part_of_speech TEXT,
            sense_order INTEGER, definition_en TEXT, example_en TEXT,
            meaning_fa TEXT, example_fa TEXT
        );
        CREATE INDEX senses_word ON senses(word_id, sense_order);
        CREATE TABLE forms (form TEXT NOT NULL, word_id TEXT NOT NULL);
        CREATE INDEX forms_form ON forms(form COLLATE NOCASE);
        CREATE VIRTUAL TABLE persian_search USING fts5(word_id UNINDEXED, meaning_fa,
            tokenize='unicode61');
    """)
    translations = {
        row["sense_id"]: row
        for row in load(source / "translations_fa.json")
        if row["language_code"] == "fa"
    }
    phonetics = {
        row["word_id"]: row["ipa"]
        for row in load(source / "phonetics.json")
        if row["variant"] == "us" and row.get("ipa")
    }
    words = load(source / "words_en.json")
    with db:
        for word in words:
            db.execute(
                "INSERT INTO words VALUES (?, ?, ?, ?, ?)",
                (word["id"], word["english"], word.get("frequency_rank"),
                 word.get("level"), phonetics.get(word["id"]))
            )
            for sense in word["senses"]:
                translation = translations.get(sense["id"], {})
                meaning = translation.get("meaning", "")
                db.execute(
                    "INSERT INTO senses VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (sense["id"], word["id"], sense["part_of_speech"],
                     sense["sense_order"], sense["definition_en"],
                     sense.get("example_en"), meaning,
                     translation.get("example"))
                )
                if meaning:
                    db.execute("INSERT INTO persian_search VALUES (?, ?)",
                               (word["id"], meaning))
        db.executemany("INSERT INTO forms VALUES (?, ?)",
                       ((r["form"], r["word_id"])
                        for r in load(source / "word_forms.json")))
    db.execute("ANALYZE")
    db.close()
    print(f"Built {output}: {len(words):,} English headwords")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Openjam data/json directory")
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    build(arguments.source, arguments.output)
