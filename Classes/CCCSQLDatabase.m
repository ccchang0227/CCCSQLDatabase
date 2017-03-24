//
//  CCCSQLDatabase.m
//  
//
//  Created by realtouchapp on 2017/3/24.
//
//

#import "CCCSQLDatabase.h"


#define kCCCDefaultDBVersion 1

@interface CCCSQLDatabase ()

@property (retain, nonatomic) NSMutableDictionary<NSString *, NSArray<NSString *> *> *tablesAndFields;

@property (assign, nonatomic) id delegate;

@end

@implementation CCCSQLDatabase

+ (NSURL *)directoryURLWithDirectories:(NSString *)directories
                 inSearchPathDirectory:(NSSearchPathDirectory)searchPathDirectory {
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NS_DURING
    NSURL *appUrl = [[fileManager URLsForDirectory:searchPathDirectory inDomains:NSUserDomainMask] lastObject];
    if (!directories || directories.length == 0) {
        return appUrl;
    }
    
    appUrl = [appUrl URLByAppendingPathComponent:directories];
    if (![fileManager fileExistsAtPath:appUrl.path]) {
        if(![fileManager createDirectoryAtPath:appUrl.path withIntermediateDirectories:YES attributes:nil error:nil]) {
            appUrl = [[fileManager URLsForDirectory:searchPathDirectory inDomains:NSUserDomainMask] lastObject];
        }
    }
    
    return appUrl;
    
    NS_HANDLER
    NS_ENDHANDLER
    
    return [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (instancetype)init {
    NSURL *directoryURL = [CCCSQLDatabase directoryURLWithDirectories:nil inSearchPathDirectory:NSDocumentDirectory];
    return [self initWithFileName:@"Database" directoryURL:directoryURL delegate:nil];
}

- (instancetype)initWithFileName:(NSString *)dbFileName
                    directoryURL:(NSURL *)directoryURL
                        delegate:(id<CCCSQLDatabaseDelegate>)delegate {
    
    self = [super init];
    if (self) {
        _tablesAndFields = [[NSMutableDictionary alloc] init];
        
        if (!dbFileName || dbFileName.length == 0) {
            dbFileName = @"Database";
        }
        if (!directoryURL || directoryURL.path.length == 0) {
            directoryURL = [CCCSQLDatabase directoryURLWithDirectories:nil inSearchPathDirectory:NSDocumentDirectory];
        }
        
        dbFileName = [NSString stringWithFormat:@"%@.db", dbFileName];
        NSString *dbPath = [directoryURL.path stringByAppendingPathComponent:dbFileName];
        
        [self createDatabaseQueueWithPath:dbPath];
    }
    
    return self;
}

- (void)dealloc {
    _delegate = nil;
    [_tablesAndFields removeAllObjects];
    
    [_tablesAndFields release];
    [_dbFilePath release];
    [_dbQueue release];
    [super dealloc];
}

- (BOOL)createDatabaseQueueWithPath:(NSString *)dbPath {
    if (_dbQueue) {
        [_dbQueue release];
    }
    
    _dbQueue = [[FMDatabaseQueue alloc] initWithPath:dbPath];
    
    if (_dbFilePath) {
        [_dbFilePath release];
    }
    if (!_dbQueue) {
        _dbFilePath = nil;
        
        [self onDatabaseOpenFailure];
        if (self.delegate && [self.delegate respondsToSelector:@selector(cccSQLDatabaseOpenFailed:)]) {
            [self.delegate cccSQLDatabaseOpenFailed:self];
        }
        
        return NO;
    }
    else {
        _dbFilePath = [dbPath copy];
        
        [self onDatabaseOpenSuccessful];
        if (self.delegate && [self.delegate respondsToSelector:@selector(cccSQLDatabaseDidOpen:)]) {
            [self.delegate cccSQLDatabaseDidOpen:self];
        }
        
        return YES;
    }
    
}

- (BOOL)reset {
    if (!self.dbQueue) {
        return NO;
    }
    
    uint32_t dbVersion = self.dbVersion;
    NSDictionary<NSString *, NSArray<NSString *> *> *tablesAndFields = [NSDictionary dictionaryWithDictionary:self.tablesAndFields];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:self.dbFilePath]) {
        [fileManager removeItemAtPath:self.dbFilePath error:nil];
    }
    
    [self.tablesAndFields removeAllObjects];
    
    if ([self createDatabaseQueueWithPath:self.dbFilePath]) {
        [tablesAndFields enumerateKeysAndObjectsUsingBlock:^(NSString *table, NSArray<NSString *> *fields, BOOL *stop) {
           
            [self addTable:table withFields:fields];
            
        }];
        self.dbVersion = dbVersion;
        
        return YES;
    }
    
    return NO;
}

