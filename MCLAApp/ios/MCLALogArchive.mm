#import "MCLALogArchive.h"
#include <zlib.h>
#include <vector>

namespace {
void U16(NSMutableData* data, uint16_t value) {
    uint8_t bytes[] = {(uint8_t)value, (uint8_t)(value >> 8)};
    [data appendBytes:bytes length:2];
}
void U32(NSMutableData* data, uint32_t value) {
    U16(data, value & 65535); U16(data, value >> 16);
}
BOOL Fail(NSError** error, NSString* reason) {
    if (error) *error = [NSError errorWithDomain:@"MCLALogArchive" code:1
        userInfo:@{NSLocalizedDescriptionKey:reason}];
    return NO;
}
struct Entry { __strong NSData* name; uint32_t crc, size, offset; };
BOOL Add(NSFileHandle* output, NSString* name, NSURL* source, NSData* content,
         std::vector<Entry>& entries, NSError** error) {
    NSData* encoded = [name dataUsingEncoding:NSUTF8StringEncoding];
    if (encoded.length > UINT16_MAX || entries.size() >= UINT16_MAX)
        return Fail(error, @"Too many diagnostic entries or an oversized filename.");
    uint64_t offset = [output offsetInFile];
    if (offset > UINT32_MAX) return Fail(error, @"Diagnostic ZIP exceeds 4 GB.");
    NSMutableData* header = [NSMutableData data];
    U32(header, 0x04034b50); U16(header, 20); U16(header, 0x808);
    U16(header, 0); U16(header, 0); U16(header, 0x21);
    U32(header, 0); U32(header, 0); U32(header, 0);
    U16(header, encoded.length); U16(header, 0); [header appendData:encoded];
    [output writeData:header];
    NSFileHandle* input = source ? [NSFileHandle fileHandleForReadingFromURL:source error:error] : nil;
    if (source && !input) return NO;
    uint64_t size = 0;
    uint32_t crc = crc32(0, Z_NULL, 0);
    BOOL first = YES;
    for (;;) {
        @autoreleasepool {
            NSData* chunk = source ? [input readDataOfLength:65536] : (first ? content : nil);
            first = NO;
            if (!chunk.length) break;
            size += chunk.length;
            if (size > UINT32_MAX || [output offsetInFile] + chunk.length > UINT32_MAX - 16) {
                [input closeFile]; return Fail(error, @"Diagnostic ZIP exceeds 4 GB.");
            }
            crc = crc32(crc, (const Bytef*)chunk.bytes, (uInt)chunk.length);
            [output writeData:chunk];
        }
    }
    [input closeFile];
    NSMutableData* descriptor = [NSMutableData data];
    U32(descriptor, 0x08074b50); U32(descriptor, crc);
    U32(descriptor, size); U32(descriptor, size); [output writeData:descriptor];
    entries.push_back({encoded, crc, (uint32_t)size, (uint32_t)offset});
    return YES;
}
}

