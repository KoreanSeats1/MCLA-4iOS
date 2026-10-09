#import <Foundation/Foundation.h>

@interface MCLALogArchive : NSObject
// Streams a standard ZIP of diagnostic text files; never traverses game or save data.
+ (BOOL)exportHome:(NSURL*)home report:(NSString*)report toURL:(NSURL*)archive error:(NSError**)error;
@end