#pragma mark - For Override

- (void)onDatabaseOpenSuccessful {
}

- (void)onDatabaseOpenFailure {
}

- (void)onUpgradeFrom:(uint32_t)oldVersion to:(uint32_t)newVersion {
}

#pragma mark - 版本升級

- (uint32_t)dbVersion {
    __block uint32_t r = 0;
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"pragma user_version"];
        
        if ([rs next]) {
            r = (uint32_t)[rs longLongIntForColumnIndex:0];
        }
        [rs close];
    }];
    return r;
}

- (void)setDbVersion:(uint32_t)dbVersion {
    if (![self checkVersion:dbVersion]) {
        
        [self onUpgradeFrom:self.dbVersion to:dbVersion];
        if (self.delegate && [self.delegate respondsToSelector:@selector(cccSQLDatabase:shouldUpgradeDatabaseFrom:to:)]) {
            [self.delegate cccSQLDatabase:self shouldUpgradeDatabaseFrom:self.dbVersion to:dbVersion];
        }
        
    }
    
    [self updateDbVersion:dbVersion];
}

- (void)updateDbVersion:(uint32_t)dbVersion {
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        NSString *query = [NSString stringWithFormat:@"pragma user_version = %d", dbVersion];
        BOOL success = [db executeUpdate:query];
        if (!success) {
            NSLog(@"Error %d: %@", [db lastErrorCode], [db lastErrorMessage]);
        }
    }];
}

- (BOOL)checkVersion:(uint32_t)dbVersion {
    if (self.dbVersion == 0) {
        self.dbVersion = kCCCDefaultDBVersion;
    }
    else {
        if (self.dbVersion != dbVersion) {
            return NO;
        }
    }
    
    return YES;
}

#pragma mark - 新增資料

- (sqlite_int64)insertDictionaryWithTableName:(NSString *)table dictionary:(NSDictionary *)dicData {
    
    __block sqlite_int64 rowID = 0;
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        rowID = [self insertWithDB:db tableName:table dictionary:dicData];
    }];
    return rowID;
}

#pragma mark - 修改資料

- (BOOL)modifyDataWithTableName:(NSString *)table
                     dictionary:(NSDictionary *)dataDic
                     constraint:(NSString*)sql, ... {
    
    //分析輸入參數
    NSMutableArray *argsArray = [[NSMutableArray alloc] init];
    va_list args;
    va_start(args, sql);
    id arg;
    if (sql) {
        while ((arg = va_arg(args, id))) {
            if (arg) {
                [argsArray addObject:arg];
            }
        }
    }
    va_end(args);
    
    __block BOOL modifySuccess = NO;
    
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        if ([self isStringNotEmpty:table]) {
            NSArray *fields = [self.tablesAndFields objectForKey:table];
            if (fields && fields.count > 0) {
                
                //有資料則修改，無資料就新增
                NSInteger intTotalCnt = [self countDataWithDB:db tableName:table constraint:sql withArgumentsInArray:argsArray];
                if (intTotalCnt == 0) {
                    sqlite_int64 rowID = [self insertWithDB:db tableName:table dictionary:dataDic];
                    if (rowID > 0) {
                        modifySuccess = YES;
                    }
                    else {
                        modifySuccess = NO;
                    }
                }
                else {
                    NSMutableArray *columnAndPlaceholders = [[NSMutableArray alloc] init];
                    NSMutableArray *values = [[NSMutableArray alloc] init];
                    
                    for (NSString *fieldName in fields) {
                        NSString *value = [dataDic objectForKey:fieldName];
                        if (value) {
                            [columnAndPlaceholders addObject:[NSString stringWithFormat:@"%@ = ?", fieldName]];
                            [values addObject:[NSString stringWithFormat:@"%@", value]];
                        }
                    }
                    NSString *strColumnAndPlaceholder = [columnAndPlaceholders componentsJoinedByString:@","];
                    NSMutableString *sqlString = [NSMutableString stringWithFormat:@"UPDATE %@ SET %@", table, strColumnAndPlaceholder];
                    
                    if ([self isStringNotEmpty:sql]) {
                        [sqlString appendFormat:@" %@", sql];
                        [values addObjectsFromArray:argsArray];
                    }
                    
                    //值要用?當參數取代，避免值裡面有特殊符號問題，值不可在executeUpdate前就先用%@取代掉
                    modifySuccess = [db executeUpdate:sqlString withArgumentsInArray:values];
                    
                    [columnAndPlaceholders release];
                    [values release];
                    
                    if (!modifySuccess) {
                        NSLog(@"Error %d: %@", [db lastErrorCode], [db lastErrorMessage]);
                    }
                }
            }
            else {
                modifySuccess = NO;
            }
        }
        else {
            modifySuccess = NO;
        }
    }];
    [argsArray release];
    
    return modifySuccess;
}

