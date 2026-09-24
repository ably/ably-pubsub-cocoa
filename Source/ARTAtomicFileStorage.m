#import "ARTAtomicFileStorage.h"
#import "ARTInternalLog.h"

@implementation ARTAtomicFileStorage {
    ARTInternalLog *_logger;
    NSLock *_lock;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL logger:(nullable ARTInternalLog *)logger {
    if (self = [super init]) {
        _fileURL = [fileURL copy];
        _logger = logger;
        _lock = [[NSLock alloc] init];
        _lock.name = @"io.ably.ARTAtomicFileStorage";
    }
    return self;
}

- (BOOL)fileExists {
    [_lock lock];
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:_fileURL.path];
    [_lock unlock];
    return exists;
}

- (NSDictionary<NSString *, id> *)load {
    [_lock lock];
    NSDictionary *result = [self load_nosync];
    [_lock unlock];
    return result;
}

- (NSDictionary<NSString *, id> *)load_nosync {
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:_fileURL options:0 error:&readError];
    if (data == nil) {
        if (readError.code != NSFileReadNoSuchFileError) {
            ARTLogWarn(_logger, @"ARTAtomicFileStorage: could not read %@: %@", _fileURL.lastPathComponent, readError.localizedDescription);
        }
        return @{};
    }

    NSError *parseError = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&parseError];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        ARTLogError(_logger, @"ARTAtomicFileStorage: %@ is not a dictionary plist (%@); treating as empty", _fileURL.lastPathComponent, parseError.localizedDescription);
        return @{};
    }
    return plist;
}

- (BOOL)save:(NSDictionary<NSString *, id> *)dictionary error:(NSError * _Nullable * _Nullable)outError {
    [_lock lock];
    @try {
        NSError *serializeError = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:dictionary
                                                                  format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0
                                                                   error:&serializeError];
        if (data == nil) {
            if (outError) *outError = serializeError;
            ARTLogError(_logger, @"ARTAtomicFileStorage: failed to serialise %@: %@", _fileURL.lastPathComponent, serializeError.localizedDescription);
            return NO;
        }

        NSError *dirError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:[_fileURL URLByDeletingLastPathComponent]
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&dirError]) {
            if (outError) *outError = dirError;
            ARTLogError(_logger, @"ARTAtomicFileStorage: failed to create parent directory for %@: %@", _fileURL.lastPathComponent, dirError.localizedDescription);
            return NO;
        }

        // IMPORTANT; DO NOT REMOVE: We use NSDataWritingFileProtectionNone
        // because the file must be always available to load. This is our
        // solution to issues that we previously had when storing data as
        // "protected until first user authentication"; there are scenarios in
        // which iOS applications get launched before a first unlock and the
        // LocalDevice data needs to still be loadable in these scenarios.
        NSDataWritingOptions options = NSDataWritingAtomic | NSDataWritingFileProtectionNone;

        NSError *writeError = nil;
        BOOL ok = [data writeToURL:_fileURL options:options error:&writeError];
        if (!ok) {
            if (outError) *outError = writeError;
            ARTLogError(_logger, @"ARTAtomicFileStorage: failed to write %@: %@", _fileURL.lastPathComponent, writeError.localizedDescription);
            return NO;
        }

        // Make sure the file is excluded from iCloud backup — the device
        // secret was previously protected with `ThisDeviceOnly` keychain
        // semantics, and we want to preserve the "doesn't leave this device"
        // property even though we've moved away from the keychain.
        NSURL *mutableURL = [_fileURL copy];
        NSError *attrError = nil;
        if (![mutableURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&attrError]) {
            ARTLogWarn(_logger, @"ARTAtomicFileStorage: could not mark %@ as excluded from backup: %@", _fileURL.lastPathComponent, attrError.localizedDescription);
        }

        return YES;
    }
    @finally {
        [_lock unlock];
    }
}

@end
