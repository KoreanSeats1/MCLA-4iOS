#import <Foundation/Foundation.h>

// A portable snapshot of the runtime's complete save directory. The runtime
// is never running while these launcher-only operations are available.
@interface MCLASaveArchive : NSObject
+ (NSUInteger)fileCountAtDirectory:(NSURL*)directory;
+ (BOOL)exportDirectory:(NSURL*)directory toURL:(NSURL*)archive error:(NSError**)error;
+ (BOOL)stageArchive:(NSURL*)archive atDirectory:(NSURL*)stage error:(NSError**)error;
+ (BOOL)replaceDirectory:(NSURL*)directory withStagedDirectory:(NSURL*)stage error:(NSError**)error;
+ (BOOL)deleteDirectory:(NSURL*)directory error:(NSError**)error;
@end