#pragma mark - 刪除資料

- (BOOL)deleteDataWithTableName:(NSString *)table
                     constraint:(NSString *)sql, ... {
    
    //分析輸入參數
    NSMutableArray *argsArray = [[NSMutableArray alloc] init];
    va_list args;
    va_start(args, sql);
    id arg;
    if (sql) {
        while ((arg = va_arg(args, id))) {
            if (arg) {
                [argsArray addObject:arg];
            }
        }
    }
    va_end(args);
    
    __block BOOL success = NO;
    
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        if ([self isStringNotEmpty:sql]) {
            
            if ([self isStringNotEmpty:table]) {
                NSMutableString *sqlString = [NSMutableString stringWithFormat:@"DELETE FROM %@ %@", table, sql];
                //值要用?當參數取代，避免值裡面有特殊符號問題，值不可在executeUpdate前就先用%@取代掉
                success = [db executeUpdate:sqlString withArgumentsInArray:argsArray];
                if (!success) {
                    NSLog(@"Error %d: %@", [db lastErrorCode], [db lastErrorMessage]);
                }
            }
            else {
                success = NO;
            }
        }
        else {
            success = [self truncateWithDB:db tableName:table];
        }
    }];
    [argsArray release];
    
    return success;
}

- (BOOL)truncateTableWithTableName:(NSString *)table {
    __block BOOL success = NO;
    
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        success = [self truncateWithDB:db tableName:table];
    }];
    return success;
}

#pragma mark - 建立/刪除表單

- (BOOL)addTables:(NSArray<NSString *> *)tables withFields:(NSArray<NSArray<NSString *> *> *)fields {
    if (!tables || tables.count == 0 ||
        !fields || fields.count == 0 ||
        tables.count != fields.count) {
        return NO;
    }
    
    BOOL success = NO;
    
    for (int i = 0; i < tables.count; i ++) {
        NSString *table = [tables objectAtIndex:i];
        NSArray<NSString *> *field = [fields objectAtIndex:i];
        success &= [self addTable:table withFields:field];
    }
    
    return success;
}

- (BOOL)addTables:(NSArray<NSString *> *)tables withFieldStrings:(NSArray<NSString *> *)fieldStrings {
    if (!tables || tables.count == 0 ||
        !fieldStrings || fieldStrings.count == 0 ||
        tables.count != fieldStrings.count) {
        return NO;
    }
    
    BOOL success = NO;
    
    for (int i = 0; i < tables.count; i ++) {
        NSString *table = [tables objectAtIndex:i];
        NSString *fieldString = [fieldStrings objectAtIndex:i];
        success &= [self addTable:table withFieldsString:fieldString];
    }
    
    return success;
}

- (BOOL)addTable:(NSString *)table withFieldsString:(NSString *)fieldsString {
    return [self addTable:table withFields:[fieldsString componentsSeparatedByString:@","]];
}

