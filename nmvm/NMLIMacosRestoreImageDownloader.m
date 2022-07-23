//
//  NMLIMacosRestoreImageDownloader.m
//  NMLIVM
//
//  Created by nomadli on 2022/7/21.
//

#import <Foundation/Foundation.h>
#import <Virtualization/Virtualization.h>
#import <pthread.h>
#import "NMLIVM.h"

#ifdef __arm64__

NS_ASSUME_NONNULL_BEGIN

@interface NMLIMacosRestoreImageDownloader : NSObject <NSURLSessionDownloadDelegate> {
    @public
    pthread_mutex_t mutx;
}
@property(nonatomic, strong) NSURLSession       *session;
@property(nonatomic, strong) NSURL              *des;
@property(nonatomic, assign) int                code;
@end

NS_ASSUME_NONNULL_END

@implementation NMLIMacosRestoreImageDownloader
- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context
{
    if ([keyPath isEqualToString:@"fractionCompleted"] && [object isKindOfClass:[NSProgress class]]) {
        NSProgress *prg = (NSProgress*)object;
        printf("\033[A\033[KRestore image download progress: %.2f%%.\n", prg.fractionCompleted * 100);
        
        if (prg.finished) {
            [prg removeObserver:self forKeyPath:@"fractionCompleted"];
        }
    }
}

- (void)dealloc {
    pthread_mutex_destroy(&mutx);
}

- (void)URLSession:(NSURLSession*)session downloadTask:(NSURLSessionDownloadTask*)downloadTask
didFinishDownloadingToURL:(NSURL*)location
{
    NSURL *path = [_des URLByAppendingPathComponent:[location lastPathComponent]];
    NSError *err;
    if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:path error:&err]) {
        NMLI_LOG_VAR("Failed to move image frome %s to %s\n", location.path.UTF8String, path.path.UTF8String);
        _code = -2;
    } else {
        _code = 0;
    }
    pthread_mutex_unlock(&mutx);
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task
didCompleteWithError:(nullable NSError*)err
{
    if (err == nil) {
        NMLI_LOG("Failed to download restore image. no error message\n");
        pthread_mutex_unlock(&mutx);
        _code = -3;
        return;
    }
    if ([err.localizedDescription isEqualToString:@"cancelled"]) {
        NMLI_LOG("User cancelled the download\n");
        pthread_mutex_unlock(&mutx);
        _code = -4;
        return;
    }
    NMLI_LOG_VAR("Failed to download restore image. %s\n", err.localizedDescription.UTF8String);
    if ([err.userInfo objectForKey:NSURLSessionDownloadTaskResumeData] == nil) {
        printf("Download can't continue\n");
        pthread_mutex_unlock(&mutx);
        _code = -5;
        return;
    }
    
    [[_session downloadTaskWithResumeData:err.userInfo[NSURLSessionDownloadTaskResumeData]] resume];
}
@end

extern int download_macos_restore_image(NMLIVM *vm) {
    @autoreleasepool {
        NMLIMacosRestoreImageDownloader *mrid = [[NMLIMacosRestoreImageDownloader alloc] init];
        pthread_mutex_init(&(mrid->mutx), NULL);
        pthread_mutex_lock(&(mrid->mutx));
        [VZMacOSRestoreImage fetchLatestSupportedWithCompletionHandler:^(VZMacOSRestoreImage *img,
                                                                         NSError *err) {
            if (err != nil) {
                NMLI_LOG_VAR("Failed to fetch latest supported restore image catalog. %s\n", err.localizedDescription.UTF8String);
                pthread_mutex_unlock(&(mrid->mutx));
                mrid.code = -1;
                return;
            }
            
            NSURLSessionConfiguration *cnf =
            [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:[NSString stringWithUTF8String:vm->vm]];
            cnf.allowsCellularAccess = NO;
            
            NSUInteger cpu_count = [[NSProcessInfo processInfo] processorCount];
            NSOperationQueue *queue = [[NSOperationQueue alloc] init];
            queue.maxConcurrentOperationCount = cpu_count > 2 ? cpu_count - 1 : 1;
            
            
            mrid.des = [NSURL fileURLWithPath:[NSString stringWithUTF8String:vm->rimg]];
            mrid.session = [NSURLSession sessionWithConfiguration:cnf delegate:mrid delegateQueue:queue];
            
            printf("Attempting to download the latest available restore image. %s\n", img.URL.absoluteString.UTF8String);
            printf("Restore image download progress: %.2f%%.\n", 0.0);
            NSURLSessionDownloadTask *dt = [[NSURLSession sharedSession] downloadTaskWithURL:img.URL];
            [dt.progress addObserver:mrid
                          forKeyPath:@"fractionCompleted"
                             options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                             context:nil];
            [dt resume];
        }];
        pthread_mutex_lock(&(mrid->mutx));
        return mrid.code;
    }
}

#else

extern int download_macos_restore_image(NMLIVM *vm) {return 0;}

#endif//__arm64__