@implementation MCLALogArchive
+ (BOOL)exportHome:(NSURL*)home report:(NSString*)report toURL:(NSURL*)archive error:(NSError**)error {
    home = home.URLByResolvingSymlinksInPath;
    NSFileManager* fm = NSFileManager.defaultManager;
    if (![fm createFileAtPath:archive.path contents:nil attributes:nil])
        return Fail(error, @"Unable to create the diagnostic ZIP.");
    NSFileHandle* output = [NSFileHandle fileHandleForWritingToURL:archive error:error];
    if (!output) { [fm removeItemAtURL:archive error:nil]; return NO; }
    BOOL success = NO;
    @try {
        std::vector<Entry> entries;
        BOOL valid = Add(output, @"report.txt", nil,
            [report dataUsingEncoding:NSUTF8StringEncoding], entries, error);
        // Only known diagnostic locations. Text extensions exclude raw shader/game captures.
        NSArray* roots = @[@"Library/Application Support/MCLA", @"Documents/Diagnostics"];
        NSSet* extensions = [NSSet setWithArray:@[@"log", @"txt", @"csv", @"tsv", @"json", @"jsonl"]];
        for (NSString* relativeRoot in roots) {
            if (!valid) break;
            NSURL* root = [home URLByAppendingPathComponent:relativeRoot isDirectory:YES];
            BOOL directory = NO;
            if (![fm fileExistsAtPath:root.path isDirectory:&directory]) continue;
            NSNumber* rootLink = nil;
            [root getResourceValue:&rootLink forKey:NSURLIsSymbolicLinkKey error:error];
            if (!directory || rootLink.boolValue) { valid = Fail(error, @"Invalid diagnostic directory."); break; }
            __block NSError* enumerationError = nil;
            NSDirectoryEnumerator<NSURL*>* enumerator = [fm enumeratorAtURL:root
                includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey, NSURLIsDirectoryKey, NSURLIsRegularFileKey]
                options:0 errorHandler:^BOOL(NSURL* url, NSError* issue) {
                    (void)url; enumerationError = issue; return NO;
                }];
            for (NSURL* url in enumerator) {
                NSNumber *link = nil, *folder = nil, *regular = nil;
                if (![url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:error] ||
                    ![url getResourceValue:&folder forKey:NSURLIsDirectoryKey error:error] ||
                    ![url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:error]) { valid = NO; break; }
                if (link.boolValue) { if (folder.boolValue) [enumerator skipDescendants]; continue; }
                if (folder.boolValue) {
                    if ([relativeRoot hasPrefix:@"Library"] &&
                        [url.URLByDeletingLastPathComponent.URLByResolvingSymlinksInPath.path isEqual:root.URLByResolvingSymlinksInPath.path] &&
                        ![@[@"native-capture", @"native-frame-capture", @"diagnostics", @"logs"] containsObject:url.lastPathComponent.lowercaseString])
                        [enumerator skipDescendants];
                    continue;
                }
                if (!regular.boolValue || (![extensions containsObject:url.pathExtension.lowercaseString] &&
                    ![url.lastPathComponent.lowercaseString containsString:@".log."])) continue;
                NSString* base = [home.path stringByAppendingString:@"/"];
                if (![url.URLByResolvingSymlinksInPath.path hasPrefix:base]) {
                    valid = Fail(error, @"A diagnostic path resolves outside app storage."); break;
                }
                valid = Add(output, [url.URLByResolvingSymlinksInPath.path substringFromIndex:base.length], url, nil, entries, error);
                if (!valid) break;
            }
            if (enumerationError) { if (error) *error = enumerationError; valid = NO; }
        }
        // These launcher/render diagnostic reports live directly in Documents.
        for (NSString* name in @[@"mcla-render-probe.json", @"mcla-control-layout.json"]) {
            if (!valid) break;
            NSURL* url = [home URLByAppendingPathComponent:[@"Documents/" stringByAppendingString:name]];
            NSNumber *regular = nil, *link = nil;
            if (![fm fileExistsAtPath:url.path]) continue;
            valid = [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:error] &&
                [url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:error];
            if (valid && regular.boolValue && !link.boolValue)
                valid = Add(output, [@"Documents/" stringByAppendingString:name], url, nil, entries, error);
        }
        if (valid) {
            uint64_t centralOffset = [output offsetInFile];
            for (const Entry& entry : entries) {
                NSMutableData* header = [NSMutableData data];
                U32(header, 0x02014b50); U16(header, 20); U16(header, 20); U16(header, 0x808);
                U16(header, 0); U16(header, 0); U16(header, 0x21);
                U32(header, entry.crc); U32(header, entry.size); U32(header, entry.size);
                U16(header, entry.name.length); U16(header, 0); U16(header, 0);
                U16(header, 0); U16(header, 0); U32(header, 0); U32(header, entry.offset);
                [header appendData:entry.name]; [output writeData:header];
            }
            uint64_t centralSize = [output offsetInFile] - centralOffset;
            if (centralOffset + centralSize + 22 > UINT32_MAX) valid = Fail(error, @"Diagnostic ZIP exceeds 4 GB.");
            if (valid) {
                NSMutableData* end = [NSMutableData data];
                U32(end, 0x06054b50); U16(end, 0); U16(end, 0);
                U16(end, entries.size()); U16(end, entries.size());
                U32(end, centralSize); U32(end, centralOffset); U16(end, 0);
                [output writeData:end]; [output synchronizeFile]; success = YES;
            }
        }
    } @catch (NSException* exception) {
        Fail(error, [NSString stringWithFormat:@"Unable to export diagnostics: %@", exception.reason]);
    } @finally {
        [output closeFile];
        if (!success) [fm removeItemAtURL:archive error:nil];
    }
    return success;
}
@end
