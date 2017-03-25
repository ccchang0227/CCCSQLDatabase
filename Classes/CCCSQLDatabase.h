//
//  CCCSQLDatabase.h
//
//
//  Created by realtouchapp on 2017/3/24.
//
//

#import <Foundation/Foundation.h>
#import "FMDatabase.h"
#import "FMDatabaseQueue.h"

#if FMDB_SQLITE_STANDALONE
#import <sqlite3/sqlite3.h>
#else
#import <sqlite3.h>
#endif


/// 查詢所有欄位
#define CCCSQL_SELECTALLFIELDS @"*"

@protocol CCCSQLDatabaseDelegate;

/**
 資料庫
 
 @class CCCSQLDatabase
 @author Chih-chieh Chang
 @version 1.5.0
 @version FMDB Version 2.6.2
 @date 2017/03/24
 @see [FMDB on GitHub] https://github.com/ccgus/fmdb
 */
@interface CCCSQLDatabase : NSObject

+ (NSURL *)directoryURLWithDirectories:(NSString *)directories
                 inSearchPathDirectory:(NSSearchPathDirectory)searchPathDirectory;

- (instancetype)initWithFileName:(NSString *)dbFileName
                    directoryURL:(NSURL *)directoryURL
                        delegate:(id<CCCSQLDatabaseDelegate>)delegate NS_DESIGNATED_INITIALIZER;

/// 資料庫版本 (預設為1)
@property (assign, nonatomic) uint32_t dbVersion;
/// 資料庫檔案路徑
@property (readonly, copy, nonatomic) NSString *dbFilePath;

@property (readonly, retain, nonatomic) FMDatabaseQueue *dbQueue;

#pragma mark - For Override

/// dbQueue成功開啟時呼叫
- (void)onDatabaseOpenSuccessful;
/// 資料庫開啟/建立失敗時呼叫
- (void)onDatabaseOpenFailure;
/// 當資料庫需要版本更新時呼叫
- (void)onUpgradeFrom:(uint32_t)oldVersion
                   to:(uint32_t)newVersion;

#pragma mark -

/**
 刪除資料庫檔案並重建
 */
- (BOOL)reset;

/**
 新增資料
 For example:
 @code
 NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"CCC", @"newsID", @"CCCC44", @"type", nil];
 [self insertDictionaryWithTableName:kDBNewsTable dictionary:dict];
 @endcode
 
 @return 回傳值為RowID，若回傳為0表示新增失敗
 */
- (sqlite_int64)insertDictionaryWithTableName:(NSString *)table
                                   dictionary:(NSDictionary *)dataDic;

/**
 修改資料
 For example:
 {
 newsID = AAAA;
 type = BBBB44;
 }
 @code
 [self modifyDataWithTableName:kDBNewsTable dictionary:dict constraint:@"WHERE newsID=(?)", @"AAAA", nil];
 @endcode
 */
- (BOOL)modifyDataWithTableName:(NSString *)table
                     dictionary:(NSDictionary *)dataDic
                     constraint:(NSString *)sql, ... NS_REQUIRES_NIL_TERMINATION;

/**
 刪除全部資料
 For example:
 @code
 [self deleteDataWithTableName:kDBNewsTable constraint:nil];
 @endcode
 
 刪除指定資料
 For example:
 @code
 [self deleteDataWithTableName:kDBNewsTable constraint:@"WHERE newsID=(?)", @"ZZZ", nil];
 @endcode
 */
- (BOOL)deleteDataWithTableName:(NSString *)table
                     constraint:(NSString *)sql, ... NS_REQUIRES_NIL_TERMINATION;

/**
 刪除整個Table資料
 @warning (只刪除全部資料，不刪除Table，primary key會重新計算)
 */
- (BOOL)truncateTableWithTableName:(NSString *)table;

/**
 新建表單
 For example:
 @code
 [self addTables:@[kDBNewsTable] withFields:@[ @[@"newsID", @"type"] ] ];
 @endcode
 */
- (BOOL)addTables:(NSArray<NSString *> *)tables
       withFields:(NSArray<NSArray<NSString *> *> *)fields;

