//
//  SYHttpNetMananger.m
//  SYNetDome
//
//  Created by ksw on 2017/9/14.
//  Copyright © 2017年 ksw. All rights reserved.
//

#import "SYNetMananger.h"
#import "SYNetLocalCache.h"
#import "AFNetworking.h"


extern NSString *SYConvertMD5FromParameter(NSString *url, NSString* method, NSDictionary* paramDict);

static NSString *SYNetProcessingQueue = @"com.eoc.SunyNet";

NS_ASSUME_NONNULL_BEGIN

@interface SYNetMananger (){
    dispatch_queue_t _SYNetQueue;
}

@property (nonatomic, strong)SYNetLocalCache *cache;
@property (nonatomic, strong) NSMutableArray *batchGroups;//批处理
@property (nonatomic, strong)dispatch_queue_t SYNetQueue;
@end

@implementation SYNetMananger


- (instancetype)init
{
    self = [super init];
    if (self) {
        _SYNetQueue = dispatch_queue_create([SYNetProcessingQueue UTF8String], DISPATCH_QUEUE_CONCURRENT);
        _cache      = [SYNetLocalCache sharedInstance];
        _batchGroups = [NSMutableArray new];
    }
    return self;
}

+ (instancetype)sharedInstance
{
    static SYNetMananger *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [self new];
    });
    return instance;
}

- (void)syGetCacheWithUrl:(NSString*)urlString
               parameters:(NSDictionary * _Nullable)parameters
        completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    [self syGetWithURLString:urlString parameters:parameters ignoreCache:NO cacheDuration:NetCacheDuration completionHandler:completionHandler];
}


- (void)syPostCacheWithUrl:(NSString*)urlString
                parameters:(NSDictionary * _Nullable)parameters
         completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    [self syPostWithURLString:urlString parameters:parameters ignoreCache:NO cacheDuration:NetCacheDuration completionHandler:completionHandler];
}


- (void)syPostNoCacheWithUrl:(NSString*)urlString
                  parameters:(NSDictionary * _Nullable)parameters
           completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    [self syPostWithURLString:urlString parameters:parameters ignoreCache:YES cacheDuration:0 completionHandler:completionHandler];
    
}

- (void)syGetNoCacheWithUrl:(NSString*)urlString
                 parameters:(NSDictionary * _Nullable)parameters
          completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    [self syGetWithURLString:urlString parameters:parameters ignoreCache:YES cacheDuration:0 completionHandler:completionHandler];
}


- (void)syPostWithURLString:(NSString *)URLString
                 parameters:(NSDictionary * _Nullable)parameters
                ignoreCache:(BOOL)ignoreCache
              cacheDuration:(NSTimeInterval)cacheDuration
          completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(_SYNetQueue, ^{
        
        [weakSelf taskWithMethod:@"POST" urlString:URLString parameters:parameters ignoreCache:ignoreCache cacheDuration:cacheDuration completionHandler:completionHandler];
    });
    
}

- (void)syGetWithURLString:(NSString *)URLString
                parameters:(NSDictionary *)parameters
               ignoreCache:(BOOL)ignoreCache
             cacheDuration:(NSTimeInterval)cacheDuration
         completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(_SYNetQueue, ^{
        
        [weakSelf taskWithMethod:@"GET" urlString:URLString parameters:parameters ignoreCache:ignoreCache cacheDuration:cacheDuration completionHandler:completionHandler];
    });
}


/**
 核心方法

 @param method 请求方式
 @param urlStr 请求路径
 @param parameters 参数
 @param ignoreCache 是否不忽略缓存
 @param cacheDuration 缓存时效
 @param completionHandler 回调
 */
