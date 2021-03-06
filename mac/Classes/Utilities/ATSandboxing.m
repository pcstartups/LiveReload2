
#import "ATSandboxing.h"
#import "NSData+Base64.h"

#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>
#include <assert.h>

NSString *ATRealHomeDirectory() {
    struct passwd *pw = getpwuid(getuid());
    assert(pw);
    return [NSString stringWithUTF8String:pw->pw_dir];
}

BOOL ATIsSandboxed() {
    return [NSHomeDirectory() compare:ATRealHomeDirectory() options:NSCaseInsensitiveSearch] != NSOrderedSame;
}

NSString *ATUserScriptsDirectory() {
    NSError *error = nil;
    if (ATIsUserScriptsFolderSupported()) {
        return [[[NSFileManager defaultManager] URLForDirectory:NSApplicationScriptsDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error] path];
    } else {
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        return [[ATRealHomeDirectory() stringByAppendingPathComponent:@"Library/Application Scripts"] stringByAppendingPathComponent:bundleId];
    }
}

NSURL *ATUserScriptsDirectoryURL() {
    NSError *error = nil;
    if (ATIsUserScriptsFolderSupported()) {
        return [[NSFileManager defaultManager] URLForDirectory:NSApplicationScriptsDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
    } else {
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        return [NSURL fileURLWithPath:[[ATRealHomeDirectory() stringByAppendingPathComponent:@"Library/Application Scripts"] stringByAppendingPathComponent:bundleId]];
    }
}

BOOL ATAreSecurityScopedBookmarksSupported() {
    return ATOSVersionAtLeast(10, 7, 3);
}
BOOL ATIsUserScriptsFolderSupported() {
    return ATOSVersionAtLeast(10, 8, 0);
}


NSString *ATOSVersionString() {
    static NSString *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        result = [[[NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"] objectForKey:@"ProductVersion"] copy];
    });
    return result;
}

int ATVersionMake(int major, int minor, int revision) {
    return major * (100 * 100) + minor * 100 + revision;
}

int ATOSVersion() {
    static int result;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *components = [[ATOSVersionString() stringByAppendingString:@".0.0.0"] componentsSeparatedByString:@"."];
        int major = [[components objectAtIndex:0] intValue];
        int minor = [[components objectAtIndex:1] intValue];
        int revision = [[components objectAtIndex:2] intValue];
        result = ATVersionMake(major, minor, revision);
    });
    return result;
}

BOOL ATOSVersionAtLeast(int major, int minor, int revision) {
    return ATOSVersion() >= ATVersionMake(major, minor, revision);
}
BOOL ATOSVersionLessThan(int major, int minor, int revision) {
    return ATOSVersion() < ATVersionMake(major, minor, revision);
}


NSURL *ATInitOrResolveSecurityScopedURL(NSMutableDictionary *memento, NSURL *newURL, ATSecurityScopedURLOptions options) {
    NSError *error;

    if (newURL) {
        [memento setObject:[[newURL path] stringByAbbreviatingTildeInPathUsingRealHomeDirectory] forKey:@"path"];  // solely for debugging and identification purposes; we'll always use a bookmark when available

        NSURLBookmarkCreationOptions o = NSURLBookmarkCreationWithSecurityScope;
        if ((options & ATSecurityScopedURLOptionsReadOnly) == ATSecurityScopedURLOptionsReadOnly)
            o |= NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess;
        NSData *bookmarkData = [newURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:@[NSURLPathKey] relativeToURL:nil error:&error];
        if (!bookmarkData) {
            [memento removeObjectForKey:@"bookmark"];
            NSLog(@"Failed to create a security-scoped bookmark for %@: %@", newURL, error);
        } else {
            [memento setObject:[bookmarkData base64EncodedString] forKey:@"bookmark"];
            NSLog(@"Created security-scoped bookmark for %@", newURL);
        }

        return newURL;
    } else {
        NSString *pathString = memento[@"path"];
        NSString *bookmarkString = memento[@"bookmark"];

        if (bookmarkString) {
            NSData *bookmark = [NSData dataFromBase64String:bookmarkString];

            BOOL stale = NO;
            NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithSecurityScope|NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
            if (!url) {
                NSString *bookmarkedPath = [NSURL resourceValuesForKeys:@[NSURLPathKey] fromBookmarkData:bookmark][NSURLPathKey];
                if (bookmarkedPath) {
                    NSLog(@"Failed to resolve a security-scoped bookmark for %@", bookmarkedPath);
                    return [NSURL fileURLWithPath:bookmarkedPath];
                } else {
                    NSLog(@"Failed to resolve a security-scoped bookmark for %@ (apparently the bookmark is completely invalid)", pathString);
                    return [NSURL fileURLWithPath:[pathString stringByExpandingTildeInPathUsingRealHomeDirectory]];
                }
            } else {
                if (stale) {
                    NSURLBookmarkCreationOptions o = NSURLBookmarkCreationWithSecurityScope;
                    if ((options & ATSecurityScopedURLOptionsReadOnly) == ATSecurityScopedURLOptionsReadOnly)
                        o |= NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess;
                    NSData *bookmarkData = [newURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:@[NSURLPathKey] relativeToURL:nil error:&error];
                    if (!bookmarkData) {
                        NSLog(@"Failed to update a security-scoped bookmark for %@: %@", newURL, error);
                    } else {
                        [memento setObject:[bookmarkData base64EncodedString] forKey:@"bookmark"];
                        NSLog(@"Updated security-scoped bookmark for %@", newURL);
                    }
                }

                return url;
            }
        } else if (pathString) {
            return [NSURL fileURLWithPath:[pathString stringByExpandingTildeInPathUsingRealHomeDirectory]];
        } else {
            return nil;
        }
    }
}



@implementation NSString (ATSandboxing)

- (NSString *)stringByAbbreviatingTildeInPathUsingRealHomeDirectory {
    NSString *realHome = ATRealHomeDirectory();

    NSUInteger ourLength = self.length;
    NSUInteger homeLength = realHome.length;

    if (ourLength < realHome.length)
        return self;
    if ([[self substringToIndex:homeLength] isEqualToString:realHome]) {
        if (ourLength == homeLength)
            return @"~";
        else if ([self characterAtIndex:homeLength] == '/')
            return [@"~" stringByAppendingString:[self substringFromIndex:homeLength]];
    }
    return self;
}

- (NSString *)stringByExpandingTildeInPathUsingRealHomeDirectory {
    NSString *realHome = ATRealHomeDirectory();
    if ([self length] > 0 && [self characterAtIndex:0] == '~') {
        if ([self length] == 1)
            return realHome;
        else if ([self characterAtIndex:1] == '/')
            return [realHome stringByAppendingPathComponent:[self substringFromIndex:2]];
    }
    return self;
}

@end
