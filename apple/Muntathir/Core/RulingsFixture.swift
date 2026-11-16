#if DEBUG
    import Foundation
    import SQLite3

    struct RulingsFixture {
        let url: URL
        init(url: URL = URL.temporaryDirectory.appending(path: UUID().uuidString + ".db")) throws {
            self.url = url
            var db: OpaquePointer?
            guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw HadithDatabaseError.unavailable }
            defer { sqlite3_close(db) }
            let sql = """
            PRAGMA application_id=1179809601; PRAGMA user_version=1;
            CREATE TABLE authority(code TEXT, name_ar TEXT, name_en TEXT, sort_order INTEGER);
            INSERT INTO authority VALUES ('sistani','السيستاني','Sistani',1),('shirazi','الشيرازي','Shirazi',2);
            CREATE TABLE language(code TEXT, name TEXT, direction TEXT);
            INSERT INTO language VALUES ('ar','العربية','rtl'),('en','English','ltr');
            CREATE TABLE topic(id INTEGER PRIMARY KEY,authority_code TEXT,language_code TEXT,title TEXT,parent_id INTEGER,position INTEGER);
            INSERT INTO topic VALUES (1,'sistani','ar','الصلاة',NULL,1),
            (2,'sistani','ar','الفرائض',1,2),(3,'sistani','en','Worship',NULL,1),
            (4,'sistani','en','Fasting',3,2),(5,'sistani','en','Charity',NULL,3);
            CREATE TABLE question(id INTEGER PRIMARY KEY,authority_code TEXT,language_code TEXT,site_id TEXT,question TEXT,answer TEXT,url TEXT);
            INSERT INTO question VALUES (100,'sistani','ar','42','الصلاة','نص أصلي','https://example.org/1'),
            (200,'shirazi','ar','42','الصلاة','جواب آخر','https://example.org/2'),
            (300,'sistani','en','42','Prayer','Original answer','https://example.org/3'),
            (301,'sistani','en','43','Fasting','Fasting answer','https://example.org/4'),
            (302,'sistani','en','44','Charity','Charity answer','https://example.org/5');
            CREATE TABLE placement(topic_id INTEGER,question_id INTEGER,position INTEGER);
            INSERT INTO placement VALUES (1,100,1),(2,100,1),(3,300,1),(4,301,1),(5,302,1);
            CREATE VIRTUAL TABLE question_fts USING fts5(question,answer,content='question',content_rowid='id');
            INSERT INTO question_fts(rowid,question,answer) SELECT id,question,answer FROM question;
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw HadithDatabaseError.unavailable }
        }

        func remove() {
            try? FileManager.default.removeItem(at: url)
        }
    }

#endif
