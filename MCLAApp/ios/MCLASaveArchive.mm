#import "MCLASaveArchive.h"

namespace {
constexpr NSUInteger kMaximumArchiveBytes = 256u * 1024u * 1024u;
constexpr NSUInteger kMaximumFileBytes = 64u * 1024u * 1024u;
constexpr NSUInteger kMaximumEntries = 8192;
NSString* const kErrorDomain = @"MCLASaveArchive";

BOOL Fail(NSError** error, NSString* reason) {
    if (error) *error = [NSError errorWithDomain:kErrorDomain code:1
        userInfo:@{NSLocalizedDescriptionKey: reason}];
    return NO;
}

BOOL SafeRelativePath(NSString* path) {
    if (![path isKindOfClass:NSString.class] || path.length == 0 ||
        [path hasPrefix:@"/"] || [path containsString:@"\\"]) return NO;
    for (NSUInteger i = 0; i < path.length; ++i)
        if ([path characterAtIndex:i] == 0) return NO;
    for (NSString* part in [path componentsSeparatedByString:@"/"])
        if (part.length == 0 || [part isEqualToString:@"."] ||
            [part isEqualToString:@".."] || [part containsString:@":"]) return NO;
    return YES;
}

NSURL* UniqueSibling(NSURL* directory, NSString* label) {
    return [[directory URLByDeletingLastPathComponent] URLByAppendingPathComponent:
        [NSString stringWithFormat:@"%@-%@", label, NSUUID.UUID.UUIDString]
        isDirectory:YES];
}
}

@implementation MCLASaveArchive

+ (NSUInteger)fileCountAtDirectory:(NSURL*)directory {
    NSFileManager* fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:directory.path isDirectory:&isDirectory] || !isDirectory) return 0;
    NSUInteger count = 0;
    NSDirectoryEnumerator<NSURL*>* entries = [fm enumeratorAtURL:directory
        includingPropertiesForKeys:@[NSURLIsRegularFileKey] options:0 errorHandler:nil];
    for (NSURL* url in entries) {
        NSNumber* regular = nil;
        if ([url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil] &&
            regular.boolValue) ++count;
    }
    return count;
}

+ (BOOL)exportDirectory:(NSURL*)directory toURL:(NSURL*)archive error:(NSError**)error {
    NSFileManager* fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:directory.path isDirectory:&isDirectory] || !isDirectory)
        return Fail(error, @"No save directory exists yet.");
    NSMutableDictionary<NSString*,NSData*>* files = [NSMutableDictionary dictionary];
    NSMutableArray<NSString*>* directories = [NSMutableArray array];
    NSUInteger total = 0, count = 0;
    __block NSError* enumerationFailure = nil;
    NSString* basePath = [directory.URLByResolvingSymlinksInPath.path stringByAppendingString:@"/"];
    NSDirectoryEnumerator<NSURL*>* entries = [fm enumeratorAtURL:directory
        includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey,
                                     NSURLIsSymbolicLinkKey, NSURLFileSizeKey]
        options:0 errorHandler:^BOOL(NSURL* url, NSError* enumerationError) {
            (void)url;
            enumerationFailure = enumerationError;
            return NO;
        }];
    for (NSURL* url in entries) {
        if (++count > kMaximumEntries)
            return Fail(error, @"Too many save entries to export.");
        NSString* itemPath = url.URLByResolvingSymlinksInPath.path;
        if (![itemPath hasPrefix:basePath])
            return Fail(error, @"A save entry resolves outside the save directory.");
        NSString* relative = [itemPath substringFromIndex:basePath.length];
        if (!SafeRelativePath(relative))
            return Fail(error, @"A save has an unsafe path.");
        NSNumber *symlink = nil, *folder = nil, *regular = nil, *size = nil;
        if (![url getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:error] ||
            ![url getResourceValue:&folder forKey:NSURLIsDirectoryKey error:error] ||
            ![url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:error] ||
            ![url getResourceValue:&size forKey:NSURLFileSizeKey error:error]) return NO;
        if (symlink.boolValue) return Fail(error, @"Save symlinks cannot be exported.");
        if (folder.boolValue) {
            [directories addObject:relative];
        } else if (regular.boolValue) {
            if (size.unsignedLongLongValue > kMaximumFileBytes ||
                total + size.unsignedLongLongValue > kMaximumArchiveBytes)
                return Fail(error, @"Save data is too large to export.");
            NSData* data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
            if (!data) return NO;
            files[relative] = data;
            total += data.length;
        } else return Fail(error, @"Unsupported save entry type.");
    }
    if (enumerationFailure) {
        if (error) *error = enumerationFailure;
        return NO;
    }
    if (files.count == 0) return Fail(error, @"No save files exist yet.");
    NSDictionary* document = @{@"format": @"MCLA-SAVES", @"version": @1,
                               @"files": files, @"directories": directories};
    NSData* data = [NSPropertyListSerialization dataWithPropertyList:document
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    if (data.length > kMaximumArchiveBytes)
        return Fail(error, @"The save archive exceeds 256 MB.");
    return [data writeToURL:archive options:NSDataWritingAtomic error:error];
}

