#include "MCLADiagnostics.h"
#import <Foundation/Foundation.h>
#import "../ios/MCLASaveArchive.h"

static void Require(BOOL condition, NSString* message) {
    if (!condition) {
        if (mcla::DiagnosticsEnabled()) NSLog(@"FAIL: %@", message);
        abort();
    }
}

int main(void) {
    @autoreleasepool {
        NSFileManager* fm = NSFileManager.defaultManager;
        NSURL* root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:[@"MCLASaveArchiveTests-" stringByAppendingString:NSUUID.UUID.UUIDString]
            isDirectory:YES];
        NSURL* saves = [root URLByAppendingPathComponent:@"saves" isDirectory:YES];
        NSURL* profile = [saves URLByAppendingPathComponent:@"profile/slot1.bin"];
        NSURL* archive = [root URLByAppendingPathComponent:@"backup.mclasave"];
        NSURL* stage = [root URLByAppendingPathComponent:@"stage" isDirectory:YES];
        NSError* error = nil;
        Require([fm createDirectoryAtURL:[profile URLByDeletingLastPathComponent]
            withIntermediateDirectories:YES attributes:nil error:&error], @"create fixture");
        NSData* original = [@"known save data" dataUsingEncoding:NSUTF8StringEncoding];
        Require([original writeToURL:profile atomically:YES], @"write fixture");
        Require([MCLASaveArchive fileCountAtDirectory:saves] == 1, @"count nested saves");
        Require([MCLASaveArchive exportDirectory:saves toURL:archive error:&error], @"export saves");
        Require([MCLASaveArchive stageArchive:archive atDirectory:stage error:&error], @"stage saves");
        Require([[NSData dataWithContentsOfURL:[stage URLByAppendingPathComponent:@"profile/slot1.bin"]]
            isEqualToData:original], @"staged content intact");
        Require([@"changed" writeToURL:profile atomically:YES encoding:NSUTF8StringEncoding error:&error],
            @"change current save");
        Require([MCLASaveArchive replaceDirectory:saves withStagedDirectory:stage error:&error],
            @"replace saves");
        Require([[NSData dataWithContentsOfURL:profile] isEqualToData:original],
            @"import restored original");

        NSDictionary* malicious = @{@"format": @"MCLA-SAVES", @"version": @1,
            @"files": @{@"../escape.bin": original}, @"directories": @[]};
        NSData* badData = [NSPropertyListSerialization dataWithPropertyList:malicious
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
        NSURL* badArchive = [root URLByAppendingPathComponent:@"bad.mclasave"];
        Require([badData writeToURL:badArchive atomically:YES], @"write invalid archive");
        NSURL* badStage = [root URLByAppendingPathComponent:@"bad-stage" isDirectory:YES];
        Require(![MCLASaveArchive stageArchive:badArchive atDirectory:badStage error:&error],
            @"reject path traversal");
        Require([[NSData dataWithContentsOfURL:profile] isEqualToData:original],
            @"invalid archive did not change saves");
        Require([MCLASaveArchive deleteDirectory:saves error:&error], @"delete saves");
        Require(![fm fileExistsAtPath:saves.path], @"save directory removed");
        [fm removeItemAtURL:root error:nil];
        if (mcla::DiagnosticsEnabled()) NSLog(@"MCLASaveArchiveTests passed");
    }
    return 0;
}
