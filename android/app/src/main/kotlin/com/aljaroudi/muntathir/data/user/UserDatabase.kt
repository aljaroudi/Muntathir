package com.aljaroudi.muntathir.data.user

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Upsert
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import com.aljaroudi.muntathir.core.highlight.StoredRecord
import com.aljaroudi.muntathir.core.highlight.UserRecords
import kotlinx.coroutines.Dispatchers

/** Swift `HighlightRecord`: a row per installation and highlight. */
@Entity(tableName = "highlights", indices = [Index("itemID")])
data class HighlightEntity(
    @PrimaryKey val recordID: String,
    val itemID: String,
    val installationID: String,
    val payload: String,
    val modifiedAt: Long,
    val isTombstone: Boolean,
)

/** Swift `BookmarkRecord`. */
@Entity(tableName = "bookmarks", indices = [Index("itemID")])
data class BookmarkEntity(
    @PrimaryKey val recordID: String,
    val itemID: String,
    val installationID: String,
    val payload: String,
    val modifiedAt: Long,
    val isTombstone: Boolean,
)

/** Swift `ProgressActivityRecord`: one reading or tasbih session, as JSON. */
@Entity(tableName = "activity")
data class ActivityEntity(
    @PrimaryKey val activityID: String,
    val payload: String,
)

@Dao
interface UserDao {
    @Query("SELECT * FROM highlights")
    suspend fun highlights(): List<HighlightEntity>

    @Query("SELECT * FROM bookmarks")
    suspend fun bookmarks(): List<BookmarkEntity>

    /** One transaction, so a batch saves together or not at all. */
    @Upsert
    suspend fun upsertHighlights(rows: List<HighlightEntity>)

    @Upsert
    suspend fun upsertBookmarks(rows: List<BookmarkEntity>)

    @Query("SELECT * FROM activity")
    suspend fun activities(): List<ActivityEntity>

    @Query("SELECT * FROM activity WHERE activityID = :id")
    suspend fun activity(id: String): ActivityEntity?

    @Upsert
    suspend fun upsertActivity(row: ActivityEntity)
}

/**
 * Personal data in `databases/user.db`, included in Auto Backup (iOS keeps the same records in iCloud).
 * The bundled SQLite driver, like the content databases.
 */
@Database(entities = [HighlightEntity::class, BookmarkEntity::class, ActivityEntity::class], version = 1)
abstract class UserDatabase : RoomDatabase() {
    abstract fun dao(): UserDao

    companion object {
        const val NAME = "user.db"

        fun open(context: Context): UserDatabase =
            configure(Room.databaseBuilder(context, UserDatabase::class.java, NAME))

        fun inMemory(context: Context): UserDatabase =
            configure(Room.inMemoryDatabaseBuilder(context, UserDatabase::class.java))

        private fun configure(builder: Builder<UserDatabase>) =
            builder.setDriver(BundledSQLiteDriver()).setQueryCoroutineContext(Dispatchers.IO).build()
    }
}

/** [UserRecords] on Room. */
class RoomUserRecords(
    private val dao: UserDao,
) : UserRecords {
    override suspend fun all(table: UserRecords.Table): List<StoredRecord> =
        when (table) {
            UserRecords.Table.Highlights -> {
                dao.highlights().map {
                    StoredRecord(it.recordID, it.itemID, it.installationID, it.payload, it.modifiedAt, it.isTombstone)
                }
            }

            UserRecords.Table.Bookmarks -> {
                dao.bookmarks().map {
                    StoredRecord(it.recordID, it.itemID, it.installationID, it.payload, it.modifiedAt, it.isTombstone)
                }
            }
        }

    override suspend fun write(
        table: UserRecords.Table,
        rows: List<StoredRecord>,
    ) = when (table) {
        UserRecords.Table.Highlights -> {
            dao.upsertHighlights(
                rows.map {
                    HighlightEntity(
                        it.recordID,
                        it.itemID,
                        it.installationID,
                        it.payload,
                        it.modifiedAt,
                        it.isTombstone,
                    )
                },
            )
        }

        UserRecords.Table.Bookmarks -> {
            dao.upsertBookmarks(
                rows.map {
                    BookmarkEntity(
                        it.recordID,
                        it.itemID,
                        it.installationID,
                        it.payload,
                        it.modifiedAt,
                        it.isTombstone,
                    )
                },
            )
        }
    }
}
