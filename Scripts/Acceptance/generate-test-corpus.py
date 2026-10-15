#!/usr/bin/env python3
"""
generate-test-corpus.py — Generates a real Otzaria SQLite database (seforim.db)
for integration testing per Requirement 6.
"""

import sqlite3
import sys
from pathlib import Path

def main():
    repo_root = Path(__file__).resolve().parent.parent.parent
    db_dir = repo_root / "Tests" / "Fixtures" / "TorahPhotoStudy"
    db_dir.mkdir(parents=True, exist_ok=True)
    db_path = db_dir / "test_seforim.db"

    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(str(db_path))
    cur = conn.cursor()

    cur.execute("CREATE TABLE category (id INTEGER PRIMARY KEY, parentId INTEGER, name TEXT);")
    cur.execute("CREATE TABLE book (id INTEGER PRIMARY KEY, name TEXT, catId INTEGER, totalLines INTEGER, authorId INTEGER);")
    cur.execute("CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER, content TEXT, heRef TEXT);")

    categories = [
        (1, None, "Tanakh"),
        (2, None, "Mishnah"),
        (3, None, "Talmud Bavli"),
        (4, None, "Rambam")
    ]
    cur.executemany("INSERT INTO category VALUES (?, ?, ?)", categories)

    books = [
        (1, "בראשית", 1, 50, 1),
        (2, "משנה ברכות", 2, 40, 2),
        (3, "משנה פאה", 2, 35, 2),
        (4, "תלמוד בבלי ברכות", 3, 100, 3),
        (5, "משנה תורה הלכות דעות", 4, 30, 4),
        (6, "פרקי אבות", 2, 30, 2)
    ]
    cur.executemany("INSERT INTO book VALUES (?, ?, ?, ?, ?)", books)

    lines = [
        # Bereshit
        (1, 1, 1, "בראשית ברא אלהים את השמים ואת הארץ", "בראשית א:א"),
        (2, 1, 2, "והארץ היתה תהו ובהו וחשך על פני תהום ורוח אלהים מרחפת על פני המים", "בראשית א:ב"),
        (3, 1, 3, "ויאמר אלהים יהי אור ויהי אור", "בראשית א:ג"),
        # Mishnah Berakhot
        (4, 2, 1, "מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים לאכול בתרומתן עד סוף האשמורה הראשונה דברי רבי אליעזר", "ברכות א:א"),
        (5, 2, 2, "וחכמים אומרים עד חצות רבן גמליאל אומר עד שיעלה עמוד השחר", "ברכות א:א"),
        # Mishnah Peah
        (6, 3, 1, "אלו דברים שאין להם שיעור הפאה והבכורים והראיון וגמילות חסדים ותלמוד תורה", "פאה א:א"),
        (7, 3, 2, "אלו דברים שאדם אוכל פירותיהן בעולם הזה והקרן קיימת לו לעולם הבא כיבוד אב ואם", "פאה א:א"),
        # Talmud Bavli Berakhot
        (8, 4, 1, "תנא היכא קאי דקתני מאימתי ותו מאי שנא דתני בערבית ברישא לתני דשחרית ברישא", "ברכות ב."),
        (9, 4, 2, "תנא אקרא קאי דכתיב בשכבך ובקומך והכי קתני זמן קריאת שמע דשכיבה אימת", "ברכות ב."),
        # Rambam Hilchot Deot
        (10, 5, 1, "דעות הרבה יש לכל אחד ואחד מבני אדם וזו משונה מזו ורחוקה ממנה ביותר", "הלכות דעות א:א"),
        (11, 5, 2, "יש אדם שהוא בעל חמה כועס תמיד ויש אדם שדעתו מיושבת עליו ואינו כועס כלל", "הלכות דעות א:א"),
        # Pirkei Avot
        (12, 6, 1, "משה קיבל תורה מסיני ומסרה ליהושע ויהושע לזקנים וזקנים לנביאים", "אבות א:א"),
        (13, 6, 2, "הוו מתונים בדין והעמידו תלמידים הרבה ועשו סייג לתורה", "אבות א:א")
    ]
    cur.executemany("INSERT INTO line VALUES (?, ?, ?, ?, ?)", lines)

    conn.commit()
    conn.close()
    print(f"Generated real Otzaria SQLite database: {db_path} ({db_path.stat().st_size} bytes)")

if __name__ == "__main__":
    main()
