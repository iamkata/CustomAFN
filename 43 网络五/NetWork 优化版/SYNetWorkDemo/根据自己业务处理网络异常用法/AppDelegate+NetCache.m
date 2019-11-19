//
//  AppDelegate+NetCache.m
//  ExamProject
//
//  Created by ksw on 2017/10/13.
//  Copyright © 2017年 SunYong. All rights reserved.
//  AppDelegate 添加分类统一进行缓存条件处理

#import "AppDelegate+NetCache.h"
#import "SYNetMananger.h"


@implementation AppDelegate (NetCache)

//AppDelegate 添加分类统一进行缓存条件处理和错误处理
// 配置缓存条件
- (void)configNetCacheCondition{
    
    // return YES 缓存， NO不缓存
    [SYNetMananger sharedInstance].cacheConditionBlock = ^BOOL(NSDictionary * _Nonnull result) {
     
        if([result isKindOfClass:[NSDictionary class]]){
            
            if([[result objectForKey:@"success"] intValue] == 0){
                
                return NO;
            }
        }
        
        return YES;
    };
    
}

@end