- (BOOL)addTable:(NSString *)table withFields:(NSArray<NSString *> *)fields {
    if (![self isStringNotEmpty:table] || !fields || fields.count == 0) {
        return NO;
    }
    
    NSString *fieldsString = [[fields componentsJoinedByString:@" text,"] stringByAppendingString:@" text"];
    
    __block BOOL success = NO;
    
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        
        NSString *sqlString = [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (uid integer primary key asc autoincrement, %@)", table, fieldsString];
        
        success = [db executeUpdate:sqlString];
        if (!success) {
            NSLog(@"Could not create table: %@", [db lastErrorMessage]);
        }
        
    }];
    
    if (success) {
        [self.tablesAndFields setObject:fields forKey:table];
    }
    
    return success;
}

- (BOOL)dropTableWithTableName:(NSString *)table {
    __block BOOL success = NO;
    
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        if ([self isStringNotEmpty:table]) {
            NSMutableString *sqlString = [NSMutableString stringWithFormat:@"DROP TABLE %@", table];
            success = [db executeUpdate:sqlString];
            if (!success) {
                NSLog(@"Error %d: %@", [db lastErrorCode], [db lastErrorMessage]);
            }
        }
        else {
            success = NO;
        }
    }];
    
    if (success) {
        [self.tablesAndFields removeObjectForKey:table];
    }
    
    return success;
}

#pragma mark - 讀取資料

- (NSMutableArray *)selectDataWithTableName:(NSString *)table
                                     fields:(NSString *)fields
                                 constraint:(NSString *)sql, ... {
    
    //分析輸入參數
    NSMutableArray *argsArray = [[NSMutableArray alloc] init];
    va_list args;
    va_start(args, sql);
    id arg;
    if (sql) {
        while ((arg = va_arg(args, id))) {
            if (arg) {
                [argsArray addObject:arg];
            }
        }
    }
    va_end(args);
    
    NSMutableArray *results = [self selectDataWithTableName:table fields:fields constraint:sql arguments:argsArray];
    [argsArray release];
    
    return results;
}

- (NSMutableArray *)selectDataWithTableName:(NSString *)table
                                     fields:(NSString *)fields
                                 constraint:(NSString *)sql
                                  arguments:(NSArray *)arguments {
    
    __block NSMutableArray *results = [[NSMutableArray alloc] init];
    
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        
        if ([self isStringNotEmpty:table] && [self isStringNotEmpty:fields]) {
            
            NSMutableString *sqlString = [NSMutableString stringWithFormat:@"SELECT %@ FROM %@", fields, table];
            if ([self isStringNotEmpty:sql]) {
                [sqlString appendFormat:@" %@", sql];
            }
            
            FMResultSet *appointmentResults = [db executeQuery:sqlString withArgumentsInArray:arguments];
            while ([appointmentResults next]) {
                NSMutableDictionary *resultDic = [NSMutableDictionary dictionaryWithDictionary:[appointmentResults resultDictionary]];
                NSArray *allKeys = [resultDic allKeys];
                for (int i = 0; i < allKeys.count; i++) {
                    NSString *strKey = [allKeys objectAtIndex:i];
                    NSString *value = [resultDic objectForKey:strKey];
                    if (![self isStringNotEmpty:value]) {
                        [resultDic removeObjectForKey:strKey];
                    }
                }
                [results addObject:resultDic];
            }
            [appointmentResults close];
        }
    }];
    
    return [results autorelease];
}

#pragma mark - 計算筆數

- (NSUInteger)countDataWithTableName:(NSString *)table
                          constraint:(NSString *)sql, ... {
    
    //分析輸入參數
    NSMutableArray *argsArray = [[NSMutableArray alloc] init];
    va_list args;
    va_start(args, sql);
    id arg;
    if (sql) {
        while ((arg = va_arg(args, id))) {
            if (arg) {
                [argsArray addObject:arg];
            }
        }
    }
    va_end(args);
    
    __block NSUInteger totalCount = 0;
    
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        totalCount = [self countDataWithDB:db tableName:table constraint:sql withArgumentsInArray:argsArray];
    }];
    [argsArray release];
    
    return totalCount;
}

