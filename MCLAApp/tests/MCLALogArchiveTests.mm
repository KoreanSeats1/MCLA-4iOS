#import "../ios/MCLALogArchive.h"
int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSError* error = nil;
        BOOL ok = [MCLALogArchive exportHome:[NSURL fileURLWithPath:@(argv[1]) isDirectory:YES]
            report:@"Synthetic test report\n" toURL:[NSURL fileURLWithPath:@(argv[2])] error:&error];
        if (!ok) NSLog(@"%@", error);
        return ok ? 0 : 1;
    }
}
