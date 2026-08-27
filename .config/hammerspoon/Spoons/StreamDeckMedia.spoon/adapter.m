// Now-playing metadata out of MediaRemote, as one line of JSON on stdout.
//
// MediaRemote is private, and since macOS 15.4 it hands nothing back to a caller
// that is not an Apple-signed binary: Hammerspoon asking directly gets a callback
// with nil, whether or not something is playing. The gate looks at the host
// process, so this is built as a dylib to be loaded into one that passes —
// /usr/bin/perl, which is an Apple platform binary and carries no library
// validation flag, so it will load an unsigned dylib. See adapter.pl.
//
// mr_run is shaped like a perl XSUB so dl_install_xsub can call it. It must run on
// perl's own thread rather than from a constructor: blocking inside a dylib
// constructor deadlocks against the loader lock, and the XPC reply never arrives.
//
// Artwork is written to a file rather than embedded in the JSON, one file per
// artwork identifier, so a poll costs no image bytes and repeated polls of the same
// track cost no writes.

#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*MRGetInfo)(dispatch_queue_t, void (^)(NSDictionary *));

static NSString *const kTitle      = @"kMRMediaRemoteNowPlayingInfoTitle";
static NSString *const kArtist     = @"kMRMediaRemoteNowPlayingInfoArtist";
static NSString *const kAlbum      = @"kMRMediaRemoteNowPlayingInfoAlbum";
static NSString *const kDuration   = @"kMRMediaRemoteNowPlayingInfoDuration";
static NSString *const kElapsed    = @"kMRMediaRemoteNowPlayingInfoElapsedTime";
static NSString *const kRate       = @"kMRMediaRemoteNowPlayingInfoPlaybackRate";
static NSString *const kTimestamp  = @"kMRMediaRemoteNowPlayingInfoTimestamp";
static NSString *const kArtData    = @"kMRMediaRemoteNowPlayingInfoArtworkData";
static NSString *const kArtMIME    = @"kMRMediaRemoteNowPlayingInfoArtworkMIMEType";
static NSString *const kArtID      = @"kMRMediaRemoteNowPlayingInfoArtworkIdentifier";

static void emit(NSDictionary *out) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:NULL];
    if (json) fwrite(json.bytes, 1, json.length, stdout);
    else fputs("{\"error\":\"encode\"}", stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id typed(NSDictionary *d, NSString *key, Class cls) {
    id v = d[key];
    return [v isKindOfClass:cls] ? v : nil;
}

// Extension from the MIME type the session reported, so the cached file is named
// what it actually is; the Lua side reads the path back out of the JSON and does
// not care either way.
static NSString *extensionForMIME(NSString *mime) {
    if ([mime isEqualToString:@"image/png"]) return @"png";
    if ([mime isEqualToString:@"image/jpeg"]) return @"jpg";
    return @"img";
}

static NSString *cacheArtwork(NSDictionary *info) {
    NSString *dir = NSProcessInfo.processInfo.environment[@"NP_ARTWORK_DIR"];
    NSData *data = typed(info, kArtData, NSData.class);
    NSString *ident = typed(info, kArtID, NSString.class);
    if (!dir.length || !data.length) return nil;

    // Falling back to a length-keyed name keeps artwork working for a session that
    // reports no identifier; it only costs a rewrite when the size collides.
    NSString *name = ident.length ? ident : [NSString stringWithFormat:@"len%lu", (unsigned long)data.length];
    NSString *path = [dir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.%@", name, extensionForMIME(typed(info, kArtMIME, NSString.class))]];

    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        if (![data writeToFile:path atomically:YES]) return nil;
    }
    return path;
}

void mr_run(void *my_perl, void *cv) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (!handle) { emit(@{@"error": @"dlopen"}); return; }
        MRGetInfo getInfo = (MRGetInfo)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        if (!getInfo) { emit(@{@"error": @"dlsym"}); return; }

        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        getInfo(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(NSDictionary *info) {
            NSMutableDictionary *out = [NSMutableDictionary dictionary];
            if (info.count == 0) {
                // Nothing has claimed the session, or it refused us. The caller
                // cannot tell those apart and does not need to: both mean no track.
                out[@"idle"] = @YES;
            } else {
                NSString *title = typed(info, kTitle, NSString.class);
                NSString *artist = typed(info, kArtist, NSString.class);
                NSString *album = typed(info, kAlbum, NSString.class);
                NSNumber *duration = typed(info, kDuration, NSNumber.class);
                NSNumber *elapsed = typed(info, kElapsed, NSNumber.class);
                NSNumber *rate = typed(info, kRate, NSNumber.class);
                NSDate *stamp = typed(info, kTimestamp, NSDate.class);
                NSString *art = cacheArtwork(info);

                if (title) out[@"title"] = title;
                if (artist) out[@"artist"] = artist;
                if (album) out[@"album"] = album;
                if (duration) out[@"duration"] = duration;
                if (elapsed) out[@"elapsed"] = elapsed;
                if (rate) out[@"rate"] = rate;
                // Epoch seconds, not a description: the caller advances the
                // position from this and cannot parse a localised date.
                if (stamp) out[@"timestamp"] = @(stamp.timeIntervalSince1970);
                if (art) out[@"artworkPath"] = art;
                // Cast: `&&` yields int, and @(int) serialises as 0/1 rather than
                // as a JSON boolean -- and 0 is truthy in Lua, so a paused track would
                // read as playing on the other side.
                out[@"playing"] = @((BOOL)(rate != nil && rate.doubleValue > 0));
                if (!title && !artist) out[@"idle"] = @YES;
            }
            emit(out);
            dispatch_semaphore_signal(done);
        });

        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC)) != 0)
            emit(@{@"error": @"timeout"});
    }
}