- (NSUInteger)countDataWithTableName:(NSString *)table
                          constraint:(NSString *)sql
                withArgumentsInArray:(NSArray *)arguments {
    
    __block NSUInteger totalCount = 0;
    
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        totalCount = [self countDataWithDB:db tableName:table constraint:sql withArgumentsInArray:arguments];
    }];
    return totalCount;
}

#pragma mark - Private

- (sqlite_int64)insertWithDB:(FMDatabase *)db
                   tableName:(NSString *)table
                  dictionary:(NSDictionary *)dataDic {
    
    sqlite_int64 rowID = 0;
    
    if ([self isStringNotEmpty:table]) {
        NSArray *fields = [self.tablesAndFields objectForKey:table];
        if (fields && fields.count > 0) {
            NSMutableArray *columns = [[NSMutableArray alloc] init];
            NSMutableArray *valPlaceholders = [[NSMutableArray alloc] init];
            NSMutableArray *values = [[NSMutableArray alloc] init];
            
            for (NSString *fieldName in fields) {
                NSString *value = [dataDic objectForKey:fieldName];
                if ([self isStringNotEmpty:value]) {
                    [columns addObject:[NSString stringWithFormat:@"%@", fieldName]];
                    [valPlaceholders addObject:[NSString stringWithFormat:@"?"]];
                    [values addObject:[NSString stringWithFormat:@"%@", value]];
                }
            }
            
            NSString *keyString = [columns componentsJoinedByString:@","];
            NSString *valPlaceholderString = [valPlaceholders componentsJoinedByString:@","];
            NSString *sqlString = [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@)", table, keyString, valPlaceholderString];
            
            //值要用?當參數取代，避免值裡面有特殊符號問題，值不可在executeUpdate前就先用%@取代掉
            BOOL successDB = [db executeUpdate:sqlString withArgumentsInArray:values];
            
            [columns release];
            [valPlaceholders release];
            [values release];
            
            if (successDB) {
                rowID = [db lastInsertRowId];
            }
            else {
                NSLog(@"Error %d: %@", [db lastErrorCode], [db lastErrorMessage]);
                rowID = 0;
            }
        }
        else {
            rowID = 0;
        }
    }
    else {
        rowID = 0;
    }
    
    return rowID;
}

- (BOOL)truncateWithDB:(FMDatabase *)db
             tableName:(NSString *)table {
    
    BOOL success = NO;
    
    if ([self isStringNotEmpty:table]) {
        NSString *sqlString = [NSString stringWithFormat:@"DELETE FROM %@", table];
        BOOL successDB = [db executeUpdate:sqlString];
        if (successDB) {
            [db executeUpdate:@"DELETE FROM sqlite_sequence WHERE name = ?", table];
            success = YES;
        }
        else {
            NSLog(@"Error %d: %@", [db lastErrorCode], [db lastErrorMessage]);
            success = NO;
        }
    }
    else {
        success = NO;
    }
    return success;
}

- (NSUInteger)countDataWithDB:(FMDatabase *)db
                    tableName:(NSString *)table
                   constraint:(NSString *)sql
         withArgumentsInArray:(NSArray *)arguments {
    
    NSUInteger totalCount = 0;
    
    if ([self isStringNotEmpty:table]) {
        NSMutableString *sqlString = [NSMutableString stringWithFormat:@"SELECT COUNT(*) FROM %@", table];
        if ([self isStringNotEmpty:sql]) {
            [sqlString appendFormat:@" %@", sql];
        }
        
        FMResultSet *appointmentResults = [db executeQuery:sqlString withArgumentsInArray:arguments];
        if ([appointmentResults next]) {
            totalCount = [appointmentResults intForColumnIndex:0];
        }
        else {
            totalCount = 0;
        }
        [appointmentResults close];
    }
    else {
        totalCount = 0;
    }
    
    return totalCount;
}

- (BOOL)isStringNotEmpty:(NSString *)string {
    if (((NSNull *)string == [NSNull null]) || (string == nil)) {
        return NO;
    }
    if ([string isKindOfClass:[NSString class]]) {
        string = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([string length] == 0) { //string is empty or nil
            return NO;
        }
    }
    return YES;
}

@end