/**
 新建表單
 For example:
 @code
 [self addTables:@[kDBNewsTable] withFieldStrings:@[@"newsID,type"]];
 @endcode
 */
- (BOOL)addTables:(NSArray<NSString *> *)tables
 withFieldStrings:(NSArray<NSString *> *)fieldStrings;

/**
 新建表單
 For example:
 @code
 [self addTable:kDBNewsTable withFieldsString:@"newsID,type"];
 @endcode
 
 @warning fieldsString須以逗號隔開，且逗號前後不能有空白
 */
- (BOOL)addTable:(NSString *)table
withFieldsString:(NSString *)fieldsString;

/**
 新建表單
 For example:
 @code
 [self addTable:kDBNewsTable withFields:@[@"newsID", @"type"]];
 @endcode
 */
- (BOOL)addTable:(NSString *)table
      withFields:(NSArray<NSString *> *)fields;

/**
 刪除整個Table
 @warning (需要重新Create Table)
 */
- (BOOL)dropTableWithTableName:(NSString *)table;

/**
 讀取資料
 For example:
 {
 newsID = AAA'A44;
 type = BBBB44;
 }
 @code
 [self selectDataWithTableName:kDBNewsTable fields:kDBNewsField constraint:nil];
 [self selectDataWithTableName:kDBNewsTable fields:kDBNewsField constraint:@"WHERE newsID=(?)", @"AAA'A44", nil];
 @endcode
 */
- (NSMutableArray *)selectDataWithTableName:(NSString *)table
                                     fields:(NSString *)fields
                                 constraint:(NSString *)sql, ... NS_REQUIRES_NIL_TERMINATION;

/**
 讀取資料
 For example:
 {
 newsID = AAA'A44;
 type = BBBB44;
 }
 @code
 NSArray *arguments = @[@"AAA'A44"];
 [self selectDataWithTableName:kDBNewsTable fields:kDBNewsField constraint:@"WHERE newsID=(?)" arguments:arguments];
 @endcode
 */
- (NSMutableArray *)selectDataWithTableName:(NSString *)table
                                     fields:(NSString *)fields
                                 constraint:(NSString *)sql
                                  arguments:(NSArray *)arguments;

/**
 讀取資料筆數
 For example:
 {
 newsID = AAA'A44;
 type = BBBB44;
 }
 @code
 NSUInteger cnt = [self countDataWithTableName:kDBNewsTable constraint:@"WHERE applicationID=(?)", @"BBBB44", nil];
 NSLog(@"%d", cnt);
 @endcode
 */
- (NSUInteger)countDataWithTableName:(NSString *)table
                          constraint:(NSString *)sql, ... NS_REQUIRES_NIL_TERMINATION;

/**
 讀取資料筆數
 For example:
 {
 newsID = AAA'A44;
 type = BBBB44;
 }
 @code
 NSArray *arguments = @[@"AAA'A44"];
 [self selectDataWithTableName:kDBNewsTable fields:kDBNewsField constraint:@"WHERE applicationID=(?)" arguments:arguments];
 @endcode
 */
- (NSUInteger)countDataWithTableName:(NSString *)table
                          constraint:(NSString *)sql
                withArgumentsInArray:(NSArray *)arguments;

#pragma mark - For update table

/**
 表單更新時，新建欄位
 */
- (BOOL)addNewFields:(NSArray<NSString *> *)fieldNames intoTable:(NSString *)table;

/**
 表單更新時，修改欄位名稱
 */
- (BOOL)renameField:(NSString *)oldFieldName toNew:(NSString *)newFieldName inTable:(NSString *)table;

/**
 表單更新時，刪除欄位
 */
- (BOOL)deleteFields:(NSArray<NSString *> *)fieldNames inTable:(NSString *)table;

@end

@protocol CCCSQLDatabaseDelegate <NSObject>

- (void)cccSQLDatabase:(CCCSQLDatabase *)sqlDatabase shouldUpgradeDatabaseFrom:(uint32_t)oldVersion to:(uint32_t)newVersion;

@optional

- (void)cccSQLDatabaseDidOpen:(CCCSQLDatabase *)sqlDatabase;
- (void)cccSQLDatabaseOpenFailed:(CCCSQLDatabase *)sqlDatabase;

@end