- (void)taskWithMethod:(NSString*)method
             urlString:(NSString*)urlStr
            parameters:(NSDictionary *)parameters
           ignoreCache:(BOOL)ignoreCache
         cacheDuration:(NSTimeInterval)cacheDuration
     completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    // 1 url+参数 生成唯一码
    NSString *fileKeyFromUrl = SYConvertMD5FromParameter(urlStr, method, parameters);
    __weak typeof(self) weakSelf = self;
    
    // 2 缓存+没失效 判断是否有有效缓存
    if (!ignoreCache && [self.cache checkIfShouldUseCacheWithCacheDuration:cacheDuration cacheKey:fileKeyFromUrl]) {
        
        NSMutableDictionary *localCache = [NSMutableDictionary dictionary];
        NSDictionary *cacheDict = [self.cache searchCacheWithUrl:fileKeyFromUrl];
        [localCache setDictionary:cacheDict];
        if (cacheDict) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // 没有进行网络请求也回调异常block
                if (weakSelf.exceptionBlock) {
                    weakSelf.exceptionBlock(nil, localCache);
                }
                // 将缓存数据回调过去
                completionHandler(nil, YES, localCache); //error isCache result
            });
            return;
        }
    }
    
    // 5 处理网络返回来的数据，即缓存处理, 或者直接写个方法也可以
    SYRequestCompletionHandler newCompletionBlock = ^( NSError* error,  BOOL isCache, NSDictionary* result){
        //5.1处理缓存  ⚠️参数ignoreCache(网络task发起前，是否从本来缓存中获取数据)  cacheDuration(网络task结束后，是否对网络数据缓存)
        result = [NSMutableDictionary dictionaryWithDictionary:result];
        if (cacheDuration > 0) {// 缓存时效(即缓存时间)大于0
            if (result) {
                //存入缓存的条件block (比如:如果服务器数据有问题就不存入缓存)
                if (weakSelf.cacheConditionBlock) {
                    if (weakSelf.cacheConditionBlock(result)) { //根据result判断是否符合条件
                        [weakSelf.cache saveCacheData:result forKey:fileKeyFromUrl];
                    }
                }else{
                    [weakSelf.cache saveCacheData:result forKey:fileKeyFromUrl];
                }
            }
        }
        
        //5.2 其他情况异常回调
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.exceptionBlock) {
                weakSelf.exceptionBlock(error, (NSMutableDictionary*)result);
            }
            completionHandler(error, NO, result);
        });
    };
    
    //3  发起AF网络任务
    NSURLSessionTask *task = nil;
    if ([method isEqualToString:@"GET"]) {
        task = [self.afHttpManager  GET:urlStr parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            /*
             4 处理数据 （处理数据的时候，需要处理下载的网络数据是否要缓存）
             这里可以直接使用 completionHandler，如果这样，网络返回的数据没有做缓存处理机制
             */
            newCompletionBlock(nil,NO, responseObject);
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            newCompletionBlock(error,NO, nil);;
        }];
    }else{
        task = [self.afHttpManager POST:urlStr parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            newCompletionBlock(nil,NO, responseObject);
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            newCompletionBlock(error,NO, nil);
        }];
    }
    
    [task resume];
}

- (AFHTTPSessionManager*)afHttpManager{
    
    AFHTTPSessionManager *afManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    return afManager;
}

//获取任务对象SYNetRequestInfo
- (SYNetRequestInfo*)syNetRequestWithURLStr:(NSString *)URLString
                                     method:(NSString*)method
                                 parameters:(NSDictionary *)parameters
                                ignoreCache:(BOOL)ignoreCache
                              cacheDuration:(NSTimeInterval)cacheDuration
                          completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    SYNetRequestInfo *syNetRequestInfo = [SYNetRequestInfo new];
    syNetRequestInfo.urlStr = URLString;
    syNetRequestInfo.method = method;
    syNetRequestInfo.parameters = parameters;
    syNetRequestInfo.ignoreCache = ignoreCache;
    syNetRequestInfo.cacheDuration = cacheDuration;
    syNetRequestInfo.completionBlock = completionHandler;
    return syNetRequestInfo;
}

//多网络任务异步  (自己思考如何实现多网络任务同步)
//tasks数组里面拿到任务, 使用dispatch_group_t执行
- (void)syBatchOfRequestOperations:(NSArray<SYNetRequestInfo *> *)tasks
                     progressBlock:(void (^)(NSUInteger numberOfFinishedTasks, NSUInteger totalNumberOfTasks))progressBlock
                   completionBlock:(netSuccessbatchBlock)completionBlock{
    
    /*
     使用 dispatch_group_t 技术点
     dispatch_group_enter: 对group里面的任务数 +1
     dispatch_group_leave: 任务完成后,对group里面的任务数 -1
     dispatch_group_notify: 当group的任务数为0了，就会执行notify的block块操作，即所有的网络任务请求完了。
     */
    __weak typeof(self) weakSelf = self;
    dispatch_async(_SYNetQueue, ^{
        
        __block dispatch_group_t group = dispatch_group_create();
        [weakSelf.batchGroups addObject:group];
        
        __block NSInteger finishedTasksCount = 0;
        __block NSInteger totalNumberOfTasks = tasks.count;
        
        [tasks enumerateObjectsUsingBlock:^(SYNetRequestInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            if (obj) {
                
                // 网络任务启动前dispatch_group_enter
                dispatch_group_enter(group);
                
                SYRequestCompletionHandler newCompletionBlock = ^( NSError* error,  BOOL isCache, NSDictionary* result){
                    
                    //先执行进度block
                    progressBlock(finishedTasksCount, totalNumberOfTasks);
                    
                    //再执行完成block
                    if (obj.completionBlock) {
                        obj.completionBlock(error, isCache, result);
                    }
                    // 网络任务结束后dispatch_group_enter
                    dispatch_group_leave(group);
                    
                };
                
                if ([obj.method isEqual:@"POST"]) {
                    
                    [[SYNetMananger sharedInstance] syPostWithURLString:obj.urlStr parameters:obj.parameters ignoreCache:obj.ignoreCache cacheDuration:obj.cacheDuration completionHandler:newCompletionBlock];
                    
                }else{
                    
                    [[SYNetMananger sharedInstance] syGetWithURLString:obj.urlStr parameters:obj.parameters ignoreCache:obj.ignoreCache cacheDuration:obj.cacheDuration completionHandler:newCompletionBlock];
                }
                
            }
            
        }];
        
        //监听
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [weakSelf.batchGroups removeObject:group];
            if (completionBlock) {
                completionBlock(tasks);
            }
        });
    });
}

@end

NS_ASSUME_NONNULL_END