+ (BOOL)stageArchive:(NSURL*)archive atDirectory:(NSURL*)stage error:(NSError**)error {
    NSFileManager* fm = NSFileManager.defaultManager;
    NSDictionary* attributes = [fm attributesOfItemAtPath:archive.path error:error];
    if (!attributes) return NO;
    if ([attributes fileSize] > kMaximumArchiveBytes)
        return Fail(error, @"The selected archive exceeds 256 MB.");
    NSData* data = [NSData dataWithContentsOfURL:archive options:0 error:error];
    if (!data) return NO;
    id plist = [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:nil error:error];
    if (![plist isKindOfClass:NSDictionary.class] ||
        ![plist[@"format"] isEqual:@"MCLA-SAVES"] ||
        ![plist[@"version"] isEqual:@1] ||
        ![plist[@"files"] isKindOfClass:NSDictionary.class] ||
        ![plist[@"directories"] isKindOfClass:NSArray.class])
        return Fail(error, @"This is not a supported MCLA save archive.");
    NSDictionary* files = plist[@"files"];
    NSArray* directories = plist[@"directories"];
    if (files.count == 0 || files.count + directories.count > kMaximumEntries)
        return Fail(error, @"The archive contains no saves or too many entries.");
    NSUInteger total = 0;
    NSMutableSet<NSString*>* paths = [NSMutableSet set];
    for (id path in directories) {
        if (!SafeRelativePath(path) || [paths containsObject:path])
            return Fail(error, @"The archive contains an unsafe or duplicate directory.");
        [paths addObject:path];
    }
    for (id path in files) {
        id content = files[path];
        if (!SafeRelativePath(path) || ![content isKindOfClass:NSData.class] ||
            [paths containsObject:path] || [content length] > kMaximumFileBytes ||
            total + [content length] > kMaximumArchiveBytes)
            return Fail(error, @"The archive contains an unsafe or oversized save file.");
        [paths addObject:path];
        total += [content length];
    }
    if ([fm fileExistsAtPath:stage.path])
        return Fail(error, @"The temporary import directory already exists.");
    if (![fm createDirectoryAtURL:stage withIntermediateDirectories:YES
                       attributes:nil error:error]) return NO;
    for (NSString* path in directories) {
        if (![fm createDirectoryAtURL:[stage URLByAppendingPathComponent:path isDirectory:YES]
            withIntermediateDirectories:YES attributes:nil error:error]) {
            [fm removeItemAtURL:stage error:nil]; return NO;
        }
    }
    for (NSString* path in files) {
        NSURL* target = [stage URLByAppendingPathComponent:path];
        if (![fm createDirectoryAtURL:[target URLByDeletingLastPathComponent]
            withIntermediateDirectories:YES attributes:nil error:error] ||
            ![files[path] writeToURL:target options:NSDataWritingAtomic error:error]) {
            [fm removeItemAtURL:stage error:nil]; return NO;
        }
    }
    return YES;
}

+ (BOOL)replaceDirectory:(NSURL*)directory withStagedDirectory:(NSURL*)stage error:(NSError**)error {
    NSFileManager* fm = NSFileManager.defaultManager;
    BOOL stageIsDirectory = NO;
    if (![fm fileExistsAtPath:stage.path isDirectory:&stageIsDirectory] || !stageIsDirectory)
        return Fail(error, @"The imported save staging area is missing.");
    NSURL* backup = UniqueSibling(directory, @"saves-backup");
    const BOOL existed = [fm fileExistsAtPath:directory.path];
    if (existed && ![fm moveItemAtURL:directory toURL:backup error:error]) return NO;
    if (![fm moveItemAtURL:stage toURL:directory error:error]) {
        if (existed) [fm moveItemAtURL:backup toURL:directory error:nil];
        return NO;
    }
    if (existed) [fm removeItemAtURL:backup error:nil];
    return YES;
}

+ (BOOL)deleteDirectory:(NSURL*)directory error:(NSError**)error {
    NSFileManager* fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:directory.path]) return YES;
    return [fm removeItemAtURL:directory error:error];
}

@end
