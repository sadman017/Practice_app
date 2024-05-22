import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:practice_app/Services/crud/crud_exception.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' show join;


class NotesService{
  Database? _db;
  List<DatabaseNote> _notes = [];

  final _notesStreamController =
    StreamController<List<DatabaseNote>>.broadcast();

  Future<DatabaseUser> getOrCreateUser({required String email}) async{
    try{
      final user =await getUser(email: email);
      return user;
    } on UserDoesNotExist{
      final createdUser = await createUser(email: email);
      return createdUser;
    } catch (e)  {
      rethrow;
    }
  }

  Future<void> _cacheNotes() async{
    final allNotes = await getAllNotes();
    _notes = allNotes.toList();
    _notesStreamController.add(_notes);
  }

  Future <void> deleteUser({required String email}) async{
    final db = _getDatabaseOrThrow();
    final deleteCount = await db.delete(
      userTable, 
      where: 'email =?', 
      whereArgs: [email.toLowerCase()],
      );
      if(deleteCount != 1){
        throw CouldNotDeleteUser();
      }
  }

  Future <DatabaseUser>createUser({required String email}) async{
    final db = _getDatabaseOrThrow();
    final results = await db.query(
      userTable,
      limit: 1,
      where: 'email =?',
      whereArgs: [email.toLowerCase()], 
      );
      if(results.isNotEmpty){
        throw UserAlreadyExists();
      }
      final userId = await db.insert(
        userTable,{
         emailColumn: email.toLowerCase()});

      return DatabaseUser(
        id: userId, 
        email: email,
        );
  }
  
  Database _getDatabaseOrThrow(){
    final db = _db;
    if(db == null){
      throw DatabaseIsNotOpen();
    }
    return db;
  }

  Future<DatabaseUser>getUser({required String email}) async{
    final db = _getDatabaseOrThrow();
    final results = await db.query(
      userTable,
      limit: 1,
      where: 'email =?',
      whereArgs: [email.toLowerCase()], 
      );
      if(results.isEmpty){
        throw UserDoesNotExist();
      } else{
        return DatabaseUser.fromRow(results.first);
      }
      
  }

  Future<DatabaseNote>createNote({required DatabaseUser owner}) async{

    final db = _getDatabaseOrThrow();
    
    final dbUser = await getUser(email: owner.email);
    if(dbUser != owner){
      throw UserDoesNotExist();
    }

    const text =" ";
    final noteId = await db.insert(
      noteTable,{
        userIdColumn: owner.id,
        textColumn: text,
        isSyncedWithCloudColumn: 1,
        });

      final note = DatabaseNote(
        id: noteId, 
        text: text, 
        userId: owner.id, 
        isSyncedWithCloud: true,
        );

        _notes.add(note);
        _notesStreamController.add(_notes);
        return note;
  }

  Future <void> deleteNote({required int id}) async{
    final db = _getDatabaseOrThrow();
    final deleteCount = await db.delete(
      noteTable, 
      where: 'id =?', 
      whereArgs: [id],
      );
      if(deleteCount == 0){
        throw CouldNotDeleteNote();
      }else{
        _notes.removeWhere((note) => note.id == id);
        _notesStreamController.add(_notes);
      }
  }

  Future<int> deleteAllNotes() async{
    final db = _getDatabaseOrThrow();
    final numberOfDeletion = await db.delete(noteTable);
    _notes = [];
    _notesStreamController.add(_notes);
    return numberOfDeletion;
  }

  Future<DatabaseNote> getNote({required int id}) async{
    final db = _getDatabaseOrThrow();
    final notes = await db.query(noteTable,
      where: "id =?",
      limit: 1,
      whereArgs: [id],

    );
    if(notes.isEmpty){
      throw NoteDoesNotExist();
    }else{
      final note = DatabaseNote.fromRow(notes.first);
      _notes.removeWhere((note) => note.id == id);
      _notes.add(note);
      _notesStreamController.add(_notes);
      return note;
    }
  }

  Future<Iterable<DatabaseNote>> getAllNotes() async{
    final db = _getDatabaseOrThrow();
    final notes = await db.query(noteTable);

    return notes.map((noteRow) => DatabaseNote.fromRow(noteRow));
  }

  Future<DatabaseNote> updateNote({
    required DatabaseNote note,
    required String text,
  }) async{
    final db = _getDatabaseOrThrow();
    await getNote(id: note.id);

    final updatesCount = db.update(noteTable,{
      textColumn:text,
      isSyncedWithCloudColumn: 0,
    });
    if(updatesCount == 0){
      throw CouldNotUpdateNote();
    }else{
      final updatedNote = await getNote(id: note.id);
        _notes.removeWhere((note) => note.id == updatedNote.id);
        _notes.add(updatedNote);
        _notesStreamController.add(_notes);
        return updatedNote;

    }
    
  }

  Future<void> close() async{
    if(_db == null){
      throw DatabaseIsNotOpen();
    }else{
      await _db!.close();
      _db = null;
    }
  }

  Future<void> open() async{
    if(_db != null){
      throw DatabaseAlreadyOpenException();
    }

    try{
      final docsPath = await getApplicationCacheDirectory();
      final dbPath = join(docsPath.path, dbName);
      final db = await openDatabase(dbPath);
      _db = db;

      await db.execute(createUserTable);

      await db.execute(createNoteTable);
      await _cacheNotes();

    } on MissingPlatformDirectoryException{
      throw UnableToGetDocumentsDirectory();
    }
  }
}

@immutable
class DatabaseUser{
  final int id;
  final String email;
  const DatabaseUser({
    required this.id,
    required this.email,
  });

  DatabaseUser.fromRow(Map<String, Object?> map)
  : id = map[idColumn] as int,
    email = map[emailColumn] as String;

  @override
  String toString() => "Person, ID = $id, email = $email";

  @override
  bool operator ==(covariant DatabaseUser other) => id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class DatabaseNote{
  final int id;
  final String text;
  final int userId;
  final bool isSyncedWithCloud;

  DatabaseNote({
    required this.id, 
    required this.text, 
    required this.userId, 
    required this.isSyncedWithCloud,
    });

  DatabaseNote.fromRow(Map<String, Object?> map)
  : id = map[idColumn] as int,
    text = map[textColumn] as String,
    userId = map[userIdColumn] as int,
    isSyncedWithCloud = 
    (map[isSyncedWithCloudColumn] as int) == 1 ? true :  false;

  @override
  String toString() => "Note, Id = $id, userId = $userId, isSyncedWithCloud =$isSyncedWithCloud, text =$text";

  @override
  bool operator ==(covariant DatabaseNote other) => id == other.id;

   @override
  int get hashCode => id.hashCode;
}

const dbName = "notes.db";
const noteTable = "note";
const userTable = "user";
const idColumn = 'id';
const emailColumn = 'email';
const userIdColumn = 'user_id';
const textColumn = 'text';
const isSyncedWithCloudColumn = 'is_synced_with_cloud';
const createUserTable = '''CREATE TABLE IF NOT EXISTS "user" (
        "id"	INTEGER NOT NULL,
        "email"	TEXT NOT NULL UNIQUE,
        PRIMARY KEY("id" AUTOINCREMENT)
      ); ''';

const createNoteTable = '''CREATE TABLE IF NOT EXISTS "note" (
        "id"	INTEGER NOT NULL,
	      "user_id"	INTEGER NOT NULL,
	      "text"	TEXT,
	      "is_synced_with_cloud"	INTEGER NOT NULL,
	      FOREIGN KEY("user_id") REFERENCES "user"("id"),
	      PRIMARY KEY("id" AUTOINCREMENT)
      ); ''';
